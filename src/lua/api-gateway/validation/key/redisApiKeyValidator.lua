-- The default implementation that validates if an API-KEY is authorized to proceed with the request.
-- NOTE: This implementation assumes ngx.var.key is set beforehand, and likewise for ngx.var.service_id
-- If the API-KEY is valid, it returns the value in the cache, else it returns ngx.HTTP_NOT_FOUND

-- Dependencies:
--   1. ngx.var.key needs to be set
--   2. ngx.var.service_id needs to be set
--   3. ngx.var.redis_backend needs to be set
--
-- User: ddascal
-- Date: 11/22/13
-- Time: 2:55 PM
-- Moved on
-- Date: 15/04/14
-- Time: 15:49
--
local BaseValidator = require "api-gateway.validation.validator"
local cjson = require "cjson"
local redis = require "resty.redis"
local RedisHealthCheck = require "api-gateway.redis.redisHealthCheck"

local ApiKeyValidator = BaseValidator:new()

local RESPONSES = {
        MISSING_KEY   = { error_code = "403000", message = "Api KEY is missing"        },
        INVALID_KEY   = { error_code = "403003", message = "Api KEY is invalid"        },
        UNKNOWN_ERROR = { error_code = "503000", message = "Could not validate API KEY"}
}

function ApiKeyValidator:getKeyFromRedis(hashed_key)
    local redis_key = "cachedkey:" .. hashed_key;
    local red = redis:new();

    local redis_host, redis_port = self:getRedisUpstream()
    local ok, err = red:connect(redis_host, redis_port)
    if ok then

        --local selectresult, selecterror = red:hgetall(redis_key);
        -- these are the fields to be saved in the request variables.
        -- NOTE: all the fields have to be defined before in nginx configuration file like : set $realm 'default_value';
        local fields =                                        {"key", "realm", "service_id", "service_name", "consumer_org_name", "app_name", "plan_name", "key_secret" }
        local selectresult, selecterror = red:hmget(redis_key, "key", "realm", "service-id", "service-name", "consumer-org-name", "app-name", "plan-name", "key_secret")
        red:set_keepalive(30000, 100);
        if selectresult then
            local api_key_obj = {}
            if selectresult and type(selectresult) == "table" then
                local found = 0
                for i,v in ipairs(selectresult) do
                    if type(v) == "string" then
                        found = 1
                        api_key_obj[fields[i]] = v
                    end
                end
                if ( found == 0 ) then
                    return ngx.HTTP_NOT_FOUND;
                end
                --ngx.log(ngx.WARN, "JSON:" .. cjson.encode(json_output) )
            else
                return ngx.HTTP_NOT_FOUND
            end
            return api_key_obj;
        end
    else
        ngx.log(ngx.WARN, "Could not connect to redis at[" .. redis_host .. ":" .. redis_port .. "]:", err);
        return ngx.HTTP_SERVICE_UNAVAILABLE;
    end
end


function ApiKeyValidator:validate_api_key()
    local api_key = ngx.ctx.key or ngx.var.key
    local service_id = ngx.ctx.service_id or ngx.var.service_id

    -- Block the requests if there is no apikey --
    if api_key == nil or api_key == "" or api_key == true then
        ngx.log(ngx.WARN, "Api Key not found as a part of the request")
        --return self:exitFn(ngx.HTTP_BAD_REQUEST)
        return self:exitFn(RESPONSES.MISSING_KEY.error_code, cjson.encode(RESPONSES.MISSING_KEY))
    end

    local hashedkey = api_key .. ":" .. service_id

    -- 1. use http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT to read data from

    -- 2. else get it from Redis and store it in the local memcached
    local local_key = self:getKeyFromLocalCache(hashedkey, "cachedkeys")
    if (nil ~= local_key) then
        -- decode json and set context properties
        local jsonKey = cjson.decode(local_key)
        self:setContextProperties(jsonKey)
        return self:exitFn(ngx.HTTP_OK, '{"valid":true}')
    end

    local redis_key = self:getKeyFromRedis(hashedkey);
    if (redis_key == ngx.HTTP_NOT_FOUND ) then
        --return self:exitFn(ngx.HTTP_FORBIDDEN)
        return self:exitFn(RESPONSES.INVALID_KEY.error_code, cjson.encode(RESPONSES.INVALID_KEY))
    end
    if ( redis_key == ngx.HTTP_SERVICE_UNAVAILABLE ) then
        --return self:exitFn(ngx.HTTP_SERVICE_UNAVAILABLE)
        return self:exitFn(RESPONSES.UNKNOWN_ERROR.error_code, cjson.encode(RESPONSES.UNKNOWN_ERROR))
    end
    -- at this moment the key exists in Redis
    self:setContextProperties(redis_key)
    self:setKeyInLocalCache(hashedkey, cjson.encode(redis_key), 120, "cachedkeys")
    -- DO NOT EXPOSE ANY VARIABLE ASSOCIATED TO THE KEY
    return self:exitFn(ngx.HTTP_OK, '{"valid":true}')
end

function ApiKeyValidator:validateRequest(obj)
    return self:validate_api_key();
end

return ApiKeyValidator



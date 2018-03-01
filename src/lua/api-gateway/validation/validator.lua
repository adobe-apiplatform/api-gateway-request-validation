-- Copyright (c) 2015 Adobe Systems Incorporated. All rights reserved.
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the "Software"),
--   to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense,
--   and/or sell copies of the Software, and to permit persons to whom the
--   Software is furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--   DEALINGS IN THE SOFTWARE.


--
-- Base class for Gateway validators
--
-- User: ddascal
-- Date: 12/03/13
-- Time: 18:01
--
-- Dependencies:
--   1. api-gateway-redis upstream needs to be set
--   2. api-gateway-redis-replica needs to be set
--
local base = require "api-gateway.validation.base"
local RedisHealthCheck = require "api-gateway.redis.redisHealthCheck"
local cjson = require "cjson"
local debug_mode = ngx.config.debug

local RedisConnectionProvider = require "api-gateway.redis.redisConnectionProvider"

-- class to be used as a base class for all api-gateway validators --
local BaseValidator = {}
local redisHealthCheck = RedisHealthCheck:new({
    shared_dict = "cachedkeys"
})

local redisConnectionProvider = RedisConnectionProvider:new()

function BaseValidator:new(o)
    local o = o or {}
    self.redis_RO_upstream = self.redis_RO_upstream or "api-gateway-redis-replica"
    self.redis_RW_upstream = self.redis_RW_upstream or "api-gateway-redis"
    self.redis_pass_env = self.redis_pass_env or "REDIS_PASS_API_KEY"
    self.log_identifier = self.log_identifier or nil
    setmetatable(o, self)
    self.__index = self
    return o
end

function BaseValidator:getVersion()
    return base.version;
end

function BaseValidator:debug(...)
    -- print("debug mode: ", debug_mode)
    if debug_mode then
        ngx.log(ngx.DEBUG, "validator: ", ...)
    end
end

function BaseValidator:getKeyFromLocalCache(key, dict_name)
    local localCachedKeys = ngx.shared[dict_name];
    if (nil ~= localCachedKeys) then
        return localCachedKeys:get(key);
    else
        ngx.log(ngx.ERR, "Dictionary " .. dict_name .. " does not exist")
    end
end

function BaseValidator:setKeyInLocalCache(key, string_value, exptime, dict_name)
    local localCachedKeys = ngx.shared[dict_name];
    if (nil ~= localCachedKeys) then
        return localCachedKeys:safe_set(key, string_value, exptime);
    else
        ngx.log(ngx.ERR, "Dictionary " .. dict_name .. " does not exist")
    end
end

function BaseValidator:deleteKeyInLocalCache(key, dict_name)
    local localCachedKeys = ngx.shared[dict_name]

    if (nil ~= localCachedKeys) then
        ngx.log(ngx.DEBUG, "Deleting entry with key " .. key .. " from local cache [" .. dict_name .. "]")
        return localCachedKeys:delete(key)
    else
        ngx.log(ngx.ERR, "Dictionary " .. dict_name .. " does not exist")
    end
end

-- TODO: remove this if no more usage
function BaseValidator:getRedisUpstream(upstream_name)
    local n = upstream_name or self.redis_RO_upstream
    local upstream, host, port = redisHealthCheck:getHealthyRedisNode(n)
    ngx.log(ngx.DEBUG, "Obtained Redis Host:" .. tostring(host) .. ":" .. tostring(port), " from upstream:", n)
    if (nil ~= host and nil ~= port) then
        return host, port
    end

    ngx.log(ngx.ERR, "Could not find a Redis upstream.")
    return nil, nil
end


-- retrieves a saved information from the Redis cache --
-- the method uses GET redis command --
-- it returns the value of the key, when found in the cache, nil otherwise --
-- for backward compatibility this method accepts a second argument, in which case it will perform a HGET instead.
function BaseValidator:getKeyFromRedis(key, hash_name)

    if hash_name ~= nil then
        return self:getHashValueFromRedis(key, hash_name)
    end

    local connection_options = {
        upstream = self.redis_RO_upstream,
        password = os.getenv(self.redis_pass_env)
    }

    local ok, redisread = redisConnectionProvider:getConnection(connection_options);
    if ok then
        local result, err = redisread:get(key)
        redisConnectionProvider:closeConnection(redisread)
        if (not result and err ~= nil) then
            ngx.log(ngx.WARN, "Failed to read key " .. tostring(key) .. ". Error:", err)
            return nil
        else
            if (type(result) == 'string') then
                return result
            else
                ngx.log(ngx.WARN, "type of result is not correct " .. tostring(type(result)))
            end
        end
    end
    return nil;
end

-- retrieves a saved information from the Redis cache --
-- the method uses HGET redis command --
-- it returns the value of the key, when found in the cache, nil otherwise --
function BaseValidator:getHashValueFromRedis(key, hash_field)
    local connection_options = {
        upstream = self.redis_RO_upstream,
        password = os.getenv(self.redis_pass_env)
    }

    local ok, redisread = redisConnectionProvider:getConnection(connection_options);
    if ok then
        local redis_key, selecterror = redisread:hget(key, hash_field)
        redisConnectionProvider:closeConnection(redisread)
        if (type(redis_key) == 'string') then
            return redis_key
        elseif selecterror then
            ngx.log(ngx.ERR, "failed to get key from redis ", tostring(key), " error: ", selecterror)
        end
    end
    return nil;
end


-- is wrapper over redis exists  but returns boolean instead
function BaseValidator:exists(key)
    local connection_options = {
        upstream = self.redis_RO_upstream,
        password = os.getenv(self.redis_pass_env)
    }

    local ok, redisread = redisConnectionProvider:getConnection(connection_options);
    if ok then
        local redis_key, selecterror = redisread:exists(key)
        redisConnectionProvider:closeConnection(redisread)
        if selecterror or redis_key ~= 1 then
            ngx.log(ngx.WARN, "Failed to read key " .. key .. " from Redis cache ", selecterror)
            return false
        end
        return true;
    end
    return false
end

-- saves a value into the redis cache. --
-- the method uses HSET redis command --
-- it retuns true if the information is saved in the cache, false otherwise --
function BaseValidator:setKeyInRedis(key, hash_name, keyexpires, value)
    ngx.log(ngx.DEBUG, "Storing in Redis the key [", tostring(key), "], expireat=", tostring(keyexpires), ", value=", tostring(value))
    local connection_options = {
        upstream = self.redis_RW_upstream,
        password = os.getenv(self.redis_pass_env)
    }

    local ok, rediss = redisConnectionProvider:getConnection(connection_options);
    if ok then
        --ngx.log(ngx.DEBUG, "WRITING IN REDIS JSON OBJ key=" .. key .. "=" .. value .. ",expiring in:" .. (keyexpires - (os.time() * 1000)) )
        rediss:init_pipeline()
        rediss:hset(key, hash_name, value)
        if keyexpires ~= nil then
            rediss:pexpireat(key, keyexpires)
        end
        local _, commit_err = rediss:commit_pipeline()
        redisConnectionProvider:closeConnection(rediss)
        --ngx.log(ngx.WARN, "SAVE RESULT:" .. cjson.encode(commit_res) )
        if (commit_err == nil) then
            return true
        else
            ngx.log(ngx.WARN, "Failed to write the key [", key, "] in Redis. Error:", commit_err)
        end
    end
    return false;
end

function BaseValidator:deleteKeyFromRedis(key)
    ngx.log(ngx.DEBUG, "Deleting key from Redis: " .. key)
    local connection_options = {
        upstream = self.redis_RW_upstream,
        password = os.getenv(self.redis_pass_env)
    }

    local ok, redis = redisConnectionProvider:getConnection(connection_options);
    if ok then
        local redisResponse, err = redis:del(key)
        if err then
            ngx.log(ngx.ERR, "Error while deleting key from redis: ", err)
            return nil
        end
        return redisResponse
    end
end

-- it accepts a table or a string and saves the properties into the current request context --
function BaseValidator:setContextProperties(cached_token)
    local jsonCacheObj = cached_token
    if (type(cached_token) == 'string') then
        jsonCacheObj = cjson.decode(cached_token)
    end

    for k, v in pairs(jsonCacheObj) do
        ngx.ctx[k] = v
        self:debug("Setting ngx.ctx." .. tostring(k) .. "=" .. tostring(v))
    end
end

-- TTL using LuaResty Redis
function BaseValidator:executeTtl(key)
    local connection_options = {
        upstream = self.redis_RO_upstream,
        password = os.getenv(self.redis_pass_env)
    }

    local ok, redis = redisConnectionProvider:getConnection(connection_options);
    if ok then
        ngx.log(ngx.DEBUG, "Executing TTL for key:" .. key)
        local ttl, err = redis:ttl(key)
        if not ttl then
            ngx.log(ngx.ERR, "Could not execute TTL for key: " .. key .. ". Error: " .. err)
        else
            ngx.log(ngx.DEBUG, "TTL response: " .. ttl)
            return ttl
        end
    end
end


-- generic exit function for a validator --
function BaseValidator:exitFn(status, resp_body)
    local responseTime = ngx.now() - ngx.req.start_time()
    ngx.header["Response-Time"] = responseTime

    if(self.log_identifier) then
        if(ngx.var[self.log_identifier]) then
            ngx.var[self.log_identifier] = string.format("%.3f", responseTime)
        else
            ngx.log(ngx.WARN, "ngx variable ", self.log_identifier , " is not declared in ngx conf")
        end
    end

    ngx.status = status

    if (ngx.null ~= resp_body) then
        ngx.say(resp_body)
    end

    return ngx.OK
end

function BaseValidator:overrideErrorResponses(custom_error_responses)

    --- handle the case when custom_error_responses is passed as string
    if type(custom_error_responses) == "string" then
        custom_error_responses = cjson.decode(custom_error_responses)
    end

    if custom_error_responses ~= nil and type(custom_error_responses) == "table" then

        local existing_custom_error_responses = ngx.var.validator_custom_error_responses
        if existing_custom_error_responses ~= nil and existing_custom_error_responses ~= "" then
            ngx.log(ngx.DEBUG, "ngx.var.validator_custom_error_responses already exist. Going to merge...")

            existing_custom_error_responses = cjson.decode(existing_custom_error_responses)
            for k, v in pairs(custom_error_responses) do
                if (existing_custom_error_responses[k] == nil) then
                    existing_custom_error_responses[k] = v
                end
            end

            ngx.var.validator_custom_error_responses = cjson.encode(existing_custom_error_responses)
        else

            ngx.var.validator_custom_error_responses = cjson.encode(custom_error_responses)
        end
    else
        ngx.log(ngx.DEBUG, "No custom error responses defined for validator")
    end
end

return BaseValidator
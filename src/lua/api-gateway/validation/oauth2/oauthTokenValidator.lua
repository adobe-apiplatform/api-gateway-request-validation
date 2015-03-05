--
-- Validates an OAuth 2 token
-- User: ddascal
-- Date: 03/03/14
-- Time: 18:12
-- It returns ngx.HTTP_OK when token is valid or ngx.HTTP_UNAUTHORIZED otherwise.
--
-- Dependencies:
--   1. ngx.var.oauth_host needs to be set
--   2. ngx.var.authtoken needs to be set
--   3. ngx.var.redis_backend needs to be set
--   4. location /validate-token defined
--   5. lua_shared_dict cachedOauthTokens 50m;
--
-- Properties that can be set:
--  1. oauth_token_scope
--  2. oauth_token_client_id
--  3. oauth_token_user_id

local BaseValidator = require "api-gateway.validation.validator"
local cjson = require "cjson"
local redis = require "resty.redis"

local _M = BaseValidator:new()

local RESPONSES = {
    MISSING_TOKEN = { error_code = "403010", message = "Oauth token is missing" },
    INVALID_TOKEN = { error_code = "401013", message = "Oauth token is not valid" },
    -- TOKEN_MISSMATCH is reserved for classes overwriting the isTokenValid method
    TOKEN_MISSMATCH = { error_code = "401014", message = "Token not allowed in the current context" },
    SCOPE_MISMATCH = { error_code = "401015", message = "Scope mismatch" },
    UNKNOWN_ERROR = { error_code = "503010", message = "Could not validate the oauth token" }
}

-- Hook to override the logic verifying if a token is valid
function _M:istokenValid(json)
    return json.valid or false, RESPONSES.INVALID_TOKEN
end

-- override this if other checks need to be in place
function _M:isCachedTokenValid(json)
    return true
end

-- returns the key that should be used when looking up in the cache --
function _M:getOauthTokenForCaching(token, oauth_host)
    local t = token;
    if (oauth_host) then
        return "cachedoauth:" .. t .. ":" .. oauth_host;
    else
        return "cachedoauth:" .. t;
    end
end

function _M:storeTokenInCache(cacheLookupKey, cachingObj, expire_at)
    local cachingObjString = cjson.encode(cachingObj)

    self:setKeyInLocalCache(cacheLookupKey, cachingObjString, 60, "cachedOauthTokens")
    self:setKeyInRedis(cacheLookupKey, "token_json", expire_at, cachingObjString)
end

-- TODO: cache invalid tokens too for a short while
-- Check in the response if the token is valid --
function _M:checkResponseFromAuth(res, cacheLookupKey)
    local json = cjson.decode(res.body)
    if json ~= nil then

        local tokenValidity, error = self:istokenValid(json)
        if not tokenValidity and error ~= nil then
            return tokenValidity, error
        end
        if tokenValidity and json.token ~= nil then
            local cachingObj = {}
            cachingObj.oauth_token_scope = json.token.scope
            cachingObj.oauth_token_client_id = json.token.client_id
            cachingObj.oauth_token_user_id = json.token.user_id

            self:setContextProperties(cachingObj)
            self:storeTokenInCache(cacheLookupKey, cachingObj, json.expires_at)
            return true
        end
    end

    return false
end

function _M:getTokenFromCache(cacheLookupKey)

    local localCacheValue = self:getKeyFromLocalCache(cacheLookupKey, "cachedOauthTokens")
    if (localCacheValue ~= nil) then
        ngx.log(ngx.DEBUG, "Found IMS token in local cache")
        return localCacheValue
    end

    local redisCacheValue = self:getKeyFromRedis(cacheLookupKey, "token_json")
    if (redisCacheValue ~= nil) then
        ngx.log(ngx.DEBUG, "Found IMS token in redis cache")
        self:setKeyInLocalCache(cacheLookupKey, redisCacheValue, 60, "cachedOauthTokens")
        return redisCacheValue
    end
    return nil;
end

-- imsAuth will validate the service token passed in "Authorization" header --
function _M:validate_ims_token()
    local oauth_host = ngx.var.oauth_host
    local oauth_token = ngx.var.authtoken

    -- ngx.var.authtoken needs to be set before calling this method
    if oauth_token == nil or oauth_token == "" then
        return self:exitFn(RESPONSES.MISSING_TOKEN.error_code, cjson.encode(RESPONSES.MISSING_TOKEN))
    end

    --1. try to get token info from the cache first ( local or redis cache )
    local oauth_token_hash = ngx.md5(oauth_token)
    local cacheLookupKey = self:getOauthTokenForCaching(oauth_token_hash, oauth_host)
    local cachedToken = self:getTokenFromCache(cacheLookupKey)

    if (cachedToken ~= nil) then
        -- ngx.log(ngx.WARN, "Cached token=" .. cachedToken)
        local obj = cjson.decode(cachedToken)
        local tokenValidity, error = self:isCachedTokenValid(obj)
        if tokenValidity then
            self:setContextProperties(obj)
            return self:exitFn(ngx.HTTP_OK)
        end
        -- at this point the cached token is not valid
        ngx.log(ngx.WARN, "Invalid OAuth Token found in cache. OAuth host=" .. tostring(oauth_host))
        if (error == nil) then
            error = RESPONSES.INVALID_TOKEN
        end
        error.error_code = error.error_code or RESPONSES.INVALID_TOKEN.error_code
        return self:exitFn(error.error_code, cjson.encode(error))
    end

    -- 2. validate the token with the OAuth endpoint
    local res = ngx.location.capture("/validate-token", { share_all_vars = true })
    if res.status == ngx.HTTP_OK then
        local tokenValidity, error = self:checkResponseFromAuth(res, cacheLookupKey)
        if (tokenValidity == true) then
            return self:exitFn(ngx.HTTP_OK)
        end
        -- at this point the token is not valid
        ngx.log(ngx.WARN, "Invalid OAuth Token returned. OAuth host=" .. tostring(oauth_host))
        if (error == nil) then
            error = RESPONSES.INVALID_TOKEN
        end
        error.error_code = error.error_code or RESPONSES.INVALID_TOKEN.error_code
        return self:exitFn(error.error_code, cjson.encode(error))
    end
    return self:exitFn(res.status, cjson.encode(RESPONSES.UNKNOWN_ERROR));
end

function _M:validateRequest(obj)
    return self:validate_ims_token()
end


return _M


-- Copyright (c) 2018 Adobe Systems Incorporated. All rights reserved.
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
-- Validates an OAuth 2 token
-- User: ddascal
-- Date: 03/03/14
-- Time: 18:12
-- It returns ngx.HTTP_OK when token is valid or ngx.HTTP_UNAUTHORIZED otherwise.
--
-- Dependencies:
--   1. ngx.var.oauth_host needs to be set
--   2. ngx.var.authtoken needs to be set
--   3. location /validate-token defined
--   4. lua_shared_dict cachedOauthTokens 50m;
--
-- Properties that can be set:
--  1. oauth_token_scope
--  2. oauth_token_client_id
--  3. oauth_token_user_id
--  4. oauth_token_expires_at

local BaseValidator = require "api-gateway.validation.validator"
local redisConfigurationProvider = require "api-gateway.redis.redisConnectionConfiguration"
local OauthClient = require "api-gateway.util.OauthClient":new()
local cjson = require "cjson"
local hasher = require "api-gateway.util.hasher"
local safeCjson = require "cjson.safe"

local _M = BaseValidator:new({
    RESPONSES = {
        MISSING_TOKEN = { error_code = "403010", message = "Oauth token is missing" },
        INVALID_TOKEN = { error_code = "401013", message = "Oauth token is not valid" },
        -- TOKEN_MISSMATCH is reserved for classes overwriting the isTokenValid method
        TOKEN_MISSMATCH = { error_code = "401014", message = "Token not allowed in the current context" },
        SCOPE_MISMATCH = { error_code = "401015", message = "Scope mismatch" },
        UNKNOWN_ERROR = { error_code = "503010", message = "Could not validate the oauth token" }
    }
})

_M["redis_RO_upstream"] = redisConfigurationProvider["oauth"]["ro_upstream_name"]
_M["redis_RW_upstream"] = redisConfigurationProvider["oauth"]["rw_upstream_name"]
_M["redis_pass_env"] = redisConfigurationProvider["oauth"]["env_password_variable"]
_M["log_identifier"] = "oauth_validator_execution_time";

---
-- Maximum time in seconds specifying how long to cache a valid token in GW's memory
local LOCAL_CACHE_TTL = 60
---
-- Maximum time in milliseconds specifying how long to cache a valid token in Redis
local REDIS_CACHE_TTL = 6 * 60 * 60

-- Hook to override the logic verifying if a token is valid
function _M:isTokenValid(json)
    return json.valid or false, self.RESPONSES.INVALID_TOKEN
end

-- override this if other checks need to be in place

--- Returns a number specifying how long the token is valid. If the value is 0 or less the token is expired
-- @param json Token info object
--
function _M:isCachedTokenValid(json)
    if (json == nil) then
        return -1
    end
    local expires_in_s = self:getExpiresIn(json.oauth_token_expires_at)
    return expires_in_s
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

--- Converts the expire_at into expire_in in seconds
-- @param expire_at UTC expiration time in seconds
--
function _M:getExpiresIn(expire_at)
    if (expire_at == nil) then
        return LOCAL_CACHE_TTL
    end

    local expire_at_s = expire_at
    if expire_at_s > 9999999999 then
        expire_at_s = expire_at / 1000
    end

    local local_t = ngx.time() -- os.time()
    local expires_in_s = expire_at_s - local_t
    return expires_in_s
end

function _M:storeTokenInCache(cacheLookupKey, cachingObj, expire_at_ms_utc)
    local expires_in_s = self:getExpiresIn(expire_at_ms_utc)
    if (expires_in_s <= 0) then
        ngx.log(ngx.DEBUG, "OAuth Token was not persisted in the cache as it has expired at:" .. tostring(expire_at_ms_utc) .. ", while now is:" .. tostring(ngx.time() * 1000) .. " ms.")
        return nil
    end
    local local_expire_in = math.min(expires_in_s, LOCAL_CACHE_TTL)
    ngx.log(ngx.DEBUG, "Storing a new token expiring in  " .. tostring(local_expire_in) .. " s locally, out of a total validity of " .. tostring(expires_in_s) .. " s.")
    local cachingObjString = cjson.encode(cachingObj)
    local default_ttl_expire = REDIS_CACHE_TTL
    if ngx.var.max_oauth_redis_cache_ttl ~= nil and ngx.var.max_oauth_redis_cache_ttl ~= '' then
        default_ttl_expire = ngx.var.max_oauth_redis_cache_ttl
    end

    self:setKeyInLocalCache(cacheLookupKey, cachingObjString, local_expire_in, "cachedOauthTokens")
    self:setKeyInRedis(cacheLookupKey, "token_json", math.min(expire_at_ms_utc, (ngx.time() + default_ttl_expire) * 1000), cachingObjString)
end

---
-- Returns an object with a set of variables to be saved in the request's context and later in the request's vars
-- IMPORTANT: This method is only called when validating a new token, otherwise the information from the cache
-- is read and automatically added to the context based on the object returned by this method
-- @param tokenInfo An object with the decoded response from the OAuth 2.0 service
--
function _M:extractContextVars(tokenInfo)
    local cachingObj = {}
    cachingObj.oauth_token_scope = tokenInfo.token.scope
    cachingObj.oauth_token_client_id = tokenInfo.token.client_id
    cachingObj.oauth_token_user_id = tokenInfo.token.user_id
    cachingObj.oauth_token_expires_at = tokenInfo.expires_at -- NOTE: Assumption: value in ms
    return cachingObj
end

-- TODO: cache invalid tokens too for a short while
-- Check in the response if the token is valid --
function _M:checkResponseFromAuth(res, cacheLookupKey)
    local json = safeCjson.decode(res.body)
    if json ~= nil then

        local tokenValidity, error = self:isTokenValid(json)
        if not tokenValidity and error ~= nil then
            return tokenValidity, error
        end
        if tokenValidity and json.token ~= nil then
            local cachingObj = self:extractContextVars(json)

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
        ngx.log(ngx.DEBUG, "Found oauth token in local cache")
        return localCacheValue
    end

    local redisCacheValue = self:getKeyFromRedis(cacheLookupKey, "token_json")
    if (redisCacheValue ~= nil) then
        ngx.log(ngx.DEBUG, "Found oauth token in redis cache")
        --        self:setKeyInLocalCache(cacheLookupKey, redisCacheValue, 60, "cachedOauthTokens")
        return redisCacheValue
    end
    return nil;
end

function _M:validateOAuthToken()

    local oauth_host = ngx.var.oauth_host
    local oauth_token = self.authtoken or ngx.var.authtoken

    if oauth_token == nil or oauth_token == "" then
        return self.RESPONSES.MISSING_TOKEN.error_code, cjson.encode(self.RESPONSES.MISSING_TOKEN)
    end

    --1. try to get token info from the cache first ( local or redis cache )
    local oauth_token_hash = hasher.hash(oauth_token)
    local cacheLookupKey = self:getOauthTokenForCaching(oauth_token_hash, oauth_host)
    local cachedToken = self:getTokenFromCache(cacheLookupKey)

    if (cachedToken ~= nil) then
        -- ngx.log(ngx.INFO, "Cached token=" .. cachedToken)
        local obj =  safeCjson.decode(cachedToken)
        local tokenValidity, error = self:isCachedTokenValid(obj)
        if (tokenValidity > 0) then
            local local_expire_in = math.min(tokenValidity, LOCAL_CACHE_TTL)
            ngx.log(ngx.DEBUG, "Caching locally a new token for " .. tostring(local_expire_in) .. " s, out of a total validity of " .. tostring(tokenValidity) .. " s.")
            self:setKeyInLocalCache(cacheLookupKey, cachedToken, local_expire_in, "cachedOauthTokens")
            self:setContextProperties(obj)
            return ngx.HTTP_OK
        end
        -- at this point the cached token is not valid
        ngx.log(ngx.INFO, "Invalid OAuth Token found in cache. OAuth host=" .. tostring(oauth_host))
        if (error == nil) then
            error = self.RESPONSES.INVALID_TOKEN
        end
        error.error_code = error.error_code or self.RESPONSES.INVALID_TOKEN.error_code
        return error.error_code, cjson.encode(error)
    end

    ngx.log(ngx.INFO, "Failed to get oauth token from cache falling back to oauth provider")

    -- 2. validate the token with the OAuth endpoint
    local res = OauthClient:makeValidateTokenCall("/validate-token", oauth_host, oauth_token)
    if res.status == ngx.HTTP_OK then
        local tokenValidity, error = self:checkResponseFromAuth(res, cacheLookupKey)
        if (tokenValidity == true) then
            return ngx.HTTP_OK
        end
        -- at this point the token is not valid
        ngx.log(ngx.WARN, "Invalid OAuth Token returned. OAuth host=" .. tostring(oauth_host))
        if (error == nil) then
            error = self.RESPONSES.INVALID_TOKEN
        end
        error.error_code = error.error_code or self.RESPONSES.INVALID_TOKEN.error_code
        return error.error_code, cjson.encode(error)
    else
        ngx.log(ngx.WARN, "Oauth provider call failed with status code=", res.status, " body=", res.body)
    end

    return res.status, cjson.encode(self.RESPONSES.UNKNOWN_ERROR);
end

function _M:validateRequest()
    return self:exitFn(self:validateOAuthToken())
end


return _M


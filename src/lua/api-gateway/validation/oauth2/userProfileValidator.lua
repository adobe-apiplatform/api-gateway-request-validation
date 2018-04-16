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


-- User Profile validator.
-- Use this validator to add profile properties in request variables that may be passed forward to the backend service.
-- This speeds up the process to identify who the user is so that the backend service doesn't have to worry about it.

-- Dependencies:
--   1. ngx.var.oauth_host                      - optional var
--   2. ngx.var.authtoken                       - required to be set
--   3. lua_shared_dict cachedOauthTokens 50m;  - required. The local shared dict to cache user profiles
--   4. ngx.ctx.oauth_token_expires_at          - optional. This is usually set by the oauthTokenValidator
--
-- Properties that can be set by this validator:
--  1. user_email
--  2. user_country_code
--  3. user_name
--
-- User: ddascal
-- Date: 17/12/13
-- Time: 20:54
--
-- User: ajk
-- Date: 07/02/14
-- Added the logic to check for the user country and pass it as header.
--
local BaseValidator = require "api-gateway.validation.validator"
local redisConfigurationProvider = require "api-gateway.redis.redisConnectionConfiguration"
local OauthClient = require "api-gateway.util.OauthClient":new()
local cjson = require "cjson"
local hasher = require "api-gateway.util.hasher"

local _M = BaseValidator:new()

_M["redis_RO_upstream"] = redisConfigurationProvider["oauth"]["ro_upstream_name"]
_M["redis_RW_upstream"] = redisConfigurationProvider["oauth"]["rw_upstream_name"]
_M["redis_pass_env"] = redisConfigurationProvider["oauth"]["env_password_variable"]

local RESPONSES = {
    P_MISSING_TOKEN   = { error_code = "403020", message = "Oauth token is missing"         },
    INVALID_PROFILE   = { error_code = "403023", message = "Profile is not valid"           },
    NOT_ALLOWED       = { error_code = "403024", message = "Not allowed to read the profile"},
    P_UNKNOWN_ERROR   = { error_code = "503020", message = "Could not read the profile"     }
}

---
-- Maximum time in seconds specifying how long to cache a valid token in GW's memory
local LOCAL_CACHE_TTL = 60

---
-- Maximum time in milliseconds specifying how long to cache a valid token in Redis
local REDIS_CACHE_TTL = 6 * 60 * 60

-- returns the key that should be used when looking up in the cache --
function _M:getCacheToken(token)
    local t = token;
    local oauth_host = ngx.var.oauth_host
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
    if ( expire_at == nil ) then
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

function _M:getContextPropertiesObject(obj)
    local props = {}
    for k, v in pairs(obj) do
        if v ~= nil then
            props[k] = v
            if k == "user_name" or k == "user_first_name" or k == "user_last_name" then
                props[k] = ngx.escape_uri(tostring(v))
            end
        end
    end
    return props
end

function _M:getProfileFromCache(cacheLookupKey)
    local localCacheValue = self:getKeyFromLocalCache(cacheLookupKey, "cachedUserProfiles")
    if ( localCacheValue ~= nil ) then
        -- ngx.log(ngx.INFO, "Found profile in local cache")
        return localCacheValue
    end

    local redisCacheValue = self:getKeyFromRedis(cacheLookupKey, "user_json")
    if ( redisCacheValue ~= nil ) then
        ngx.log(ngx.DEBUG, "Found User Profile in Redis cache")
        local oauthTokenExpiration = ngx.ctx.oauth_token_expires_at
        local expiresIn = self:getExpiresIn(oauthTokenExpiration)
        local localExpiresIn = math.min( expiresIn, LOCAL_CACHE_TTL )
        ngx.log(ngx.DEBUG, "Storing cached User Profile in the local cache for " .. tostring(localExpiresIn) .. " s out of a total validity of " .. tostring(expiresIn) .. " s.")
        self:setKeyInLocalCache(cacheLookupKey, redisCacheValue, localExpiresIn, "cachedUserProfiles")
        return redisCacheValue
    end
    return nil;
end

function _M:storeProfileInCache(cacheLookupKey, cachingObj)
    local cachingObjString = cjson.encode(cachingObj)

    local oauthTokenExpiration = (ngx.ctx.oauth_token_expires_at or ((ngx.time() + LOCAL_CACHE_TTL) * 1000))
    local expiresIn = self:getExpiresIn(oauthTokenExpiration)

    if ( expiresIn <= 0 ) then
        ngx.log(ngx.ERR, "OAuth Token was not persisted in the cache as it has expired at:" .. tostring(expiresIn) .. ", while now is:" .. tostring(ngx.time() * 1000) .. " ms.")
        return nil
    end

    local localExpiresIn = math.min( expiresIn, LOCAL_CACHE_TTL )
    ngx.log(ngx.DEBUG, "Storing new cached User Profile in the local cache for " .. tostring(localExpiresIn) .. " s out of a total validity of " .. tostring(expiresIn) .. " s.")

    local default_ttl_expire = REDIS_CACHE_TTL
    if ngx.var.max_oauth_redis_cache_ttl ~= nil and ngx.var.max_oauth_redis_cache_ttl ~= '' then
        default_ttl_expire = ngx.var.max_oauth_redis_cache_ttl
    end
    self:setKeyInLocalCache(cacheLookupKey, cachingObjString, localExpiresIn , "cachedUserProfiles")
    -- cache the use profile for 5 minutes
    self:setKeyInRedis(cacheLookupKey, "user_json", math.min(oauthTokenExpiration, (ngx.time() + default_ttl_expire) * 1000), cachingObjString)
end

--- Returns true if the profile is valid for the request context. If profile is not valid then it returns the failure
-- status code and message.
-- This method is to be overritten when this class is extended.
-- @param cachedProfile The information about the user profile that gets cached
--
function _M:isProfileValid(cachedProfile)
    return true, nil, nil
end

---
-- Returns an object with a set of variables to be saved in the request's context and later in the request's vars
--  IMPORTANT: This method is only called when fetching a new profile, otherwise the information from the cache
--             is read and automatically added to the context based on the object returned by this method
-- @param profile User Profile
--
function _M:extractContextVars(profile)
    local cachingObj = {};
    cachingObj.user_email           = profile.email
    cachingObj.user_country_code    = profile.countryCode
    cachingObj.user_name            = profile.displayName
    cachingObj.user_first_name      = profile.first_name
    cachingObj.user_last_name       = profile.last_name
    return cachingObj
end

function _M:getCacheLookupKey()
    local oauth_token = ngx.var.authtoken
    local oauth_token_hash = hasher.hash(oauth_token)
    return self:getCacheToken(oauth_token_hash)
end

function _M:validateUserProfile()
    --1. try to get user's profile from the cache first ( local or redis cache )
    local cacheLookupKey = self:getCacheLookupKey()
    local cachedUserProfile = self:getProfileFromCache(cacheLookupKey)

    if ( cachedUserProfile ~= nil ) then
        if (type(cachedUserProfile) == 'string') then
            cachedUserProfile = cjson.decode(cachedUserProfile)
        end
        self:setContextProperties(self:getContextPropertiesObject(cachedUserProfile))

        local isValid, failureErrorCode, failureMessage = self:isProfileValid(cachedUserProfile)
        if isValid == true then
            return ngx.HTTP_OK
        elseif failureErrorCode ~= nil and failureMessage ~= nil then
            return failureErrorCode, failureMessage
        else
            return RESPONSES.INVALID_PROFILE.error_code, cjson.encode(RESPONSES.INVALID_PROFILE)
        end

    end

    ngx.log(ngx.INFO, "Failed to get profile from cache falling back to oauth provider")
    -- 2. get the user profile from the oauth profile
    local res = OauthClient:makeProfileCall("/validate-user")

    if res.status == ngx.HTTP_OK then
        local json = cjson.decode(res.body)
        if json ~= nil then

            local cachingObj = self:extractContextVars(json)

            self:setContextProperties(self:getContextPropertiesObject(cachingObj))
            self:storeProfileInCache(cacheLookupKey, cachingObj)

            local isValid, failureErrorCode, failureMessage = self:isProfileValid(cachingObj)
            if isValid == true then
                return ngx.HTTP_OK
            elseif failureErrorCode ~= nil and failureMessage ~= nil then
                return failureErrorCode, failureMessage
            else
                return RESPONSES.INVALID_PROFILE.error_code, cjson.encode(RESPONSES.INVALID_PROFILE)
            end
        else
            ngx.log(ngx.WARN, "Could not decode /validate-user response:" .. tostring(res.body) )
        end
    else
        -- ngx.log(ngx.WARN, "Could not read /oauth-profile. status=" .. res.status .. ".body=" .. res.body .. ". token=" .. ngx.var.authtoken)
        ngx.log(ngx.WARN, "Could not read /validate-user. status=" .. res.status .. ".body=" .. res.body )
        if ( res.status == ngx.HTTP_UNAUTHORIZED or res.status == ngx.HTTP_BAD_REQUEST ) then
            return RESPONSES.NOT_ALLOWED.error_code, cjson.encode(RESPONSES.NOT_ALLOWED)
        end
    end
    --ngx.log(ngx.WARN, "Error validating Profile for Token:" .. tostring(ngx.var.authtoken))
    return RESPONSES.P_UNKNOWN_ERROR.error_code, cjson.encode(RESPONSES.P_UNKNOWN_ERROR)
end

function _M:validateRequest()

    local oauth_token = ngx.var.authtoken
    if oauth_token == nil or oauth_token == "" then
        ngx.log(ngx.DEBUG, "Token is either null or empty")
        return self:exitFn(RESPONSES.P_MISSING_TOKEN.error_code, cjson.encode(RESPONSES.P_MISSING_TOKEN))
    end

    return self:exitFn(self:validateUserProfile())
end

return _M
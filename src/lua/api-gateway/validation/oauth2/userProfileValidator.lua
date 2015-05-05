-- User Profile validator.
-- Use this validator to add profile properties in request variables that may be passed forward to the backend service.
-- This speeds up the process to identify who the user is so that the backend service doesn't have to worry about it.

-- Dependencies:
--   1. ngx.var.oauth_host                      - optional var
--   2. ngx.var.authtoken                       - required to be set
--   3. ngx.var.redis_backend                   - required
--   4. lua_shared_dict cachedOauthTokens 50m;  - required. The local shared dict to cache user profiles
--
-- Properties that can be set by this validator:
--  1. user_email
--  2. user_country_code
--  3. user_region
--  4. user_name
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
local cjson = require "cjson"

local _M = BaseValidator:new()

local RESPONSES = {
        P_MISSING_TOKEN   = { error_code = "403020", message = "Oauth token is missing"         },
        INVALID_PROFILE   = { error_code = "403023", message = "Profile is not valid"           },
        NOT_ALLOWED       = { error_code = "403024", message = "Not allowed to read the profile"},
        P_UNKNOWN_ERROR   = { error_code = "503020", message = "Could not read the profile"     }
}
---
-- @field US - countries mapping to US region
-- @field EU - countries mapping to EU region
-- @field AP - countries mapping to AP region
--
local DEFAULT_COUNTRY_MAP = {
    US = { "US", "CA", "AI", "AG", "AR", "AW", "BS", "BB", "BZ", "BM", "BO", "BR", "KY", "CL", "CO", "CR", "DM", "DO", "EC", "SV", "FK", "GF", "GD", "GP", "GT", "GY", "HT", "HN", "JM", "MQ", "MX", "MS", "AN", "NI", "PA", "PY", "PE", "KN", "LC", "PM", "VC", "GS", "SR", "TT", "TC", "UM", "UY", "VE", "VG", "AS" },
    EU = { "GB", "AL", "DZ", "AD", "AO", "AM", "AT", "AZ", "BY", "BE", "BJ", "BA", "BW", "IO", "BG", "BF", "BI", "CM", "CV", "CF", "TD", "KM", "CD", "CG", "HR", "CY", "CZ", "DK", "DJ", "EG", "GQ", "ER", "EE", "ET", "FO", "FI", "FR", "GA", "GM", "GE", "DE", "GH", "GI", "GR", "GL", "GN", "GW", "HU", "IS", "IE", "IT", "CI", "KE", "LV", "LS", "LR", "LY", "LI", "LT", "LU", "MK", "MG", "MW", "ML", "MT", "MR", "MU", "YT", "MD", "MC", "ME", "MA", "MZ", "NA", "NL", "NE", "NG", "NO", "PS", "PL", "PT", "RE", "RO", "RW", "SH", "SM", "ST", "SN", "CS", "RS", "SC", "SL", "SK", "SI", "SO", "ZA", "ES", "SJ", "SZ", "SE", "CH", "TZ", "TG", "TN", "UG", "UA", "VA", "EH", "ZM", "ZW" },
    AP = { "AU", "AF", "AQ", "BH", "BD", "BT", "BN", "MM", "KH", "CN", "CX", "CC", "CK", "TL", "FJ", "PF", "HK", "IN", "ID", "IQ", "IL", "JP", "JO", "KZ", "KI", "KR", "KW", "KG", "LA", "LB", "MO", "MY", "MV", "MH", "FM", "MN", "NR", "NP", "NC", "NZ", "NU", "NF", "OM", "PK", "PG", "PH", "PN", "QA", "RU", "WS", "SA", "SG", "SB", "LK", "TW", "TJ", "TH", "TK", "TO", "TR", "TM", "TV", "AE", "UZ", "VU", "VN", "WF", "YE" }
}

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

function _M:getProfileFromCache(cacheLookupKey)
    local localCacheValue = self:getKeyFromLocalCache(cacheLookupKey, "cachedUserProfiles")
    if ( localCacheValue ~= nil ) then
        -- ngx.log(ngx.WARN, "Found profile in local cache")
        return localCacheValue
    end

    local redisCacheValue = self:getKeyFromRedis(cacheLookupKey, "user_json")
    if ( redisCacheValue ~= nil ) then
        -- ngx.log(ngx.WARN, "Found profile in redis cache")
        self:setKeyInLocalCache(cacheLookupKey, redisCacheValue, 60, "cachedUserProfiles")
        return redisCacheValue
    end
    return nil;
end

function _M:storeProfileInCache(cacheLookupKey, cachingObj)
    local cachingObjString = cjson.encode(cachingObj)
    -- TODO: find a better way to compute the expiry time
    self:setKeyInLocalCache(cacheLookupKey, cachingObjString, 60, "cachedUserProfiles")
    -- cache the use profile for 5 minutes
    self:setKeyInRedis(cacheLookupKey, "user_json", ((os.time() + 300) * 1000 ), cachingObjString)
end

--- Returns true if the profile is valid for the request context
--     This method is to be overritten when this class is extended
-- @param cachedProfile The information about the user profile that gets cached
function _M:isProfileValid(cachedProfile)
    return true
end

---
--  Returns an object mapping countries to regions
function _M:getDefaultCountryMap()
    return DEFAULT_COUNTRY_MAP
end

function _M:getUserRegion( user_country_code, country_map )
    local cmap = country_map or self:getDefaultCountryMap()
    for region,countries in pairs(cmap) do
        for i , countryCode in pairs(countries) do
            if user_country_code == countryCode then
                return region
            end
        end
    end
    return "US"
end

---
-- Returns an object with a set of variables to be saved in the request's context and later in the request's vars
-- @param profile User Profile
--
function _M:extractContextVars(profile)
    local cachingObj = {};
    cachingObj.user_email           = profile.email
    cachingObj.user_country_code    = profile.countryCode
    cachingObj.user_name            = profile.displayName
    cachingObj.user_region          = self:getUserRegion(profile.countryCode)

    return cachingObj
end

function _M:validateRequest()
    -- ngx.var.authtoken needs to be set before calling this method
    local oauth_token = ngx.var.authtoken
    if oauth_token == nil or oauth_token == "" then
        --return self:exitFn(ngx.HTTP_BAD_REQUEST)
        return self:exitFn(RESPONSES.P_MISSING_TOKEN.error_code, cjson.encode(RESPONSES.P_MISSING_TOKEN))
    end

    --1. try to get user's profile from the cache first ( local or redis cache )
    local oauth_token_hash = ngx.md5(oauth_token)
    local cacheLookupKey = self:getCacheToken(oauth_token_hash)
    local cachedUserProfile = self:getProfileFromCache(cacheLookupKey)

    if ( cachedUserProfile ~= nil ) then
        self:setContextProperties(cachedUserProfile)
        if ( self:isProfileValid(cachedUserProfile) == true ) then
            return self:exitFn(ngx.HTTP_OK)
        else
            return self:exitFn(RESPONSES.INVALID_PROFILE.error_code, cjson.encode(RESPONSES.INVALID_PROFILE))
        end
    end

	-- 2. get the user profile from the IMS profile
    local res = ngx.location.capture("/validate-user", { share_all_vars = true })
    if res.status == ngx.HTTP_OK then
    	local json = cjson.decode(res.body)
    	if json ~= nil then

            local cachingObj = self:extractContextVars(json)

            self:setContextProperties(cachingObj)
            self:storeProfileInCache(cacheLookupKey, cachingObj)

            if ( self:isProfileValid(cachingObj) == true ) then
                return self:exitFn(ngx.HTTP_OK)
            else
                return self:exitFn(RESPONSES.INVALID_PROFILE.error_code, cjson.encode(RESPONSES.INVALID_PROFILE))
            end
        else
            ngx.log(ngx.WARN, "Could not decode /validate-user response:" .. tostring(res.body) )
        end
    else
        -- ngx.log(ngx.WARN, "Could not read /ims-profile. status=" .. res.status .. ".body=" .. res.body .. ". token=" .. ngx.var.authtoken)
        ngx.log(ngx.WARN, "Could not read /validate-user. status=" .. res.status .. ".body=" .. res.body )
        if ( res.status == ngx.HTTP_UNAUTHORIZED or res.status == ngx.HTTP_BAD_REQUEST ) then
            return self:exitFn(RESPONSES.NOT_ALLOWED.error_code, cjson.encode(RESPONSES.NOT_ALLOWED))
        end
    end
    --ngx.log(ngx.WARN, "Error validating Profile for Token:" .. tostring(ngx.var.authtoken))
    return self:exitFn(RESPONSES.P_UNKNOWN_ERROR.error_code, cjson.encode(RESPONSES.P_UNKNOWN_ERROR))
end

return _M
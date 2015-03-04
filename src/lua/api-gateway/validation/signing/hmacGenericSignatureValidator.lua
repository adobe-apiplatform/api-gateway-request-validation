-- Generic HMAC Validator implementation
-- This should replace the hmacSha1SignatureValidator

-- Dependencies:
--   1. ngx.var.hmac_source_string        - source string to encode using ngx.var.hmac_secret
--   2. ngx.var.hmac_target_string        - hmac to compare against
--   3. ngx.var.hmac_secret               - secret used to compile the ngx.var.hmac_source_string

-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 01/04/14
-- Time: 00:19
-- To change this template use File | Settings | File Templates.
--

local BaseValidator = require "api-gateway.validation.validator"
local RestyHMAC = require "api-gateway.resty.hmac"
local cjson = require "cjson"

local _M = BaseValidator:new()

local RESPONSES = {
        MISSING_SIGNATURE   = { error_code = "403030", message = "Signature is missing"        },
        INVALID_SIGNATURE   = { error_code = "403033", message = "Signature is invalid"        },
        -- unknown error is not used at the moment
        UNKNOWN_ERROR       = { error_code = "503030", message = "Could not validate Signature"}
}

function  _M:validateSignature()
    local source = ngx.var.hmac_source_string
    local secret = ngx.var.hmac_secret or ngx.ctx.key_secret -- ngx.ctx.key_secret is set by api key validator
    local target = ngx.var.hmac_target_string
    local algorithm = ngx.var.hmac_method

    if ( source == nil or secret == nil or target == nil) then
        ngx.log(ngx.WARN, "Invalid request. source=" .. tostring(source) .. ",secret=" .. tostring(secret) .. ",target=" .. tostring(target))
        return self:exitFn(RESPONSES.MISSING_SIGNATURE.error_code, cjson.encode(RESPONSES.MISSING_SIGNATURE))
    end
    local hmac = RestyHMAC:new()
    local digest = ngx.encode_base64(hmac:digest(algorithm, secret, self:getHmacSource(source), true))

    self:debug(ngx.WARN, "Testing HMAC DIGEST WITH secret=" .. secret)
    if ( digest == target ) then
        return self:exitFn(ngx.HTTP_OK)
    end

    ngx.log(ngx.WARN, "HMAC signature missmatch. Expected:" .. tostring(target) .. ", but got:" .. tostring(digest), ", HMAC Algorithm=", algorithm )
    return self:exitFn(RESPONSES.INVALID_SIGNATURE.error_code, cjson.encode(RESPONSES.INVALID_SIGNATURE))
end

-- method to be overriden in the super classes to return another source
-- some implementations may choose to apply a lowercase or other transformations
-- NOTE: the same can be achieved by using
--       "set_by_lua $hmac_source_string 'return string.lower(ngx.var.request_method .. ngx.var.uri .. ngx.var.api_key)';"
function _M:getHmacSource( source )
    return source
end

return _M
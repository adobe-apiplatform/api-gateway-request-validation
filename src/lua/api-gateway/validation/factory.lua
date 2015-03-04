-- This factory creates the object to be instatiated when the API Gateway starts
--
--  Usage:
--      init_worker_by_lua '
--          ngx.apiGateway = ngx.apiGateway or {}
--          ngx.apiGateway.validation = require "api-gateway.validation.factory"
--      ';
--
--

-- User: ddascal
-- Date: 02/03/15
-- Time: 23:36
--

local ValidatorsHandler = require "api-gateway.validation.validatorsHandler"
local ApiKeyValidatorCls = require "api-gateway.validation.key.redisApiKeyValidator"
local HmacSignatureValidator = require "api-gateway.validation.signing.hmacGenericSignatureValidator"
local OAuthTokenValidator = require "api-gateway.validation.oauth2.oauthTokenValidator"


local debug_mode = ngx.config.debug
local function debug(...)
    if debug_mode then
        ngx.log(ngx.DEBUG, "validator: ", ...)
    end
end

---
-- Function designed to be called from access_by_lua
-- It calls an internal /validate-request path which can provide any custom implementation for request validation
local function _validateRequest()
    if (ngx.var.request_method == 'OPTIONS') then
        return ngx.exit(ngx.OK);
    end

    local res = ngx.location.capture("/validate-request", { share_all_vars = true });
    debug("Final validation result:" .. ngx.var.validate_request_response_body .. ", [" .. res.status .. "]")

    if ngx.var.arg_debug == "true" then
        ngx.header["X-Debug-Validation-Response-Times"] = res.header["X-Debug-Validation-Response-Times"];
    end

    if res.status == ngx.HTTP_OK then
        return ngx.exit(ngx.OK);
    end

    if res.status == ngx.HTTP_FORBIDDEN or res.status == ngx.HTTP_UNAUTHORIZED or res.status == ngx.HTTP_BAD_REQUEST or tonumber(res.status) > 599 then
        -- return ngx.exit(res.status)
        local error_page = ngx.var.validation_error_page or "@handle_gateway_validation_error"
        return ngx.exec(error_page)
    end

    -- for all other unknown cases return 500
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

---
-- Default request validation implementation
local function _defaultValidateRequestImpl()
    local handlers = ValidatorsHandler:new()
    return handlers:validateRequest()
end

---
-- Basic impl extending redisApiKey validator.
local function _validateApiKey()
    local keyValidator = ApiKeyValidatorCls:new()
    return keyValidator:validateRequest()
end

local function _validateHmacSignature()
    local hmacSignatureValidator = HmacSignatureValidator:new()
    return hmacSignatureValidator:validateSignature()
end

local function _validateOAuthToken()
    local oauthTokenValidator = OAuthTokenValidator:new()
    return oauthTokenValidator:validateRequest()
end


return {
    validateApiKey = _validateApiKey,
    validateHmacSignature = _validateHmacSignature,
    validateOAuthToken = _validateOAuthToken,
    validateRequest = _validateRequest,
    defaultValidateRequestImpl = _defaultValidateRequestImpl,
}

--return _M

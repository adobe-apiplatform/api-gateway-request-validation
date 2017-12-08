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
local UserProfileValidator = require "api-gateway.validation.oauth2.userProfileValidator"
local logger = require "api-gateway.util.logger"

local function debug(...)
    if debug_mode then
        ngx.log(ngx.DEBUG, "validator: ", ...)
    end
end

---
-- Function designed to be called from access_by_lua
-- It calls an internal /validate-request path which can provide any custom implementation for request validation
local function _validateRequest()
    logger.decorateLogger()

    if (ngx.var.request_method == 'OPTIONS') then
        return ngx.OK;
    end
    local res = ngx.location.capture("/validate-request", { share_all_vars = true });
    debug("Final validation result:" .. ngx.var.validate_request_response_body .. ", [" .. res.status .. "]")

    if ngx.var.arg_debug == "true" then
        ngx.header["X-Debug-Validation-Response-Times"] = res.header["X-Debug-Validation-Response-Times"];
    end

    if res.status == ngx.HTTP_OK then
        if ( ngx.var.is_access_phase_tracking_enabled == "true" ) then
            if ( ngx.apiGateway.tracking ~= nil ) then
                ngx.log(ngx.DEBUG, "Request tracking done on access phase.");
                ngx.apiGateway.tracking.track()
            end
        end
        return ngx.OK;
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

local function _generateHmacSignature()
    local hmacSignatureValidator = HmacSignatureValidator:new()
    return hmacSignatureValidator:generateSignature()
end

local function _validateOAuthToken(config)
    local oauthTokenValidator = OAuthTokenValidator:new(config)
    return oauthTokenValidator:validateRequest()
end

local function _validateUserProfile()
    local userProfileValidator = UserProfileValidator:new()
    return userProfileValidator:validateRequest()
end


return {
    validateApiKey = _validateApiKey,
    validateHmacSignature = _validateHmacSignature,
    generateHmacSignature = _generateHmacSignature,
    validateOAuthToken = _validateOAuthToken,
    validateUserProfile = _validateUserProfile,
    validateRequest = _validateRequest,
    defaultValidateRequestImpl = _defaultValidateRequestImpl,
}

--return _M

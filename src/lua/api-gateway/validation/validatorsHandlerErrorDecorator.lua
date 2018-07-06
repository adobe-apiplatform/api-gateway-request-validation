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


-- Decorates the error response when validation fails
--
-- Usage example:
-- # NOTE: this endpoint assumes that $validate_request_status and $validate_request_response_body is set before
-- location @handle_gateway_validation_error {
--    internal;
--    content_by_lua '
--        local ErrorDecorator = require "api-gateway.validation.validatorsHandlerErrorDecorator"
--        local decorator = ErrorDecorator:new()
--        decorator:decorateResponse(ngx.var.validate_request_status, ngx.var.validate_request_response_body)
--    ';
--}

local base = require "api-gateway.validation.base"
local cjson = require "cjson"
local debug_mode = ngx.config.debug

-- Object to map the error_codes sent by validators to real HTTP response codes.
-- When a validator fail with the given "error_code", the HTTP response code is the "http_status" associated to the "error_code"
-- The "message" associated to the "error_code" is returned as well.
local DEFAULT_RESPONSES = {
    -- ip filtering
    BLACKLIST_IP = { http_status = 403, error_code = 403012, message = '{"error_code":"403012","message":"Your IP is blacklisted"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    WHITELIST_IP = { http_status = 403, error_code = 403013, message = '{"error_code":"403013","message":"Your IP is not whitelisted"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    -- redisApiKeyValidator error
    MISSING_KEY = { http_status = 403, error_code = 403000, message = '{"error_code":"403000","message":"Api Key is required"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    INVALID_KEY = { http_status = 403, error_code = 403003, message = '{"error_code":"403003","message":"Api Key is invalid"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    K_UNKNOWN_ERROR = { http_status = 503, error_code = 503000, message = '{"error_code":"503000","message":"Could not validate Api Key"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    --oauth errors
    MISSING_TOKEN = { http_status = 403, error_code = 403010, message = '{"error_code":"403010","message":"Oauth token is missing."}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    INVALID_TOKEN = { http_status = 401, error_code = 401013, message = '{"error_code":"401013","message":"Oauth token is not valid"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    T_UNKNOWN_ERROR = { http_status = 503, error_code = 503010, message = '{"error_code":"503010","message":"Could not validate the oauth token"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    SCOPE_MISMATCH = { http_status = 403, error_code = 403011, message = '{"error_code":"403011","message":"Scope mismatch"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    -- oauth profile error
    P_MISSING_TOKEN = { http_status = 403, error_code = 403020, message = '{"error_code":"403020","message":"Oauth token missing or invalid"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    INVALID_PROFILE = { http_status = 403, error_code = 403023, message = '{"error_code":"403023","message":"Profile is not valid"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    NOT_ALLOWED = { http_status = 403, error_code = 403024, message = '{"error_code":"403024","message":"Not allowed to read the profile"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    P_UNKNOWN_ERROR = { http_status = 403, error_code = 503020, message = '{"error_code":"503020","message":"Could not read the profile"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    -- hmacSha1SignatureValidator errors
    MISSING_SIGNATURE = { http_status = 403, error_code = 403030, message = '{"error_code":"403030","message":"Signature is missing"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    INVALID_SIGNATURE = { http_status = 403, error_code = 403033, message = '{"error_code":"403033","message":"Signature is invalid"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    UNKNOWN_ERROR = { http_status = 503, error_code = 503030, message = '{"error_code":"503030","message":"Could not validate Signature"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    -- Service limit errrors
    LIMIT_EXCEEDED = { http_status = 429, error_code = 429001, message = '{"error_code":"429001","message":"Service usage limit reached"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    DEV_KEY_LIMIT_EXCEEDED = { http_status = 429, error_code = 429002, message = '{"error_code":"429002","message":"Developer key usage limit reached"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    BLOCK_REQUEST = { http_status = 429, error_code = 429050, message = '{"error_code":"429050","message":"Too many requests"}', headers = { ["X-Request-Id"] = "ngx.var.requestId", ["Retry-After"] = "ngx.var.retry_after" } },
    -- App valdations
    DELAY_CLIENT_ON_REQUEST = { http_status = 503, error_code = 503071, messsage = '', headers = { ["Retry_After"] = "300s" }, headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    -- CC Link validation
    INVALID_LINK = { http_status = 403, error_code = 403040, message = '{"error_code":"403040","message":"Invalid link"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    LINK_NOT_FOUND = { http_status = 404, error_code = 404040, message = '{"error_code":"404040","message":"Link not found"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    -- Generate Hmac validators
    MISSING_SOURCE = { http_status = 400, error_code = 400001, message = '{"error_code":"400001","message":"Missing digest source"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    MISSING_SECRET = { http_status = 400, error_code = 400002, message = '{"error_code":"400002","message":"Missing digest secret"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } },
    MISSING_HEADER = { http_status = 400, error_code = 400003, message = '{"error_code":"400003","message":"Missing header"}', headers = { ["X-Request-Id"] = "ngx.var.requestId" } }
}

local default_responses_array
local user_defined_responses

local function getResponsesTemplate()
    return user_defined_responses or default_responses_array
end

local function convertResponsesToArray(responses)
    local a = {}
    for k, v in pairs(responses) do
        if (v.error_code ~= nil and v.http_status ~= nil) then
            --table.insert(a, v.error_code, { http_status = v.http_status, message = v.message } )
            table.insert(a, v.error_code, v)
        end
    end
    return a
end

local ValidatorHandlerErrorDecorator = {}

function ValidatorHandlerErrorDecorator:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    default_responses_array = convertResponsesToArray(DEFAULT_RESPONSES)
    return o
end

-- decorates the response by the given response_status and response_body
function ValidatorHandlerErrorDecorator:decorateResponse(response_status, response_body)
    response_status = tonumber(response_status)

    local o = getResponsesTemplate()[response_status]
    if (o ~= nil) then
        ngx.status = self:convertToValidHttpStatusCode(o.http_status)
        -- NOTE: assumption: for the moment if it's custom, then it's application/json
        ngx.header["Content-Type"] = "application/json"
        -- add custom headers too
        if (o.headers ~= nil) then
            local val, i, j
            for k, v in pairs(o.headers) do
                val = tostring(v)
                -- see if the header is a variable and replace it with ngx.var.<var_name>
                i, j = string.find(val, "ngx.var.")
                if (i ~= nil and j ~= nil) then
                    val = string.sub(val, j + 1)
                    if (#val > 0) then
                        val = ngx.var[val]
                    end
                end
                ngx.header[k] = val
            end
        end
        -- initialize an nginx variable with the error_code in order to print it in the logging file
        if (o.error_code ~= nil) then
            ngx.var.request_validator_error_code = o.error_code;
        end
        -- ngx.say(o.message)
        -- add custom message
        local msg = self:parseResponseMessage(o.message)
        ngx.say(msg)
        return
    end

    -- if no custom status code was used, assume the default one is right by trusting the validators
    if (response_body ~= nil and #response_body > 0 and response_body ~= "nil\n") then
        ngx.status = self:convertToValidHttpStatusCode(response_status)
        ngx.say(response_body)
        return
    end
    -- if there is no custom response form the validator just exit with the status
    ngx.exit(self:convertToValidHttpStatusCode(response_status))
end

--- Convert the codes sent by validators to real HTTP response codes
-- @param response_status
--
function ValidatorHandlerErrorDecorator:convertToValidHttpStatusCode(response_status)
    if (response_status >= 100 and response_status <= 599) then
        return response_status
    end

    local http_code_str = string.sub(tostring(response_status), 0, 3)
    local http_code_number = assert(tonumber(http_code_str), "Invalid HTTP Status Code when decorating response: " .. http_code_str)
    if (http_code_number >= 100 and http_code_number <= 599) then
        return http_code_number
    end

    ngx.log(ngx.DEBUG, "Status code: ", tostring(response_status), " has not a valid HTTP Status Code format")
    return 500
end

--- Parse the response message and replace any variables, if found (at most 3 variables)
-- @param message Response message
--
function ValidatorHandlerErrorDecorator:parseResponseMessage(message)
    local m = message
    local from, to, var, varName, value
    local cnt = 0
    while cnt < 3 do
        from, to = ngx.re.find(m, "ngx.var.[a-zA-Z_0-9]+", "jo")
        if (from) then
            var = string.sub(m, from, to)
            varName = string.sub(m, from + 8, to) -- "+ 8" jump over "ngx.var."
            value = ngx.var[varName]
            m = string.gsub(m, var, value)
        else
            break
        end
        cnt = cnt + 1
    end
    -- all variables have been replaced
    return m
end

-- hook to overwrite the DEFAULT_RESPONSES by specifying a jsonString
function ValidatorHandlerErrorDecorator:setUserDefinedResponsesFromJson(jsonString)
    if (jsonString == nil or #jsonString < 2) then
        return
    end
    local r = assert(cjson.decode(jsonString), "Invalid user defined jsonString:" .. tostring(jsonString))
    if r ~= nil then
        user_defined_responses = r
        local user_responses = convertResponsesToArray(r)
        -- merge tables
        for k, v in pairs(default_responses_array) do
            -- merge only if user didn't overwrite the default response
            if (user_responses[k] == nil) then
                user_responses[k] = v
            end
        end

        user_defined_responses = user_responses
    end
end

return ValidatorHandlerErrorDecorator
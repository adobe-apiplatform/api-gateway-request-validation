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


-- Executes multiple validators
--
--
-- The long-term plan is to define a C module that loads a set of request_validators
-- executing them during the access phase of Nginx, based on the their order.
--
-- location /my-location {
--    request_validator "on; path=/validate_api_key;        args=api_key,service_id;    order=1";
--    request_validator "on; path=/validate_oauth_oauth;      args=authtoken;             order=1";
--    request_validator "on; path=/validate_oauth_profile";   args=authtoken;             order=1";
--    request_validator "on; path=/validate_user_plan;      args=oauth_user_id;         order=2";
-- }
--
-- The short term plan is to have a variable for each validator.
-- Subrequests share all variables, and write properties into the request context
-- location /my-location {
--    set $validate_api_key     "on; path=/validate_api_key;        order=1; ";
--    set $validate_oauth_oauth   "on; path=/validate_oauth_oauth;      order=1; ";
--    set $validate_oauth_profile "on; path=/validate_oauth_profile";   order=1; ";
--    set $validate_user_plan   "on; path=/validate_user_plan;      order=2; ";
--    set $request_validator_1   "on; path=/validate_a_custom_case;      order=2; ";
--
-- }
-- User: ddascal
-- Date: 11/22/13
-- Time: 2:55 PM
--

-- class to be used as a base class for all api-gateway validators --
local ValidatorsHandler = {}

function ValidatorsHandler:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

local DEFAULT_VALIDATORS = {
    validate_api_key = {
         defaultProperties = {
            path = '/validate_api_key', order=1
         }
       },
         validate_oauth_token = {
          defaultProperties = {
             path = '/validate_oauth_token', order=1
          }
       },
       validate_user_profile = {
           defaultProperties = {
              path = '/validate_user_profile', order=2
           }
       },
       validate_hmac_signature = {
           defaultProperties = {
              path = '/validate_hmac_signature', order=2
           }
       },

       generate_hmac_signature = {
           defaultProperties = {
              path = '/generate_hmac_signature', order=2
           }
       },

       -- service_plan validator usually contains throttling limits
       validate_service_plan = {
            defaultProperties = {
               path = '/validate_service_plan', order=1
            }
       },
       -- app_plan validator should execute after the api-key has been validated
       validate_app_plan = {
            defaultProperties = {
               path = '/validate_app_plan', order=2
            }
       },
       -- user_plan validator should execute after a user token has been validated
       validate_user_plan = {
            defaultProperties = {
               path = '/validate_user_plan', order=3
            }
       },
       -- extra validators used for custom use-cases
       request_validator_1 = { defaultProperties = { path = '/request_validator-1', order=1 } },
       request_validator_2 = { defaultProperties = { path = '/request_validator-2', order=1 } },
       request_validator_3 = { defaultProperties = { path = '/request_validator-3', order=1 } },
       request_validator_4 = { defaultProperties = { path = '/request_validator-4', order=1 } }
}

function ValidatorsHandler:getValidatorsList()
    return DEFAULT_VALIDATORS
end

function ValidatorsHandler:trim(s)
  return s:match "^%s*(.-)%s*$"
end

function ValidatorsHandler:getValidatorsFromConfiguration( localContext )
    local reqs = {}
    local request_validator = {}
    local defined_props = {}
    local request_props = {}

    local validatorsList = self:getValidatorsList()
    for validator_prop_name, validator_default_props in pairs(validatorsList) do
        request_validator = {}
        defined_props = ngx.var[validator_prop_name]
        if ( defined_props ~= nil and self:trim(defined_props):sub(1,2) == "on") then
            --1. set default properties first
            for prop,val in pairs(validator_default_props.defaultProperties) do
                request_validator[prop] = val
            end
            --2. overwrite with the custom properties
            -- TODO: test with ngx.re.gmatch instead of string.gmatch
--            local iterator, err = ngx.re.gmatch(defined_props, [[(\w+)=([^\s]*);]], "jois")
--            local m, m_err = iterator()
--            while ( m ~= nil ) do
--                local k = tostring(m[1])
--                local v = tostring(m[2])
--                request_validator[k] = v
--
--                m, m_err = iterator()
--            end

            for k,v in string.gmatch(defined_props, "(%a+)=(.-)%;") do
                request_validator[k] = v
            end
            -- push request in the list
            request_validator.order = tonumber(request_validator.order)
            ngx.log(ngx.DEBUG, "Adding validator:" .. request_validator.path .. ",order:" .. tostring(request_validator.order))
            reqs[ request_validator.order ] = reqs[ request_validator.order ] or {}
            request_props = {
                method = ngx.HTTP_GET,
                share_all_vars = true,
                ctx = localContext
            }
            if request_validator.args ~= nil then
                request_props.args = request_validator.args
            end

            table.insert(
                    reqs[ request_validator.order ],
                    {
                        request_validator.path,
                        request_props
                    }
            )
        end
    end
    return reqs;
end

-- validates in parallel a set of subrequests
function ValidatorsHandler:validateSubrequests(order, subrequests, localContext, responseTimesHeaders )
    local subrequests_count = table.getn(subrequests)
    ngx.log(ngx.DEBUG, "Validating " .. subrequests_count .. " subrequests. Order=" .. order )

     -- issue all the requests at once and wait until they all return
    local resps = { ngx.location.capture_multi(subrequests) }
    local validation_response_status = ngx.HTTP_OK
    local validation_response_body = ""

    local response_times = responseTimesHeaders or {}

    -- loop over the responses table
    for i, resp in ipairs(resps) do
        local subrequest_path = subrequests[i][1];
        local subrequest_duration = resp.header["Response-Time"] or 0;
        subrequest_duration = math.floor(subrequest_duration * 1000);
        ngx.log(ngx.DEBUG, "subrequest:", subrequest_path, " executed in:", subrequest_duration, "s, status:", resp.status);

        table.insert(response_times, subrequest_path .. ", " .. subrequest_duration .. " ms, status:" .. resp.status);
        -- check that each status is 2xx in order to consider it valid
        if (resp.status ~= ngx.HTTP_OK) then
            local resp_body = resp.body or "<empty>";
            ngx.log(ngx.WARN, "Unauthorized request. Subrequest:", subrequests[i][1], ", status:", resp.status, ", body:", resp_body);
            -- When status >= 200 (i.e., ngx.HTTP_OK and above),
            --      ngx.exit will interrupt the execution of the current request and return status code to nginx.
            -- When status == 0 (i.e., ngx.OK), it will only quit the current phase handler
            --      and continue to run later phases (if any) for the current request.
            validation_response_status = resp.status;
            validation_response_body = resp.body;
        end
    end
    local req_time = ngx.now() - ngx.req.start_time();
    req_time = math.floor(req_time * 1000);
    ngx.log(ngx.DEBUG, "Request validation order " .. order .. " executed " .. table.getn(resps) .. " validator(s) in " .. req_time .. "s");
    table.insert(response_times, "request_validator [order:" .. order .. "], " .. req_time .. " ms, status:" .. validation_response_status);

    -- the next 2 variables are declared in auth_request_validations.conf
    ngx.var.validate_request_status = validation_response_status;
    ngx.var.validate_request_response_body = validation_response_body;
    ngx.var.validate_request_response_time = req_time;

    -- save all debug headers into a variable to be accessed from the main Request and used in header_filter_by_lua
    if nil ~= ngx.var.validation_debug_headers then
        ngx.var.validation_debug_headers = response_times;
    end

    ngx.header["X-Debug-Validation-Response-Times"] = response_times;
    ngx.status = validation_response_status;
    return validation_response_status, validation_response_body, req_time;

end

---
-- save variables set by validators in subrequests into the current request vars
function ValidatorsHandler:saveContextInRequestVars(localContext)
     for k,v in pairs(localContext) do
    -- for i,k in pairs(varsToSet) do
        if ngx.var[k] ~= nil and (type(localContext[k]) == "string" or type(localContext[k]) == "number") then
            -- ngx.log(ngx.DEBUG, "Setting " .. k .. ",from: " .. ngx.var[k] .. ",to:" .. v)
            if v ~= nil then
                ngx.var[k] = v
            end
        end
    end
end

function ValidatorsHandler:validateRequest()
    local localContext = {}
    local reqs = self:getValidatorsFromConfiguration(localContext)
    local subrequestResultStatus = ngx.HTTP_OK
    local subrequestResultBody
    local responseTimesHeaders = {}
    local reqs_count = table.maxn(reqs)
    ngx.log(ngx.DEBUG, "Executing " .. reqs_count .. " ordered subrequests")

    for i = 1,reqs_count do
        ngx.log(ngx.DEBUG, "Executing validators with order=" .. i)
        --ngx.log(ngx.DEBUG, "Printing ctx object before executing validators of order:" .. i)
        local requests = reqs[i]
--        ngx.log(ngx.DEBUG, "Table requests " .. table.getn(requests))
        if ( requests ~= nil and table.maxn(requests) > 0) then
            subrequestResultStatus, subrequestResultBody = self:validateSubrequests(i, requests, localContext, responseTimesHeaders)
            if ( subrequestResultStatus ~= ngx.HTTP_OK ) then
                self:saveContextInRequestVars(localContext)
                return ngx.exit(subrequestResultStatus)
            end
        else
            ngx.log(ngx.DEBUG, "Skipped this validator.")
        end
    end
    self:saveContextInRequestVars(localContext)
    return ngx.exit(ngx.HTTP_OK)
end

return ValidatorsHandler

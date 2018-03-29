---
--- Created by trifan.
--- DateTime: 10/01/2018 12:18
---
---
--- Created by trifan.
--- DateTime: 10/01/2018 11:36
---

local OauthClient = {}

function OauthClient:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

local dogstats = require "api-gateway.dogstatsd.Dogstatsd"
local dogstatsInstance = dogstats:new()

--- metrics for Dogstatsd
OauthClient.oauthHttpCallsMetric = 'oauth.http_calls'


--- Computes the total number of oauth http calls, divide them by their status code and outputs the total elapsed time
-- @param metric - metric to be identified in the Dogstatsd dashboard
-- @param methodName - The name of the method for which we are measuring http calls
-- @param startTime - The time the call was initiated
-- @param endTime - The time the call returned
-- @param statusCode - The status code returned by the call
-- @return - void method
--
function OauthClient:computeMetrics(metric, methodName, startTime, endTime, statusCode)
    dogstatsInstance:computeMetrics(metric, 1, methodName, startTime, endTime, statusCode)
end

function OauthClient:makeValidateTokenCall(internalPath, oauth_host, oauth_token)
    oauth_host = oauth_host or ngx.var.oauth_host
    oauth_token = oauth_token or ngx.var.authtoken

    ngx.log(ngx.INFO, "validateToken request to host=", oauth_host)

    local startTime = os.clock()
    local res = ngx.location.capture(internalPath, {
        share_all_vars = true,
        args = { authtoken = oauth_token }
    })
    local endTime = os.clock()

    self:computeMetrics(self.oauthHttpCallsMetric, 'makeValidateTokenCall', startTime, endTime, res.status)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end

    ngx.log(logLevel, "validateToken Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

function OauthClient:makeProfileCall(internalPath, oauth_host)

    oauth_host = oauth_host or ngx.var.oauth_host
    ngx.log(ngx.INFO, "profileCall request to host=", oauth_host)
    local startTime = os.clock()
    local res = ngx.location.capture(internalPath, { share_all_vars = true })
    local endTime = os.clock()

    self:computeMetrics(self.oauthHttpCallsMetric, 'makeProfileCall', startTime, endTime, res.status)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end

    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
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

--- Increments the number of calls to the Oauth provider
--  @param metric - metric to be identified in the Dogstatsd dashboard
--  @param counter - the number of times we would like to have the metric incremented
-- @return - void method
--
function OauthClient:increment(metric, counter)
    dogstatsInstance:increment(metric, counter)
end

--- Measures the number of milliseconds elapsed
-- @param metric - metric to be identified in the Dogstatsd dashboard
-- @param ms - the time it took a call to finish in milliseconds
-- @return - void method
--
function OauthClient:time(metric, ms)
    dogstatsInstance:time(metric, ms)
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
    self:increment(self.oauthHttpCallsMetric, 1)

    local elapsedTime = os.difftime(endTime,startTime) * 1000
    local elapsedTimeMetric = self.oauthHttpCallsMetric .. '.makeValidateTokenCall.duration'
    self:time(elapsedTimeMetric, elapsedTime)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end
    local oauthMakeValidateTokenCallStatusMetric = self.oauthHttpCallsMetric .. '.makeValidateTokenCall.status.' .. res.status
    self:increment(oauthMakeValidateTokenCallStatusMetric, 1)
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
    self:increment(self.oauthHttpCallsMetric, 1)

    local elapsedTime = os.difftime(endTime,startTime) * 1000
    local elapsedTimeMetric = self.oauthHttpCallsMetric '.makeProfileCall.duration'
    self:time(elapsedTimeMetric, elapsedTime)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end
    local oauthMakeProfileCallStatusMetric = self.oauthHttpCallsMetric .. '.makeValidateTokenCall.status.' .. res.status
    self:increment(oauthMakeProfileCallStatusMetric, 1)
    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
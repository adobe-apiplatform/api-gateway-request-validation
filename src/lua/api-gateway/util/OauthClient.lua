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
-- @return - void method
--
function OauthClient:increment(metric)
    dogstatsInstance:increment(metric)
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

    local startTime = os.time()
    local res = ngx.location.capture(internalPath, {
        share_all_vars = true,
        args = { authtoken = oauth_token }
    })
    local endTime = os.time()
    self:increment(OauthClient.oauthHttpCallsMetric)

    local elapsedTime = os.difftime(endTime,startTime) * 1000
    local elapsedTimeMetric = OauthClient.oauthHttpCallsMetric .. 'makeValidateTokenCall.duration'
    self:time(elapsedTimeMetric, elapsedTime)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end
    local oauthMakeValidateTokenCallStatusMetric = OauthClient.oauthHttpCallsMetric .. '.makeValidateTokenCall.status.' .. res.status
    self:increment(oauthMakeValidateTokenCallStatusMetric)
    ngx.log(logLevel, "validateToken Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

function OauthClient:makeProfileCall(internalPath, oauth_host)

    oauth_host = oauth_host or ngx.var.oauth_host
    ngx.log(ngx.INFO, "profileCall request to host=", oauth_host)
    local startTime = os.time()
    local res = ngx.location.capture(internalPath, { share_all_vars = true })
    local endTime = os.time()
    self:increment(OauthClient.oauthHttpCallsMetric)

    local elapsedTime = os.difftime(endTime,startTime) * 1000
    local elapsedTimeMetric = OauthClient.oauthHttpCallsMetric '.makeProfileCall.duration'
    self:time(elapsedTimeMetric, elapsedTime)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end
    local oauthMakeProfileCallStatusMetric = OauthClient.oauthHttpCallsMetric .. '.makeValidateTokenCall.status.' .. res.status
    self:increment(oauthMakeProfileCallStatusMetric)
    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
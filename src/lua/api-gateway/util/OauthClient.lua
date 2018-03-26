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
--- metrics for Dogstatsd
local httpCalls = 'oauth.http_calls'
local successfulHttpCalls = 'oauth.successful.http_calls'
local failedHttpCalls = 'oauth.failed.http_calls'

--- Increments the number of calls to the Oauth provider
--  @param metric - metric to be identified in the Dogstatsd dashboard
-- @return - void method
--
function OauthClient:increment(metric)
    if dogstats ~= nil then
        dogstats:increment(metric)
    else
        ngx.log(ngx.WARN, "Could not increment metric " .. metric .. " because dogstats could not be loaded")
    end
end

--- Measures the number of milliseconds elapsed
-- @param metric - metric to be identified in the Dogstatsd dashboard
-- @param ms - the time it took a call to finish in milliseconds
-- @return - void method
--
function OauthClient:time(metric, ms)
    if dogstats ~= nil then
        dogstats:time(metric, ms)
    else
        ngx.log(ngx.WARN, "Could not compute elapsed time for metric " .. metric .. " because dogstats could not be loaded")
    end
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
    self:increment(httpCalls)

    local elapsedTime = os.difftime(endTime,startTime) * 1000
    local elapsedTimeMetric = 'oauth.makeValidateTokenCall.duration'
    self:time(elapsedTimeMetric, elapsedTime)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        self:increment(failedHttpCalls)
        logLevel = ngx.WARN
    end
    self:increment(successfulHttpCalls)
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
    self:increment(httpCalls)

    local elapsedTime = os.difftime(endTime,startTime) * 1000
    local elapsedTimeMetric = 'oauth.makeProfileCall.duration'
    self:time(elapsedTimeMetric, elapsedTime)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        self:increment(failedHttpCalls)
        logLevel = ngx.WARN
    end
    self:increment(successfulHttpCalls)
    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
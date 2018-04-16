-- Copyright (c) 2018 Adobe Systems Incorporated. All rights reserved.
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

--- Namespace used for computing metric names for Dogstatsd
OauthClient.oauthHttpCallsNamespace = 'oauth.http_calls'

--- Increments the number of calls to the Oauth provider
--  @param metric - metric to be identified in the Dogstatsd dashboard
--  @return - void method
--
function OauthClient:increment(metric)
    dogstatsInstance:increment(metric, 1)
end

--- Measures the number of milliseconds elapsed
-- @param metric - metric to be identified in the Dogstatsd dashboard
-- @param ms - the time it took a call to finish in milliseconds
-- @return - void method
--
function OauthClient:time(metric, ms)
    dogstatsInstance:time(metric, ms)
end

--- Pushes metrics about the total number of https calls to the oauth provider,
--- the time it took for a http call to finish and the response status code.
---
-- @param oauthHttpCallsNamespace - Namespace used for computing metric names for Dogstatsd
-- @param methodName - The name of the method for which we are measuring http calls
-- @param startTime - The time the call was initiated
-- @param endTime - The time the call returned
-- @param statusCode - The status code returned by the call
-- @return - void method
--
function OauthClient:pushMetrics(oauthHttpCallsNamespace, methodName, startTime, endTime, statusCode)
    local noOfOauthHttpCallsMetric = oauthHttpCallsNamespace
    local elapsedTimeMetric = oauthHttpCallsNamespace .. '.' .. methodName .. '.duration'
    local oauthStatusMetric = oauthHttpCallsNamespace .. '.' .. methodName .. '.status.' .. statusCode

    local elapsedTime = string.format("%.3f", endTime - startTime)

    self:increment(noOfOauthHttpCallsMetric)
    self:time(elapsedTimeMetric, elapsedTime)
    self:increment(oauthStatusMetric)
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

    self:pushMetrics(self.oauthHttpCallsNamespace, 'makeValidateTokenCall', startTime, endTime, res.status)

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

    self:pushMetrics(self.oauthHttpCallsNamespace, 'makeProfileCall', startTime, endTime, res.status)

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end

    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
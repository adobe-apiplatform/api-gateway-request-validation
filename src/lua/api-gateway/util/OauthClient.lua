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


--- Loads a lua gracefully. If the module doesn't exist the exception is caught, logged and the execution continues
-- @param module path to the module to be loaded
--
local function loadrequire(module)
    ngx.log(ngx.DEBUG, "Loading module [" .. tostring(module) .. "]")
    local function requiref(module)
        require(module)
    end

    local res, cls = pcall(requiref, module)
    if res then
        return cls
    else
        ngx.log(ngx.WARN, "Could not load module [", module, "].")
        return nil
    end
end

--- Returns an instance of dogstatsd only if it does not already exist
function OauthClient:getDogstatsd()

    if dogstatsd ~= nil then
        return dogstatsd
    end

    local restyDogstatsd = loadrequire('resty_dogstatsd')

    if restyDogstatsd == nil then
        return nil
    end

    local dogstatsd = restyDogstatsd.new({
        statsd = {
            host = "datadog.docker",
            port = 8125,
            namespace = "api_gateway",
        },
        tags = {
            "application:lua",
        },
    })
    return dogstatsd
end

--- Increments the number of calls to the Oauth provider
--  @param oauthCalls metric to be identified in the Dogstatsd dashboard
--
function OauthClient:incrementOauthCalls(oauthCalls)
    local dogstatsd
    if self.dogstatsd == nil then
        dogstatsd = self:getDogstatsd()
    end
    if dogstatsd ~= nil then
        dogstatsd:increment(oauthCalls, 1)
    end
end

local dogstatsd = require "api-gateway.dogstatsd.Dogstatsd"

local oauthCalls = 'oauth.http_calls'

function OauthClient:makeValidateTokenCall(internalPath, oauth_host, oauth_token)
    oauth_host = oauth_host or ngx.var.oauth_host
    oauth_token = oauth_token or ngx.var.authtoken

    ngx.log(ngx.INFO, "validateToken request to host=", oauth_host)


    local res = ngx.location.capture(internalPath, {
        share_all_vars = true,
        args = { authtoken = oauth_token }
    })

    self:incrementOauthCalls(oauthCalls)

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
    local res = ngx.location.capture(internalPath, { share_all_vars = true })

    local logLevel = ngx.INFO
    if res.status ~= 200 then
        logLevel = ngx.WARN
    end

    self:incrementOauthCalls(oauthCalls)

    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
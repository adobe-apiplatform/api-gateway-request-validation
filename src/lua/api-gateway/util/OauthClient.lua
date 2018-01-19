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

function OauthClient:makeValidateTokenCall(internalPath, oauth_host, oauth_token)
    oauth_host = oauth_host or ngx.var.oauth_host
    oauth_token = oauth_token or ngx.var.authtoken

    ngx.log(ngx.INFO, "validateToken request to host=", oauth_host)


    local res = ngx.location.capture(internalPath, {
        share_all_vars = true,
        args = { authtoken = oauth_token }
    })

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
    ngx.log(logLevel, "profileCall Host=", oauth_host, " responded with status=", res.status, " and x-debug-id=",
        tostring(res.header["X-DEBUG-ID"]), " body=", res.body)

    return res
end

return OauthClient
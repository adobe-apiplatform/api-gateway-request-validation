-- Copyright (c) 2017 Adobe Systems Incorporated. All rights reserved.
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

-- redis endpoints are assumed to be global per GW node and therefore are read here

local restyRedis = require "resty.redis"
local RedisHealthCheck = require "api-gateway.redis.redisHealthCheck"
local apiGatewayRedisReadReplica = "api-gateway-redis-replica"
local redisConfiguration = require "api-gateway.redis.redisConnectionConfiguration"

local redisHealthCheck = RedisHealthCheck:new({
    shared_dict = "cachedkeys"
})

local max_idle_timeout = 30000
local pool_size = 100

local RedisConnectionProvider = {}

function RedisConnectionProvider:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function RedisConnectionProvider:isNotEmpty(s)
    return s ~= nil and s ~= ''
end


function RedisConnectionProvider:getRedisUpstream(upstream_name)
    local upstream_name = upstream_name or apiGatewayRedisReadReplica
    local _, host, port = redisHealthCheck:getHealthyRedisNode(upstream_name)
    ngx.log(ngx.DEBUG, "Obtained Redis Host:" .. tostring(host) .. ":" .. tostring(port), " from upstream:", upstream_name)
    if (nil ~= host and nil ~= port) then
        return host, port
    end

    ngx.log(ngx.ERR, "Could not find a Redis upstream.")
    return nil, nil
end


-- Redis authentication
function RedisConnectionProvider:getConnection(connection_options)
    local redisUpstream = connection_options["upstream"]
    local redisPassword = connection_options["password"]
    local redisHost, redisPort = self:getRedisUpstream(redisUpstream)

    return self:connectToRedis(redisHost, redisPort, redisPassword)
end


function RedisConnectionProvider:connectToRedis(host, port, password)
    local redis = restyRedis:new()
    local ok, err = redis:connect(host, port)

    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis instance: " .. host .. ", port: " .. port .. ". Error: ", err)
        return false, nil
    end

    if self:isNotEmpty(password) then
        -- Authenticate
        local ok, err = redis:auth(password)
        if not ok then
            ngx.log(ngx.ERR, "Redis authentication failed for server: " .. host .. ":" .. port .. ". Error: ", err)
            return false, nil
        end
        ngx.log(ngx.DEBUG, "Redis authentication successful")
        return ok, redis
    else
        ngx.log(ngx.DEBUG, "No password authentication for Redis")
        return true, redis
    end
end


function RedisConnectionProvider:closeConnection(redis_instance)
    redis_instance:set_keepalive(max_idle_timeout, pool_size)
end

function RedisConnectionProvider:closeConnectionWithTimeout(redis_instance, max_idle_timeout)
    redis_instance:set_keepalive(max_idle_timeout, pool_size)
end

return RedisConnectionProvider
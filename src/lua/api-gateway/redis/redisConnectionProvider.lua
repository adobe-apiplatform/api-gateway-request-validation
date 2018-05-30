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

--- Redis connection provider module with retry and keepalive functionalities

local restyRedis = require "resty.redis"
local RedisHealthCheck = require "api-gateway.redis.redisHealthCheck"
local apiGatewayRedisReadReplica = "api-gateway-redis-replica"

local redisHealthCheck = RedisHealthCheck:new({
    shared_dict = "cachedkeys"
})

local max_idle_timeout = 30000
local pool_size = 100
local default_redis_timeout = 5000

local RedisConnectionProvider = {}

function RedisConnectionProvider:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

local function isNotEmpty(s)
    return s ~= nil and s ~= ''
end

--- Searches and returns a Redis upstream pair (host:port) based on the name provided
--- @param upstream_name The Redis upstream name, as defined in the Nginx conf file
--- @return Redis host
--- @return Redis port
function RedisConnectionProvider:getRedisUpstream(upstream_name)
    local upstreamName = upstream_name or apiGatewayRedisReadReplica
    local _, host, port = redisHealthCheck:getHealthyRedisNode(upstreamName)
    ngx.log(ngx.DEBUG, "Obtained Redis Host:" .. tostring(host) .. ":" .. tostring(port), " from upstream:", upstreamName)
    if (nil ~= host and nil ~= port) then
        return host, port
    end

    ngx.log(ngx.ERR, "Could not find a Redis upstream.")
    return nil, nil
end

--- Obtains a connection to a provided upstream using an optionally provided password and timeout
--- If no password is provided, it is searched in the REDIS_PASS and REDIS_PASSWORD env variables
--- If the first connection attempt fails, a second retry is automatically performed with the same connection options
--- @param connection_options If this is a table, it should have upstream, password and redis_timeout.
--- Otherwise, the connection_options is considered the upstream name
function RedisConnectionProvider:getConnection(connection_options)
    local redisUpstream,
    redisPassword,
    redisTimeout;

    if (type(connection_options) == 'table') then
        redisUpstream = connection_options["upstream"]
        redisPassword = connection_options["password"]
        redisTimeout = connection_options["redis_timeout"]
    else
        redisUpstream = connection_options
        redisPassword = os.getenv('REDIS_PASS') or os.getenv('REDIS_PASSWORD') or ''
    end

    local redisHost, redisPort = self:getRedisUpstream(redisUpstream)
    ngx.log(ngx.DEBUG, "Trying with: " .. tostring(redisHost) .. " and " .. tostring(redisPort))
    local status, redisInstance = self:connectToRedis(redisHost, redisPort, redisPassword, redisTimeout)
    if not status then
        -- retry
        ngx.log(ngx.WARN, "Connection to Redis failed. Retrieving new Redis host and retrying")
        redisHost, redisPort = self:getRedisUpstream(redisUpstream)
        ngx.log(ngx.DEBUG, "Got new upstream: " .. tostring(redisHost) .. " and " .. tostring(redisPort))
        status, redisInstance = self:connectToRedis(redisHost, redisPort, redisPassword, redisTimeout)
    end
    return status, redisInstance
end

function RedisConnectionProvider:connectToRedis(host, port, password, redisTimeout)
    local redis = restyRedis:new()

    -- sets general timeout - for all operations
    local redis_timeout = redisTimeout or ngx.var.redis_timeout or default_redis_timeout
    redis:set_timeout(redis_timeout)

    local ok, err = redis:connect(host, port)

    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis instance: " .. host .. ", port: " .. port .. ". Error: ", err)
        return false, nil
    end

    if isNotEmpty(password) then
        -- Authenticate
        ok, err = redis:auth(password)
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
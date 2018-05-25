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


--
-- Created by IntelliJ IDEA.
-- User: nramaswa
-- Date: 4/17/14
-- Time: 7:38 PM
-- To change this template use File | Settings | File Templates.
--


-- Base class for redis health check to get the healthy node

local base = require "api-gateway.validation.base"

local HealthCheck = {}
local DEFAULT_SHARED_DICT = "cachedkeys"

function HealthCheck:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if ( o ~= nil ) then
        self.shared_dict = o.shared_dict or DEFAULT_SHARED_DICT
    end
    return o
end

local function split(inputStr, separator)
    if separator == nil then
        separator = "%s"
    end

    local table = {}
    local index = 1
    for str in string.gmatch(inputStr, "([^%s" .. separator .. "]+)") do
        table[index] = str
        index = index + 1
    end
    return table
end

local function isPeerHealthy(peerName)

    local peerAddress = split(peerName, ":")
    
    -- for now, we should only validate host:port
    if #peerAddress ~= 2 then
        return false
    end

    local peerHost = peerAddress[1]
    local peerPort = peerAddress[2]

    ngx.log(ngx.DEBUG, "Checking health for: " .. tostring(peerHost) .. ":" .. tostring(peerPort))
    local socket = ngx.socket.tcp
    local tcp = socket()
    local ok, err = tcp:connect(peerHost, peerPort)
    if not ok then
        tcp:close()
        return false
    end
    tcp:settimeout(2000)
    tcp:send("PING\r\n")
    local message, status, partial = tcp:receive()
    tcp:close()
    return message and string.match(message, "PONG")
end

local function gen_peers_status_info(peers, bits, idx)
    local npeers = #peers
    for i = 1, npeers do
        local peer = peers[i]
        local peerName = peer.name
        bits[idx] = peerName

        if isPeerHealthy(peerName) then
            bits[idx + 1] = " up\n"
        else
            bits[idx + 1] = " DOWN\n"
        end
        idx = idx + 2
    end
    return idx
end

-- Pass the name of any upstream for which the health check is performed by the
-- "resty.upstream.healthcheck" module. This is only to get the results of the healthcheck
local function getHealthCheckForUpstream(upstreamName)
    local ok, upstream = pcall(require, "ngx.upstream")
    if not ok then
        error("ngx_upstream_lua module required")
    end

    local get_primary_peers = upstream.get_primary_peers
    local get_backup_peers = upstream.get_backup_peers

    local ok, new_tab = pcall(require, "table.new")
    if not ok or type(new_tab) ~= "function" then
        new_tab = function(narr, nrec)
            return {}
        end
    end

    local n = 1
    local bits = new_tab(n * 20, 0)
    local idx = 1

    local peers, err = get_primary_peers(upstreamName)
    if not peers then
        return "failed to get primary peers in upstream " .. upstreamName .. ": "
                .. err
    end

    idx = gen_peers_status_info(peers, bits, idx)

    peers, err = get_backup_peers(upstreamName)
    if not peers then
        return "failed to get backup peers in upstream " .. upstreamName .. ": "
                .. err
    end

    idx = gen_peers_status_info(peers, bits, idx)

    return bits
end

local function getHealthyRedisNodeFromCache(dict_name, upstream_name)
    local dict = ngx.shared[dict_name];
    local upstreamRedis
    if ( nil ~= dict ) then
        upstreamRedis = dict:get("healthy_redis_upstream:" .. tostring(upstream_name) )
    end
    return upstreamRedis
end

local function updateHealthyRedisNodeInCache(dict_name, upstream_name, healthy_redis_host)
    local dict = ngx.shared[dict_name];
    if ( nil ~= dict ) then
        ngx.log(ngx.DEBUG, "Saving a healthy redis host:", healthy_redis_host, " in cache:", dict_name, " for upstream:", upstream_name)
        local exp_time_in_seconds = 5
        dict:set("healthy_redis_upstream:" .. tostring(upstream_name), healthy_redis_host, exp_time_in_seconds)
        return
    end

    ngx.log(ngx.WARN, "Dictionary ", dict_name, " doesn't seem to be set. Did you define one ? ")
end

local function getHostAndPortInUpstream(upstreamRedis)
    local p = {}
    p.host = upstreamRedis

    local idx = string.find(upstreamRedis, ":", 1, true)
    if idx then
        p.host = string.sub(upstreamRedis, 1, idx - 1)
        p.port = tonumber(string.sub(upstreamRedis, idx + 1))
    end
    return p.host, p.port
end

-- Get the redis node to use for read.
-- Returns 3 values: <upstreamName , host, port >
-- The difference between upstream and <host,port> is that the upstream may be just a string containing host:port
function HealthCheck:getHealthyRedisNode(upstream_name)

    -- get the Redis host and port from the local cache first
    local healthy_redis_host = getHealthyRedisNodeFromCache(self.shared_dict, upstream_name)
    if ( nil ~= healthy_redis_host) then
        local host, port = getHostAndPortInUpstream(healthy_redis_host)
        return healthy_redis_host, host, port
    end

    ngx.log(ngx.DEBUG, "Looking up for a healthy redis node in upstream:", upstream_name)
    -- if the Redis host is not in the local cache get it from the upstream configuration
    local redisUpstreamHealthResult = getHealthCheckForUpstream(upstream_name)

    if (redisUpstreamHealthResult == nil) then
        ngx.log(ngx.ERR, "\n No upstream results found for redis!!! ")
        return nil
    end

    for key, value in ipairs(redisUpstreamHealthResult) do
        -- return the first node found to be up.
        -- TODO: save all the nodes that are up and return them using round-robin alg
        if (value == " up\n") then
            healthy_redis_host = redisUpstreamHealthResult[key - 1]
            updateHealthyRedisNodeInCache(self.shared_dict, upstream_name, healthy_redis_host)
            local host, port = getHostAndPortInUpstream(healthy_redis_host)
            return healthy_redis_host, host, port
        end
        if (value == " DOWN\n" and redisUpstreamHealthResult[key - 1] ~= nil ) then
            ngx.log(ngx.WARN, "\n Redis node " .. tostring(redisUpstreamHealthResult[key - 1]) .. " is down! Checking for backup nodes. ")
        end
    end

    ngx.log(ngx.ERR, "\n All Redis nodes are down!!! ")
    return nil -- No redis nodes are up
end

return HealthCheck
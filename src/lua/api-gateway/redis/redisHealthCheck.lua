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


--- Redis healthcheck module, which checks for both primary and backup upstreams health,
-- required by the RedisConnectionProvider module

local RedisHealthCheck = {}
local DEFAULT_SHARED_DICT = "cachedkeys"
local HEALTHY_REDIS_UPSTREAM_KEY_PREFIX = "healthy_redis_upstream:"

function RedisHealthCheck:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if (o ~= nil) then
        self.sharedDictionary = o.sharedDictionary or DEFAULT_SHARED_DICT
    end
    return o
end

--- Splits a string by a given separator
-- @param inputStr The string to be split
-- @param separator The separator used in splitting
-- @return Array containing the substrings after separation
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

--- Splits the host:port upstream format into corresponding fields
-- @param upstreamRedis Upstream address as host:port
-- @return Upstream host
-- @return Upstream port
local function getHostAndPortInUpstream(upstreamRedis)
    local host, port
    local upstreamNameSeparator = ":"
    local splitUpstreamAddress = split(upstreamRedis, upstreamNameSeparator)
    -- For the moment, validate the address is host:port
    if #splitUpstreamAddress == 2 then
        host = splitUpstreamAddress[1]
        port = splitUpstreamAddress[2]
    else
        return nil, nil
    end
    return host, port
end


--- Checks if a Redis peer is healthy by opening a TCP connection and sending a PING message. If upstream_password
--- is present, authentication is performed prior to pinging the machine
-- @param peerName Redis upstream in host:port format
-- @param upstreamPassword upstream password used for authentication before pinging
-- @return true if the peer is considered healthy (PING response is PONG), false otherwise (password may be incorrect,
-- instance may be down)
local function isPeerHealthy(upstream, upstreamPassword)

    local performRedisAdvancedHealthcheck = ngx.var.redis_advanced_healthcheck
    if not performRedisAdvancedHealthcheck or performRedisAdvancedHealthcheck == "" or performRedisAdvancedHealthcheck == "false" then
        ngx.log(ngx.DEBUG, "No advanced healthcheck, assuming peer is healthy: " .. tostring(upstream))
        return true
    end

    local authMessage = "AUTH "
    local successfulAuthResponse = "OK"
    local pingMessage = "PING\r\n"
    local pongResponse = "PONG"

    local peerHost, peerPort = getHostAndPortInUpstream(upstream)

    -- for now, we should only validate host:port
    if peerHost == nil or peerPort == nil then
        return false
    end

    ngx.log(ngx.DEBUG, "Checking health for: " .. tostring(peerHost) .. ":" .. tostring(peerPort))
    local socket = ngx.socket.tcp
    local tcpSocket = socket()
    local ok, err = tcpSocket:connect(peerHost, peerPort)
    if err or not ok then
        ngx.log(ngx.ERR, "Could not open TCP connection to Redis: ", err)
        tcpSocket:close()
        return false
    end

    tcpSocket:settimeout(2000)

    -- Remove spaces to eliminate false lengths
    if upstreamPassword ~= nil then
        upstreamPassword = string.gsub(upstreamPassword, "%s+", "")
    end

    -- First auth using provided password
    if upstreamPassword and upstreamPassword ~= nil and upstreamPassword ~= '' and type(upstreamPassword) == 'string' then
        tcpSocket:send(authMessage .. upstreamPassword .. '\r\n')
        local message, err, _ = tcpSocket:receive()
        if err then
            ngx.log(ngx.ERR, "Error while receiving message from Redis: ", err)
            tcpSocket:close()
            return false
        end
        if not message or not string.match(message, successfulAuthResponse) then
            return false
        end
    end

    tcpSocket:send(pingMessage)
    local message, err, _ = tcpSocket:receive()
    tcpSocket:close()
    if err then
        ngx.log(ngx.ERR, "Error while health checking Redis: ", err)
        return false
    end
    return message and string.match(message, pongResponse)
end

--- Generates peers health status
-- @param peers Array of peers to be health checked
-- @param upstreamPassword Peer password used for authentication prior to health checking (one password for now)
-- @return Upstream status array as peer -> 1 (healthy), 0(unhealthy)
local function generatePeersStatus(peers, upstreamPassword)
    local status = {}
    for i = 1, #peers do
        local currentPeerName = peers[i].name
        if isPeerHealthy(currentPeerName, upstreamPassword) then
            status[currentPeerName] = 1
        else
            status[currentPeerName] = 0
        end
    end
    return status
end

--- Checks for healthy upstreams using the ngx_upstream_lua module. It checks for both primary and secondary peers
-- @param upstream The name of the upstream, as defined in the conf files
-- @param upstreamPassword The password for the upstream, needed to perform authentication prior to the actual healthcheck
-- @return Upstream status as a table containing host:port -> 1(healthy) or 0(unhealthy)
local function getHealthCheckForUpstream(upstream, upstreamPassword)
    local ok, upstreamModule = pcall(require, "ngx.upstream")
    if not ok then
        error("ngx_upstream_lua module required")
    end

    local get_primary_peers = upstreamModule.get_primary_peers
    local get_backup_peers = upstreamModule.get_backup_peers

    local peersStatus = {}

    local primaryPeers, err = get_primary_peers(upstream)
    if err or not primaryPeers then
        ngx.log(ngx.ERR, "Failed to get primary peers in upstream " .. tostring(upstream) .. ":" .. err)
    else
        local primaryPeersStatus = generatePeersStatus(primaryPeers, upstreamPassword)

        if primaryPeersStatus ~= nil then
            for k, v in pairs(primaryPeersStatus) do
                peersStatus[k] = v
            end
        end
    end

    local backupPeers, err = get_backup_peers(upstream)

    if err or not backupPeers then
        ngx.log(ngx.ERR, "Failed to get backup peers in upstream " .. tostring(upstream) .. ":" .. err)
    else
        local backupPeersStatus = generatePeersStatus(backupPeers, upstreamPassword)
        if backupPeersStatus ~= nil then
            for k, v in pairs(backupPeersStatus) do
                peersStatus[k] = v
            end
        end

    end

    return peersStatus
end

--- Returns the upstream address from the shared cache
-- @param dictionaryName Shared dictionary containing the cached entries
-- @param upstreamName The name of the upstream, used in the caching key
-- @return Upstream address as host:port
local function getHealthyRedisNodeFromCache(dictionaryName, upstreamName)
    local dict = ngx.shared[dictionaryName];
    local upstreamRedis
    if (nil ~= dict) then
        upstreamRedis = dict:get(HEALTHY_REDIS_UPSTREAM_KEY_PREFIX .. tostring(upstreamName))
    end
    return upstreamRedis
end

--- Sets the healthy upstream address in the shared cache
-- @param dictionaryName Shared dictionary containing the cached entries
-- @param upstreamName The name of the upstream, used in the caching key
-- @param healthyRedisHost Upstream address as host:port
local function updateHealthyRedisNodeInCache(dictionaryName, upstreamName, healthyRedisHost)
    local dict = ngx.shared[dictionaryName];
    if (nil ~= dict) then
        ngx.log(ngx.DEBUG, "Saving a healthy redis host:", healthyRedisHost, " in cache:", dictionaryName, " for upstream:", upstreamName)
        local expiryTimeInSeconds = 5
        dict:set(HEALTHY_REDIS_UPSTREAM_KEY_PREFIX .. tostring(upstreamName), healthyRedisHost, expiryTimeInSeconds)
        return
    end
    ngx.log(ngx.WARN, "Dictionary ", dictionaryName, " doesn't seem to be set. Did you define one ? ")
end

--- Checks for healthy Redis nodes and returns the first correct value
-- @param upstream The name of the upstream for which a healthy address is to be found
-- @param upstreamPassword The password for the upstream, should this need authentication prior to health checking
-- @return Full upstream address as host:port
-- @return Upstream host
-- @return Upstream port
function RedisHealthCheck:getHealthyRedisNode(upstream, upstreamPassword)

    -- get the Redis host and port from the local cache first
    local healthyRedisHost = getHealthyRedisNodeFromCache(self.sharedDictionary, upstream)
    if (nil ~= healthyRedisHost) then
        local host, port = getHostAndPortInUpstream(healthyRedisHost)
        return healthyRedisHost, host, port
    end

    ngx.log(ngx.DEBUG, "Looking up for a healthy redis node in upstream:", upstream)
    -- if the Redis host is not in the local cache get it from the upstream configuration
    local redisUpstreamHealthResult = getHealthCheckForUpstream(upstream, upstreamPassword)

    if (redisUpstreamHealthResult == nil) then
        ngx.log(ngx.ERR, "No upstream results found for Redis!!!")
        return nil, nil, nil
    end
    for upstream, status in pairs(redisUpstreamHealthResult) do
        -- return the first node found to be up.
        if (status == 1) then
            healthyRedisHost = upstream
            updateHealthyRedisNodeInCache(self.sharedDictionary, upstream, healthyRedisHost)
            local host, port = getHostAndPortInUpstream(healthyRedisHost)
            return healthyRedisHost, host, port
        end
    end

    ngx.log(ngx.ERR, "All Redis nodes are down!!!")
    return nil, nil, nil
end

return RedisHealthCheck
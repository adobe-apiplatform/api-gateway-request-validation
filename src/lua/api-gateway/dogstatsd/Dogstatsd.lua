
--- Auxiliary module used to extract dogstats deamon initialization methods, incrementation of metrics
-- and calls to other useful functions
-- employed to measure calls to the Oauth provider: number, duration, etc.

local Dogstatsd = {}

function Dogstatsd:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Loads a lua gracefully. If the module doesn't exist the exception is caught, logged and the execution continues
-- @param module path to the module to be loaded
-- @return The loaded module, or nil if the module cannot be loaded
--
local function loadrequire(module)
    ngx.log(ngx.DEBUG, "Loading module [" .. tostring(module) .. "]")
    local function requiref(module)
        require(module)
    end

    local res, cls = pcall(requiref, module)
    if not (res) then
        ngx.log(ngx.WARN, "Could not load module [", module, "].")
        return nil
    end

    return cls
end

local dogstatsd

--- Returns an instance of dogstatsd only if it does not already exist
-- @param none
-- @return An instance of dogstatsd or nil if the class cannot be instantiated
--
local function getDogstatsd()

    if dogstatsd ~= nil then
        return dogstatsd
    end

    local restyDogstatsd = loadrequire('resty_dogstatsd')

    if restyDogstatsd == nil then
        return nil
    end

    dogstatsd = restyDogstatsd.new({
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
--  @param metric - metric to be identified in the Dogstatsd dashboard
-- @return - void method
--
function Dogstatsd:increment(metric)
    dogstatsd = getDogstatsd()

    if dogstatsd ~= nil then
        dogstatsd:increment(metric, 1)
    end
end

return Dogstatsd



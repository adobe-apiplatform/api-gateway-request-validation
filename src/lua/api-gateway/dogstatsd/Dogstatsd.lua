
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
    local function requiref(module)
        require(module)
    end

    local res = pcall(requiref, module)
    if not (res) then
        ngx.log(ngx.WARN, "Module ", module, " was not found.")
        return nil
    end
    return require(module)
end

local dogstatsd

--- Returns an instance of dogstatsd only if it does not already exist. Returns the instance if the feature is enabled
-- @param none
-- @return An instance of dogstatsd or nil if the class cannot be instantiated
--
local function getDogstatsd()
    if ngx.var.isDogstatsEnabled == nil or ngx.var.isDogstatsEnabled == "false" then
        ngx.log(ngx.INFO, "dogstats module is disabled")
        return nil
    end

    if dogstatsd ~= nil then
        return dogstatsd
    end

    local restyDogstatsd = loadrequire('resty_dogstatsd')

    if restyDogstatsd == nil then
        ngx.log(ngx.WARN, "Could not loadrequire resty_dogstatsd.")
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
    ngx.log(ngx.DEBUG, "Instantiated dogstatsd.")
    return dogstatsd
end

--- Increments the number of calls to the Oauth provider
-- @param metric - metric to be identified in the Dogstatsd dashboard
-- @return - void method
--
function Dogstatsd:increment(metric)
    dogstatsd = getDogstatsd()

    if dogstatsd ~= nil then
        dogstatsd:increment(metric, 1)
    end
end

--- Measures the number of milliseconds elapsed
-- @param metric - metric to be identified in the Dogstatsd dashboard
-- @param ms - the time it took a call to finish in milliseconds
-- @return - void method
--
function Dogstatsd:time(metric, ms)
    dogstatsd = getDogstatsd()

    if dogstatsd ~= nil then
        dogstatsd:timer(metric, ms)
    end
end

return Dogstatsd



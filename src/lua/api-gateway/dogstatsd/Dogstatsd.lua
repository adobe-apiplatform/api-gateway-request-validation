
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
    ngx.log(ngx.DEBUG, "Loading module [", tostring(module), "]")
    local function requiref(module)
        return require(module)
    end

    local status, result = pcall(requiref, module)
    if not (status) then
        ngx.log(ngx.WARN, "Could not load module [", module, "]. Error ", result)
        return nil
    end

    return result
end

local dogstatsd

--- Returns an instance of dogstatsd only if it does not already exist. Returns the instance if the feature is enabled
-- @param none
-- @return An instance of dogstatsd or nil if the class cannot be instantiated
--
local function getDogstatsd()

    local isDogstatsEnabled = ngx.var.isDogstatsEnabled
    if isDogstatsEnabled == nil or isDogstatsEnabled == "false" then
        ngx.log(ngx.INFO, "dogstats module is disabled")
        return nil
    end

    local dogstatsHost = ngx.var.dogstatsHost
    if dogstatsHost == nil or dogstatsHost == '' then
        ngx.log(ngx.ERR, "dogstats host was not defined")
        return nil
    end

    if dogstatsd ~= nil then
        return dogstatsd
    end

    local restyDogstatsd = loadrequire('resty_dogstatsd')

    if restyDogstatsd == nil then
        return nil
    end

    dogstatsd = restyDogstatsd.new({
        statsd = {
            host = dogstatsHost,
            port = ngx.var.dogstatsPort or 8125,
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
-- @param counter - the number of times we would like to have the metric incremented
-- @return - void method
--
function Dogstatsd:increment(metric, counter)
    dogstatsd = getDogstatsd()

    if dogstatsd ~= nil then
        ngx.log(ngx.DEBUG, "[Dogstatsd] Incrementing metric ", metric)
        dogstatsd:increment(metric, counter)
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
        ngx.log(ngx.DEBUG, "[Dogstatsd] Computing elapsed time for ", metric, ".Request duration ", ms)
        dogstatsd:timer(metric, ms)
    end
end

return Dogstatsd



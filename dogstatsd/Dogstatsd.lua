
local Dogstatsd = {}

function Dogstatsd:new(o)
    o = o or {}
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

    local res = pcall(requiref, module)
    if not (res) then
        ngx.log(ngx.WARN, "Could not load module [", module, "].")
        return nil
    end
    return require(module)
end

--- Returns an instance of dogstatsd only if it does not already exist
function Dogstatsd:getDogstatsd()

    if dogstatsd ~= nil then
        return dogstatsd
    end

    if restyDogstatsd == nil then
        return nil
    end

    local restyDogstatsd = loadrequire('resty_dogstatsd')
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
function Dogstatsd:incrementOauthCalls(oauthCalls)
    local dogstatsd
    if self.dogstatsd == nil then
        dogstatsd = self:getDogstatsd()
    end
    if dogstatsd ~= nil then
        dogstatsd:increment(oauthCalls, 1)
    end
end

return Dogstatsd



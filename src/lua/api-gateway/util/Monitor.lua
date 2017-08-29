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


local Monitor = {
    decorateFunction = nil,
    decorateClass = nil,
    decorateRedisCallsWithTimeElapsedFunction = nil
}

Monitor.decorateRedisCallsWithTimeElapsedFunction = function(name, fn)
    return function(...)
        local result
        local single_result = false
        local start_time, end_time, elapsed

        if(name == "restyRedis:hset") then
            start_time = os.clock()
            single_result = true
            result = fn(...)
            end_time = os.clock()
            elapsed = end_time - start_time
            ngx.log(ngx.WARN, "Execution for: " .. name .. " took: " .. elapsed * 100000)
        end

        start_time = os.clock()
        local ok, err = fn(...)
        end_time = os.clock()
        elapsed = end_time - start_time
        ngx.log(ngx.WARN, "Execution for: " .. name .. " took: " .. elapsed * 100000)

        if(single_result) then
            return result
        else
            return ok, err
        end
    end
end

Monitor.decorateFunction = function(name, fn, decorationFunction)
    if(not fn or type(fn) ~= 'function') then
        return fn
    end

    if not decorationFunction or type(decorationFunction) ~= 'function' then
        local localFn = function( ... )
            print("start " .. name)
            local result = fn(...)
            print("end " .. name)
            return result
        end

        return localFn
    end

    return decorationFunction(name, fn)
end

Monitor.decorateClass = function(name, class, methods, decorationFunction)
    if(not class or type(class) ~= 'table') then
        return class
    end

    methods = methods or {}

    local all = false
    if #methods == 0 then
        all = true
    end

    if all then
        for k, v in pairs(class) do
            class[k] = Monitor.decorateFunction(name .. ":" .. k, v, decorationFunction)
        end
    else
        for k, v in ipairs(methods) do
            class[v] = Monitor.decorateFunction(name .. ":" .. v, class[v], decorationFunction)
        end
    end

    return class
end

return Monitor




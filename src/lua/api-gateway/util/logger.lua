-- Copyright (c) 2018 Adobe Systems Incorporated. All rights reserved.
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

local set = false

---
-- Checks and returns the ngx.var.requestId if possible
-- ngx.var is not accessible in some nginx phases like init phase and so we also check this
--
local function is_in_init_phase()
    return ngx.var.requestId
end

---
-- Get an error log format level, [file:currentline:function_name() req_id=<request_id>], message. This is passed to the
-- original ngx.log function
-- @param level - the log level like ngx.DEBUG, ngx.INFO, etc.
-- @param debugInfo - the debug.getinfo() table needed for the stacktrace
-- @param ... - other variables normally passed to ngx.log(), in general string concatenation
--
local function getLogFormat(level, debugInfo, ...)
    local status, request_id = pcall(is_in_init_phase)
    --- testing for init phase
    if not status then
       request_id = "N/A"
    end

    return level, "[", debugInfo.short_src,
    ":", debugInfo.currentline,
    ":", debugInfo.name,
    "() req_id=", tostring(request_id),
    "] ", ...
end

---
-- Replaces the ngx.log function with the original ngx.log but redecorate the message
--
local function _decorateLogger()
    if not set then
        local oldNgx = ngx.log
        ngx.log = function(level, ...)
            -- gets the level 2 because level 1 is this function and I need my caller
            -- nSl means line, name, source
            local debugInfo =  debug.getinfo(2, "nSl")
            pcall(function(...)
                oldNgx(getLogFormat(level, debugInfo, ...))
            end, ...)
        end
        set = true
    end
end

return {
    decorateLogger = _decorateLogger
}
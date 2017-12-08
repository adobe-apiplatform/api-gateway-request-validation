local set = false

function getLogFormatExtended(level, debugInfo, ...)
    return level, "[", debugInfo.short_src,
        ":", debugInfo.currentline,
        ":", debugInfo.name,
        "() req_id=", ngx.var.requestId,
        "] ", ...
end

function getLogFormat(level, debugInfo, ...)
    return level, "[", debugInfo.short_src,
    ":", debugInfo.currentline,
    ":", debugInfo.name,
    "()]", ...
end

function _decorateLogger()
    if not set then
        local oldNgx = ngx.log
        ngx.log = function(level, ...)
            local debugInfo =  debug.getinfo(2)
            if not pcall(function()
                oldNgx(getLogFormatExtended(level, debugInfo, ...))
            end) then
                oldNgx(getLogFormat(level, debugInfo, ...))
            end
        end
        set = true
    end
end

return {
    decorateLogger = _decorateLogger
}
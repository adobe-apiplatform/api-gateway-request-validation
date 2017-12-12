local set = false

function getLogFormat(level, debugInfo, ...)
    return level, "[", debugInfo.short_src,
        ":", debugInfo.currentline,
        ":", debugInfo.name,
        "() req_id=", tostring(ngx.var.requestId),
        "] ", ...
end

function _decorateLogger()
    if not set then
        local oldNgx = ngx.log
        ngx.log = function(level, ...)
            local debugInfo =  debug.getinfo(2)
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
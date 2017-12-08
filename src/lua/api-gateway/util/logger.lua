local oldNgx

function post_init_phase()
    return true
end

function getLogFormat(level, debugInfo, ...)
    if pcall(post_init_phase) then
        return level, "[", debugInfo.short_src,
        ":", debugInfo.currentline,
        ":", debugInfo.name,
        "() req_id=", ngx.var.requestId,
        "] ", ...
    else
        return level, "[", debugInfo.short_src,
        ":", debugInfo.currentline,
        ":", debugInfo.name,
        "()] ", ...
    end
end

function _decorateLogger()
    if not oldNgx then
        oldNgx = ngx.log
        ngx.log = function(level, ...)
            local debugInfo =  debug.getinfo(2)
            oldNgx(getLogFormat(level, debugInfo, ...))
        end
    end
end

return {
    decorateLogger = _decorateLogger
}
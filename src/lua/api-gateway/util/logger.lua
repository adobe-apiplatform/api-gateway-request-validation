local set = false

function _decorateLogger()
    if not set then
        local oldNgx = ngx.log
        ngx.log = function(level, ...)
            local debugInfo =  debug.getinfo(2)
            pcall(function()
                oldNgx(level, "[", debugInfo.short_src,
                ":", debugInfo.currentline,
                ":", debugInfo.name,
                " req_id=", ngx.var.requestId, "] ", ...)
            end)
        end
        set = true
    end
end

return {
    decorateLogger = _decorateLogger
}
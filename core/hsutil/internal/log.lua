--- HSUtil.internal.log
--- 统一日志封装。基于 hs.logger。
--- 注意：hs.logger 实例方法是「静态」函数，必须用点号调用（l.i / l.f），
--- 且 i/w/e 接收多个字符串、f/wf/ef/df 才是 printf 格式化。
local log = {}

local loggers = {}        -- prefix -> hs.logger instance
log._globalLevel = "info" -- debug/info/warn/error/fatal

--- 设置全局 level（影响新建 logger）
function log.setLevel(level)
    log._globalLevel = level or "info"
    hs.logger.defaultLogLevel = level or "info"
end

--- 新建一个 logger，返回 hs.logger 实例。
--- 用法： l.f("hello %s", "world")  /  l.i("just a", "message")
--- @param prefix string 日志前缀
--- @param level string|nil debug/info/warning/error，默认全局
function log.new(prefix, level)
    local l = hs.logger.new(prefix, level or log._globalLevel)
    loggers[prefix] = l
    return l
end

--- HTTP 请求日志中间件工厂（供 server:use 使用）
--- 记录每个请求的 method/path/状态码/耗时。
function log.http()
    return function(req, res, next)
        local start = os.clock()
        next()
        local cost = math.floor((os.clock() - start) * 1000)
        local l = loggers["HSUtil.http"] or hs.logger.new("HSUtil.http", log._globalLevel)
        l.f("%s %s -> %d (%dms)", req.method, req.path, res._code, cost)
    end
end

return log

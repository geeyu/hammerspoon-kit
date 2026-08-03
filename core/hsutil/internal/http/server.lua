--- HSUtil.internal.http.server
--- HTTP server 封装。端口发现 + loopback + reload 安全。
local httpserver = require("hs.httpserver")
local router = require("HSUtil.internal.http.router")

local server = {}

--- 全局登记表（弱值），reload/shutdown 时遍历 stop
local registry = setmetatable({}, { __mode = "v" })
server._registry = registry

--- reload/shutdown 时清理旧 server
function server._cleanupAll()
    for _, s in pairs(registry) do
        pcall(function() s:stop() end)
    end
    registry = setmetatable({}, { __mode = "v" })
end

local Server = {}
Server.__index = Server

--- @param opts table|nil { port=0, loopback=true }
function server.new(opts)
    opts = opts or {}
    local r = router.new()
    local obj = setmetatable({
        _router = r,
        _port = tonumber(opts.port) or 0,
        _loopback = opts.loopback ~= false,
        _hs = nil,
        _actualPort = nil,
        _started = false,
    }, Server)
    -- 暴露路由方法（转发给内部 router）
    for _, m in ipairs({ "get","post","put","delete","patch","head","options","use","transform" }) do
        obj[m] = function(self, ...)
            r[m](r, ...)
            return self
        end
    end
    -- 静态文件快捷方法
    function obj.static(self, prefix, root)
        local s = require("HSUtil.internal.http.static")
        r:use(s.serve(prefix, root))
        return self
    end
    return obj
end

function Server:start()
    if self._started then return self end
    self._hs = httpserver.new(false, false)
    if self._loopback then
        self._hs:setInterface("loopback")
    end
    if self._port > 0 then
        self._hs:setPort(self._port)
    end
    self._hs:setCallback(function(method, pathStr, headers, body)
        return self._router:dispatch(method, pathStr, headers, body)
    end)
    self._hs:start()
    self._actualPort = self._hs:getPort()
    self._started = true

    table.insert(registry, self)
    return self
end

function Server:port()
    return self._actualPort
end

function Server:url()
    if not self._actualPort then return nil end
    return "http://127.0.0.1:" .. self._actualPort
end

function Server:stop()
    if self._hs and self._started then
        pcall(function() self._hs:stop() end)
        self._started = false
    end
end

return server

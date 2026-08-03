--- === HSUtil ===
--- 公共工具框架：HTTP 网关 + SQLite 薄层 ORM + util 底座。
--- 用法： local HSUtil = hs.loadSpoon("HSUtil")
local HSUtil = {}

if not HSUtil.spoonPath then
    local src = debug.getinfo(1, "S").source:sub(2)
    HSUtil.spoonPath = src:match("^(.*)/init%.lua$") or src:match("^(.*)/[^/]+$")
end

local internalDir = HSUtil.spoonPath .. "/internal"

-- 把 internal/*.lua 预注册进 package.preload，模块名 HSUtil.internal.<rel>
-- rel 用 "." 分隔（如 "db.orm"）。require 时按 Lua 5.4 的 _ENV/全局机制正常加载。
local function preload(name, rel)
    package.preload[name] = function(...)
        local fn, err = loadfile(internalDir .. "/" .. rel .. ".lua")
        if not fn then error(err, 2) end
        return fn(...)
    end
end

preload("HSUtil.internal.log", "log")
preload("HSUtil.internal.path", "path")
preload("HSUtil.internal.json", "json")
preload("HSUtil.internal.task", "task")
preload("HSUtil.internal.db.connection", "db/connection")
preload("HSUtil.internal.db.orm", "db/orm")
preload("HSUtil.internal.db.migrate", "db/migrate")
preload("HSUtil.internal.http.router", "http/router")
preload("HSUtil.internal.http.request", "http/request")
preload("HSUtil.internal.http.response", "http/response")
preload("HSUtil.internal.http.cors", "http/cors")
preload("HSUtil.internal.http.static", "http/static")
preload("HSUtil.internal.http.server", "http/server")
preload("HSUtil.internal.ui", "ui")
preload("HSUtil.internal.webview", "webview")
preload("HSUtil.internal._test", "_test")

HSUtil.log   = require("HSUtil.internal.log")
HSUtil.path  = require("HSUtil.internal.path")
HSUtil.json  = require("HSUtil.internal.json")
HSUtil.task  = require("HSUtil.internal.task")
HSUtil.db    = require("HSUtil.internal.db.connection")
HSUtil.db.orm     = require("HSUtil.internal.db.orm")
HSUtil.db.migrate = require("HSUtil.internal.db.migrate")
HSUtil.http        = {}
HSUtil.http.server = require("HSUtil.internal.http.server")
HSUtil.http.cors   = require("HSUtil.internal.http.cors")
HSUtil.http.log    = HSUtil.log.http

--- 固定端口 + base url 常量。各 Spoon / 前端统一引用，避免到处写死。
HSUtil.http.PORT    = 8821
HSUtil.http.HOST    = "127.0.0.1"
HSUtil.http.BASE   = "http://" .. HSUtil.http.HOST .. ":" .. HSUtil.http.PORT

-- 全局共享 server 单例：各 Spoon 注册路由到同一 server，避免各起各的端口
HSUtil.http.app = HSUtil.http.server.new({ port = HSUtil.http.PORT, loopback = true })
HSUtil.http.app:use(HSUtil.http.cors.new())
HSUtil.http.app:use(HSUtil.http.log())

-- 挂载共享 UI 资产静态路由（/hsutil/assets/*，各包 webview 前端共享）
local assetsDir = (function()
    local str = debug.getinfo(1, "S").source:sub(2)
    return (str:match("(.*[/\\])") or "") .. "assets"
end)()
-- UI 资产注册表 + HTML 占位符注入（<!-- hsutil:ui ... -->）
HSUtil.ui = require("HSUtil.internal.ui")
HSUtil.ui.init(assetsDir)
--- 面板 webview 生命周期（show/hide/Esc/失焦隐藏/reset 钩子），三 Spoon 共用
HSUtil.webview = require("HSUtil.internal.webview")
HSUtil.http.app:transform(HSUtil.ui.transform())
if HSUtil.http and HSUtil.http.app then
    pcall(function() HSUtil.http.app:static("/hsutil/assets", assetsDir) end)
end

-- reload 时清理旧 HTTP server（防止端口泄漏）
local function cleanupOnShutdown()
    if HSUtil.http and HSUtil.http._cleanupAll then
        pcall(HSUtil.http._cleanupAll)
    end
end
if hs.shutdown then
    local prev = hs.shutdown
    hs.shutdown = function()
        pcall(cleanupOnShutdown)
        if prev then prev() end
    end
else
    hs.shutdown = function() pcall(cleanupOnShutdown) end
end

return HSUtil

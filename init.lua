--- ============================================================
--- Hammerspoon Kit — 开源版入口
----
--- 组成（统一风格）：
---   * core/hsutil         核心框架（HTTP 网关 + SQLite ORM + UI 组件库）
---   * core/launcher       命令中枢（Option+Space）
---   * QuantumWindow.spoon 窗口管理（带 HUD）
---   * Clipboard.spoon     剪贴板历史（Ctrl+V）
---   * StayAwake.spoon     菜单栏防睡眠
--- ============================================================

hs.window.animationDuration = 0

-- 加载 ipc 模块（hs CLI 命令行依赖它常驻）
require("hs.ipc")

-- 公共工具框架（HTTP 网关 + SQLite ORM + util），核心层
local HS = require("core.hsutil")
-- 启动共享 HTTP server（各 Spoon 通过 HS.http.app 挂路由）
HS.http.app:start()
-- 端口启动检测：异常 reload（旧 server 未及时释放）时 hs.httpserver 绑定失败是静默的，
-- 前端全部 404。绑定失败时 getPort 返回 0/nil，显式告警便于排查
if not HS.http.app:port() or HS.http.app:port() == 0 then
    hs.logger.new("HSUtil", "error"):e(
        "HTTP server 启动失败：端口 %d 可能被占用，请重载 Hammerspoon 配置", HS.http.PORT)
end

-- 框架层：Launcher 命令中枢（core/launcher）
package.path = package.path .. ";" .. hs.configdir .. "/?.lua;" .. hs.configdir .. "/?/init.lua"
local launcher = require("core.launcher")
launcher:start()

-- QuantumWindow：窗口管理（分屏/Space/跨屏/铺满/居中 + HUD）
local qw = hs.loadSpoon("QuantumWindow")
qw:start()

-- Clipboard：剪贴板历史（Ctrl+V 面板，SQLite 持久化）
local ch = hs.loadSpoon("Clipboard")
ch:start()

-- StayAwake：菜单栏防睡眠（永久/小时/分钟/直到 + 双模式）
local stayAwake = hs.loadSpoon("StayAwake")
if stayAwake then
    stayAwake:start()
end

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", function()
    hs.reload()
    hs.alert.show("Hammerspoon 已重载")
end)

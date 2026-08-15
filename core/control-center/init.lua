--- === ControlCenter ===
---
--- 统一菜单栏控制中心：常驻菜单栏按钮（🛠，每次打开菜单重建）+ 聚合配置页
--- （webview 卡片网格，复用 HSUtil.webview / UI 组件库）。
--- 数据源只读复用各 Spoon 的 launcher-commands.lua 协议（internal/sources.lua，
--- 扫描 Spoons/*.spoon 与 core/*/，绝不写任何配置）；配置面板为单例
--- （internal/panel.lua，setUrl 切换）；HTTP 路由挂在 HSUtil 共享 server
--- （internal/api.lua，/control-center/api/*）。
---
--- 使用（框架层）：
---   require("core.control-center")   -- 自启：菜单栏按钮即现，无需显式 start()
---
--- 零侵入：只新增本目录 + 根 init.lua 一行 require；不写任何既有模块的
---         配置、不挂多余路由、不改 hsutil/Spoons 任何既有文件。
--- ============================================================

local obj = {}

obj.name = "ControlCenter"
obj.version = "1.0.0"
obj.author = "geeyu"
obj.homepage = "https://github.com/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- 定位本模块目录（core/control-center/；source 形如 core/control-center/init.lua）
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local modulePath = script_path()
local loadMod = function(n) return dofile(modulePath .. "internal/" .. n) end

-- 加载各层（按目录 dofile 兄弟模块）
local sources = loadMod("sources.lua")   -- 只读数据源（scan/get）
local panel   = loadMod("panel.lua")     -- 配置面板单例（open/hide，惰性创建）
local api     = loadMod("api.lua")       -- HTTP 路由（providers/open/close + 静态）
local menubar = loadMod("menubar.lua")   -- 常驻菜单栏按钮（每次打开菜单重建）

local HSUtil = require("core.hsutil")

obj.sources = sources
obj.panel = panel
obj.api = api
obj.menubar = menubar
obj.logger = HSUtil.log.new("ControlCenter")

-- 运行期状态
obj.started = false

--- ControlCenter:start()
--- Method：装配并启动（require 时自动调用一次，幂等）：
---   * 面板单例 setup（aggregateUrl 指向聚合配置页；webview 懒创建，首次 open 才建）
---   * HTTP 路由 + 前端静态挂载（api.setup，共享 server 端口 8821）
---   * 常驻菜单栏按钮（menubar 注入同一 sources/panel 实例，避免面板双实例）
function obj:start()
    if obj.started then return self end

    -- 聚合配置页 URL（api.setup 把本目录 views/ 挂到 /control-center/view）
    local aggregateUrl = HSUtil.http.BASE .. "/control-center/view/pages/control-center/index.html"

    -- 配置面板单例：注入聚合页目标（懒创建，首次 open 才建 webview）
    panel.setup({ aggregateUrl = aggregateUrl })

    -- HTTP 路由（providers/open/close + 前端静态，/control-center 命名空间）
    api.setup(sources, panel, modulePath .. "views")

    -- 常驻菜单栏：注入同一 sources/panel 实例（聚合页目标经 panel.setup 已就绪）
    menubar.setup({ sources = sources, panel = panel })
    menubar.start()

    obj.started = true
    obj.logger.f("ControlCenter 已启动（菜单栏 🛠，聚合配置页 %s）", aggregateUrl)
    return self
end

--- ControlCenter:stop()
--- Method：移除菜单栏按钮 + 销毁面板（模块卸载时）
function obj:stop()
    menubar.stop()
    panel.teardown()
    obj.started = false
    return self
end

-- 模块自启：require 即生效（与 HSUtil 模式一致，免显式 start() 调用）
obj:start()

return obj

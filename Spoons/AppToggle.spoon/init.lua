--- === AppToggle ===
---
--- 任意应用一键显隐（全局热键，带管理页面）。
--- 基于 core/app-toggle.lua 引擎封装：应用列表（Bundle ID + 热键 + 选项）
--- 存 SQLite，管理页可增删改/录制热键/测试/查看清除布局。
---
--- 能力：
---   * 每个应用一个全局热键：呼出（鼠标所在屏锁定布局）/ 隐藏（记录布局）
---   * 布局锁定：调整好窗口后按热键隐藏即记录该屏布局并持久化，呼出时还原；
---     跨屏呼出自动移动窗口；全屏 Space 上呼出 → 全屏形态接管
---   * 管理页面（/apptoggle/view/pages/apps/）：应用 CRUD + 热键录制 + 测试 +
---     布局查看/清除 + 运行状态
---
--- 使用：
---   local at = hs.loadSpoon("AppToggle")
---   at:start()          -- 加载配置 + 绑定全部启用应用的热键
---   at:showManager()    -- 打开管理页面（也可走 Launcher 卡片「应用显隐」）
--- ============================================================

local obj = {}

obj.name = "AppToggle"
obj.version = "1.0.0"
obj.author = "geeyu"
obj.homepage = "https://github.com/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- 定位本 spoon 目录
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local spoonPath = script_path()
local loadMod = function(n) return dofile(spoonPath .. "internal/" .. n) end

-- 加载各层
local config  = loadMod("config.lua")
local store   = loadMod("store.lua")
local manager = loadMod("manager.lua")
local api     = loadMod("api.lua")

obj.config = config
obj.logger = hs.logger.new("AppToggle", "info")

--- AppToggle:start()
--- Method
--- 打开数据库 + 加载配置 + 绑定全部启用应用的热键 + 挂 API。幂等。
function obj:start()
    if self._started then return self end
    if not store.open(config.data_dir) then
        obj.logger.ef("无法打开数据库: %s", config.data_dir)
        return self
    end
    manager.setup(config, store)
    local ok, conflicts = manager.reloadAll()
    -- 挂 API 路由（含热键录制 guard + 静态 view）
    api.setup(config, manager, spoonPath .. "views")
    if not ok and conflicts and #conflicts > 0 then
        for _, c in ipairs(conflicts) do
            obj.logger.ef("「%s」(%s) 绑定失败: %s", c.name, c.bundle_id, c.err)
        end
    end
    self._started = true
    obj.logger.f("AppToggle 已启动（%d 个应用热键）", manager.boundCount())
    return self
end

--- AppToggle:stop()
--- Method
--- 释放全部热键并关闭数据库。
function obj:stop()
    manager.clear()
    pcall(store.close)
    self._started = false
    return self
end

--- AppToggle:reload()
--- Method
--- 配置变更后重载（热键重建）。
function obj:reload()
    manager.reloadAll()
    return self
end

--- AppToggle:showManager()
--- Method
--- 打开管理页面（webview 面板）。
function obj:showManager()
    if not self._started then self:start() end
    -- 使用 HSUtil.webview 统一生命周期（失焦隐藏/Esc 等）
    local HSUtil = require("core.hsutil")
    local view = HSUtil.webview.new({
        url = HSUtil.http.BASE .. "/" .. config.pkg .. "/view/pages/apps/index.html",
        widthRatio = 0.62,
        heightRatio = 0.7,
        yRatio = 0.12,
        screenFor = function() return hs.screen.mainScreen() end,
    })
    view:show()
    return view
end

--- AppToggle:apps()
--- Method
--- 当前应用列表（只读）。
function obj:apps()
    return manager.list()
end

--- AppToggle:bindApp(app)
--- Method
--- 编程式添加/更新应用（不经管理页）。
--- @param app table {name=, bundle_id=, mods=, key=, ...}
--- @return id|nil, err|nil
function obj:bindApp(app)
    local result, err = manager.upsert(app)
    if result then
        obj.logger.f("已绑定「%s」%s+%s", result.app.name,
            table.concat(result.app.mods, "+"), result.app.key)
    end
    return result and result.id or nil, err
end

return obj

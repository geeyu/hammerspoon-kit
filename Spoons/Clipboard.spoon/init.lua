--- === Clipboard ===
---
--- 剪贴板历史管理包（纯原生，仅内嵌 Vue3 前端，本地离线）。
--- 架构分层：
---   init.lua     装配层（公共 API / 热键 / 模块协调）
---   internal/config.lua   配置单点
---   internal/store.lua    数据访问层（SQLite 参数绑定查询 + 图片 data URI）
---   internal/watcher.lua  数据模型 + 监听（缓存、去重、提升、每日清理）
---   internal/panel.lua    表现层（Vue3 webview + 结构化消息桥接）
---   internal/paste.lua    剪贴板操作（写回/粘贴）
---
--- 说明：前端不生成 SQL，只发结构化消息 {type, params}；
---       Lua 负责参数绑定查询、粘贴动作、生命周期管理。
---
--- 使用：
---   local ch = hs.loadSpoon("Clipboard")
---   ch:start()
---
--- 快捷键：Ctrl+V 呼出；面板内输入即搜索，↑↓ 选，Enter 粘贴，Esc 关
--- ============================================================

local obj = {}

obj.name = "Clipboard"
obj.version = "5.1.0"            -- 包名 ClipboardHistory → Clipboard（与路由前缀 /clipboard/* 一致）
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
local watcher = loadMod("watcher.lua")
local panel   = loadMod("panel.lua")
local paste   = loadMod("paste.lua")
local api     = loadMod("api.lua")

obj.config = config
obj.logger = hs.logger.new("Clipboard", "info")
obj.hotkeyToggle = nil  -- 热键对象（对齐 Seal 模式：new + enable 分离）

--- 选中条目的动作链：提升 + 写回 + 隐藏
--- 背景：writeBack 写回系统剪贴板会触发 watcher 捕获，若不加抑制会把“写回”
---      误当作新复制再次入库（导致复制一份/重复）。故写回前先抑制下一次捕获；
---      hash 去重（watcher._push → store.findByText）做第二道保险。
--- 顺序：先 promote（同步落库）再 hide——hide 触发的刷新能拿到置顶后的排序，
---      面板下次打开即见条目在顶部，选择框跟随置顶。
--- 注意：entry 是面板 confirm 后用 watcher.get 查出的行 {id,text,created}。
local function onPick(entry)
    if not entry then return end
    -- 抑制：写回剪贴板不等于“新复制”，不要触发重新入库
    watcher.suspendNextCapture()
    -- 提升到顶：该行 update created 置顶，不新增；复制次数 +1（写回剪贴板算一次复制）
    if entry.id then
        watcher.promote(entry.id)
        watcher.bumpCount(entry.id)
    end
    -- 仅写回系统剪贴板，不自动触发粘贴（粘贴由用户手动 Cmd+V）
    paste.writeBack(entry)
    -- 最后隐藏面板：隐藏时静默刷新，此刻置顶已同步落库
    panel.hide()
end

--- 绑定/重绑呼出热键（settings 保存后调用，立即生效）
local function rebindHotkey()
    if obj.hotkeyToggle then
        pcall(function() obj.hotkeyToggle:disable() end)
        obj.hotkeyToggle = nil
    end
    obj.hotkeyToggle = hs.hotkey.new(config.hotkey_show[1], config.hotkey_show[2], function()
        if panel.visible() then
            panel.hide()
        else
            panel.show()
        end
    end)
    obj.hotkeyToggle:enable()
end

--- Clipboard:show()
--- Method
--- 呼出面板（供 Launcher 卡片/CLI 调用；未 start 时懒初始化面板）。
function obj:show()
    if not panel.ready() then
        panel.setup(config)
        obj.logger.i("Clipboard 面板懒初始化（外部呼出）")
    end
    panel.show()
    return self
end

--- Clipboard:hide()
--- Method
--- 隐藏面板。
function obj:hide()
    panel.hide()
    return self
end

--- Clipboard:start()
--- Method
--- 启动：监听 + 持久化 + 绑定呼出热键。
--- Returns:
---  * Clipboard 对象
function obj:start()
    watcher.setup(config)
    watcher.start()
    obj.watcher = watcher          -- 暴露业务入口（供 panel/调试用）
    -- 数据变更（入库/删除）时刷新前端缓存，避免漏数据
    watcher.onChange = function()
        panel.onDataChanged()
    end
    -- 注册 HTTP API 路由到共享 server，并挂前端静态文件到 /<pkg>/view
    -- 前端目录规范：views/pages/<page>/（对齐 core/hsutil/template/tool.spoon）
    api.setup(watcher, onPick, panel.hide, spoonPath .. "views", config.pkg, config, function(settings)
        -- 配置保存后：热键变更立即重绑（watcher 的条数/天数/图片开关走 config 引用，自动生效）
        if settings and settings.hotkey_show then
            rebindHotkey()
            obj.logger.f("热键已更新: %s+%s", table.concat(settings.hotkey_show[1], "+"), settings.hotkey_show[2])
        end
        -- 面板尺寸变更立即应用（webview resize，下次呼出即新尺寸）
        if settings and settings.panel then
            panel.applySettings(settings.panel)
            obj.logger.f("面板尺寸已更新: %s%% x %s%% @ %s%%",
                math.floor((settings.panel.widthRatio or 0.52) * 100),
                math.floor((settings.panel.heightRatio or 0.62) * 100),
                math.floor((settings.panel.yRatio or 0.22) * 100))
        end
    end)
    panel.setup(config)

    -- 全局热键（toggle：可见时关闭，隐藏时呼出）
    rebindHotkey()

    obj.logger.f("Clipboard 已启动（Ctrl+V 呼出，数据 %s）", config.data_dir)
    return self
end

--- Clipboard:stop()
--- Method
--- 停止监听并隐藏面板。
function obj:stop()
    if self.hotkeyToggle then self.hotkeyToggle:disable() end
    watcher.stop()
    panel.teardown()
    return self
end

--- Clipboard:history()
--- Method
--- 返回当前历史列表（只读）。
function obj:history()
    return watcher.all()
end

--- Clipboard:pull()
--- Method
--- 手动刷新（重新采集当前剪贴板 + 从库重载）。
function obj:pull()
    watcher.captureCurrent()
    watcher.reload()
    return self
end

return obj

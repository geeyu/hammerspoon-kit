--- === QuantumWindow ===
---
--- 一套窗口管理快捷键组合包（分屏 / 铺满 / 居中 / Space 移动 / 跨屏移动）。
--- 全部基于 Hammerspoon 内置 API，无第三方 spoon 依赖。
---
--- 下载/安装：将本 QuantumWindow.spoon 目录放入 ~/.hammerspoon/Spoons/
--- 然后在 init.lua 中：
---   hs.loadSpoon("QuantumWindow"):bindHotkeys()   -- 使用默认快捷键（defaultHotkeys）
---   或 hs.loadSpoon("QuantumWindow"):bindHotkeys(customMapping)
---
--- 默认快捷键一览：
---   left_half/right_half/top_half/bottom_half : Ctrl+Opt+Cmd+方向键
---   space_left/space_right                     : Ctrl+Cmd+左右（相邻 Space）
---   screen_north/screen_south                  : Ctrl+Cmd+上下（跨屏移动）
---   toggleFullscreen                           : Ctrl+Opt+Cmd+M（当前 Space 铺满，可还原）
---   centerAbsolute                             : Ctrl+Opt+Cmd+C（居中 + 绝对尺寸）
--- ===

local obj = {}

-- 注意：不要对 obj 做 setmetatable(obj, obj) 自引用 ——
-- 会与 Hammerspoon 的 spoon 装载机制(_G.spoon 表的 __index 链)冲突，
-- 触发 "__index chain too long; possible loop"。
-- 所有方法均作为普通字段直接写入 obj，冒号调用即可，无需 __index。

-- 元数据
obj.name = "QuantumWindow"
obj.version = "1.0.0"
obj.author = "geeyu"
obj.homepage = "https://github.com/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- 日志器
obj.logger = hs.logger.new("QuantumWindow")

-- 找到本 spoon 所在目录（用于 dofile 内部子模块）
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local spoonPath = script_path()

-- 加载内部子模块
local internal = spoonPath .. "internal"
local config    = dofile(internal .. "/config.lua")
local window    = dofile(internal .. "/window.lua")
local split     = dofile(internal .. "/split.lua")
local spaces    = dofile(internal .. "/spaces.lua")
local fullscreen= dofile(internal .. "/fullscreen.lua")
local center    = dofile(internal .. "/center.lua")
local notify    = dofile(internal .. "/notify.lua")

-- 注入 window 工具到依赖它的子模块
spaces.setup(window)
center.setup(window)

-- 公开配置（可在 bindHotkeys 前修改）
obj.config = config

--- QuantumWindow.defaultHotkeys
--- Variable
--- 一组默认快捷键。可通过 bindHotkeys(customMapping) 覆盖。
obj.defaultHotkeys = {
    left_half        = config.split.hotkeys.left_half,
    right_half       = config.split.hotkeys.right_half,
    top_half         = config.split.hotkeys.top_half,
    bottom_half      = config.split.hotkeys.bottom_half,
    space_left       = config.spaces.hotkeys.space_left,
    space_right      = config.spaces.hotkeys.space_right,
    screen_north     = config.spaces.hotkeys.screen_north,
    screen_south     = config.spaces.hotkeys.screen_south,
    toggleFullscreen = config.fullscreen.hotkey,
    centerAbsolute   = config.center.hotkey,
}

-- 已绑定的热键表句柄（用于重新 bind 时清理）
local boundHotkeys = {}

--- QuantumWindow:leftHalf() / :rightHalf() / :topHalf() / :bottomHalf()
--- Method
--- 让聚焦窗口铺到对应半屏，并显示 HUD 提示。
--- Returns:
---  * QuantumWindow 对象
function obj:leftHalf()   local m=self.defaultHotkeys.left_half;  local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  左半屏", function() split.operate(hs.window.focusedWindow(), "left_half") end) return self end
function obj:rightHalf()  local m=self.defaultHotkeys.right_half; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  右半屏", function() split.operate(hs.window.focusedWindow(), "right_half") end) return self end
function obj:topHalf()    local m=self.defaultHotkeys.top_half;  local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  上半屏", function() split.operate(hs.window.focusedWindow(), "top_half") end) return self end
function obj:bottomHalf() local m=self.defaultHotkeys.bottom_half; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  下半屏", function() split.operate(hs.window.focusedWindow(), "bottom_half") end) return self end

--- QuantumWindow:spaceLeft() / :spaceRight()
--- Method
--- 把聚焦窗口移到上/下一个 Space。
function obj:spaceLeft()  local m=self.defaultHotkeys.space_left;  local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  上一个 Space", function() spaces.moveAdjacent(hs.window.focusedWindow(), -1) end) return self end
function obj:spaceRight() local m=self.defaultHotkeys.space_right; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  下一个 Space", function() spaces.moveAdjacent(hs.window.focusedWindow(), 1) end) return self end

--- QuantumWindow:screenNorth() / :screenSouth()
--- Method
--- 把聚焦窗口移到上/下方显示器。
function obj:screenNorth() local m=self.defaultHotkeys.screen_north; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  上方屏幕", function() spaces.moveScreen(hs.window.focusedWindow(), "north") end) return self end
function obj:screenSouth() local m=self.defaultHotkeys.screen_south; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  下方屏幕", function() spaces.moveScreen(hs.window.focusedWindow(), "south") end) return self end

--- QuantumWindow:toggleFill()
--- Method
--- 当前 Space 内铺满（可还原），显示 HUD。
function obj:toggleFill() local m=self.defaultHotkeys.toggleFullscreen; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  铺满", function() fullscreen.toggle(hs.window.focusedWindow()) end) return self end

--- QuantumWindow:centerOnScreen()
--- Method
--- 居中 + 绝对尺寸，显示 HUD。
function obj:centerOnScreen() local m=self.defaultHotkeys.centerAbsolute; local k=notify.keyLabel(m and m[1], m and m[2])
    notify.with(k.."  居中", function() center.operate(hs.window.focusedWindow(), self.config.center) end) return self end

--- QuantumWindow:bindHotkeys(mapping)
--- Method
--- 绑定快捷键。
--- Parameters:
---  * mapping - 可选的 table。键为动作名（见 defaultHotkeys），值为 {mods, key}。省略时使用 defaultHotkeys。
--- Returns:
---  * QuantumWindow 对象
function obj:bindHotkeys(mapping)
    mapping = mapping or self.defaultHotkeys

    -- 清理旧绑定
    for _, hk in pairs(boundHotkeys) do
        if hk then hk:delete() end
    end
    boundHotkeys = {}

    local function bind(name, mods_key, fn, actionLabel)
        if not mods_key then return end
        if actionLabel then
            local _fn = fn
            -- HUD 显示「按键 + 动作」，如 ⌃⌥⌘→ 右半屏
            fn = function()
                local keys = notify.keyLabel(mods_key[1], mods_key[2]) or ""
                notify.with(keys .. "  " .. actionLabel, _fn)
            end
        end
        local hk = hs.hotkey.bindSpec(mods_key, fn)
        if not hk then
            -- 绑定失败（组合被系统或其他应用占用）静默吞掉会让人以为功能失效，显式告警
            self.logger:ef("热键 %s 绑定失败（可能被系统或其他应用占用）",
                table.concat(mods_key[1], "+") .. "+" .. tostring(mods_key[2]))
        end
        boundHotkeys[name] = hk
    end

    -- 分屏（带 HUD 命令提示）
    bind("left_half", mapping.left_half, function() split.operate(hs.window.focusedWindow(), "left_half") end, "左半屏")
    bind("right_half", mapping.right_half, function() split.operate(hs.window.focusedWindow(), "right_half") end, "右半屏")
    bind("top_half", mapping.top_half, function() split.operate(hs.window.focusedWindow(), "top_half") end, "上半屏")
    bind("bottom_half", mapping.bottom_half, function() split.operate(hs.window.focusedWindow(), "bottom_half") end, "下半屏")

    -- Space / 跨屏
    bind("space_left", mapping.space_left, function() spaces.moveAdjacent(hs.window.focusedWindow(), -1) end, "上一个 Space")
    bind("space_right", mapping.space_right, function() spaces.moveAdjacent(hs.window.focusedWindow(), 1) end, "下一个 Space")
    bind("screen_north", mapping.screen_north, function() spaces.moveScreen(hs.window.focusedWindow(), "north") end, "上方屏幕")
    bind("screen_south", mapping.screen_south, function() spaces.moveScreen(hs.window.focusedWindow(), "south") end, "下方屏幕")

    -- 铺满 / 居中
    bind("toggleFullscreen", mapping.toggleFullscreen, function() fullscreen.toggle(hs.window.focusedWindow()) end, "铺满")
    bind("centerAbsolute", mapping.centerAbsolute, function() center.operate(hs.window.focusedWindow(), self.config.center) end, "居中")

    self.logger:i("快捷键已绑定")
    return self
end

--- QuantumWindow:start()
--- Method
--- 便捷启动：绑定默认快捷键 + 挂配置 API（每动作 启用 + 热键，改动即保存）。
--- Returns:
---  * QuantumWindow 对象
local ACTION_FILE = os.getenv("HOME") .. "/.hammerspoon/data/QuantumWindow/settings.json"

function obj:start()
    -- 配置 API（launcher 配置页；热键录制吞键 guard）
    local apiMod = dofile(internal .. "/api.lua")
    local actionsMod = dofile(internal .. "/actions.lua")
    -- 加载持久化覆盖（settings.json：每动作 enabled + hotkey）
    self._actions = actionsMod.load(ACTION_FILE)
    apiMod.setup(config, spoonPath .. "views", {
        getState = function() return { actions = self._actions } end,
        onSaveActions = function(raw)
            local clean = actionsMod.sanitize(config, raw)
            actionsMod.save(ACTION_FILE, clean)
            self._actions = clean
            self:bindHotkeys(actionsMod.buildMapping(config, clean))
        end,
    })
    return self:bindHotkeys(actionsMod.buildMapping(config, self._actions))
end

--- QuantumWindow:stop()
--- Method
--- 解除所有已绑定的快捷键。
--- Returns:
---  * QuantumWindow 对象
function obj:stop()
    for _, hk in pairs(boundHotkeys) do
        if hk then hk:delete() end
    end
    boundHotkeys = {}
    return self
end

return obj

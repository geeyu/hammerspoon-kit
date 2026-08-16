--- QuantumWindow.internal.config
--- 所有可调参数集中于此；可通过 spoon 暴露的 config 修改。
local config = {}

-- 半屏分屏（纯原生 unitrect）
config.split = {
    hotkeys = {
        left_half   = { { "ctrl", "alt", "cmd" }, "Left"  },
        right_half  = { { "ctrl", "alt", "cmd" }, "Right" },
        top_half    = { { "ctrl", "alt", "cmd" }, "Up"    },
        bottom_half = { { "ctrl", "alt", "cmd" }, "Down"  },
    },
}

-- Space / 多显示器移动
-- 注意：space_left/right 不用 ctrl+cmd+Left/Right——那是 macOS 系统默认的
-- 「Move left/right a space」（调度中心快捷键 79/81，默认启用），冲突时系统抢先、热键无效。
config.spaces = {
    hotkeys = {
        space_left  = { { "ctrl", "cmd", "shift" }, "Left"  },
        space_right = { { "ctrl", "cmd", "shift" }, "Right" },
        screen_north = { { "ctrl", "cmd" }, "Up"   },
        screen_south = { { "ctrl", "cmd" }, "Down" },
    },
}

-- 铺满/最大化（当前 Space 内铺满，非全屏空间）
config.fullscreen = {
    hotkey = { { "ctrl", "alt", "cmd" }, "M" },
}

-- 居中 + 绝对尺寸
config.center = {
    hotkey = { { "ctrl", "alt", "cmd" }, "C" },
    width  = 800,
    height = 600,
    raise  = true,
}

-- 配置页动作清单（数组顺序 = 页面展示顺序；key 与绑定动作名一致）
config.action_order = {
    { key = "left_half",        group = "split",      label = "左半屏",      desc = "窗口贴到左半屏" },
    { key = "right_half",       group = "split",      label = "右半屏",      desc = "窗口贴到右半屏" },
    { key = "top_half",         group = "split",      label = "上半屏",      desc = "窗口贴到上半屏" },
    { key = "bottom_half",      group = "split",      label = "下半屏",      desc = "窗口贴到下半屏" },
    { key = "space_left",       group = "spaces",     label = "上一个 Space", desc = "窗口移到上一个 Space（macOS 15+ 系统限制，暂不可用）" },
    { key = "space_right",      group = "spaces",     label = "下一个 Space", desc = "窗口移到下一个 Space（macOS 15+ 系统限制，暂不可用）" },
    { key = "screen_north",     group = "spaces",     label = "上方屏幕",    desc = "窗口移到上方显示器" },
    { key = "screen_south",     group = "spaces",     label = "下方屏幕",    desc = "窗口移到下方显示器" },
    { key = "toggleFullscreen", group = "fullscreen", label = "铺满窗口",    desc = "当前 Space 内铺满，可还原" },
    { key = "centerAbsolute",   group = "center",     label = "居中窗口",    desc = "居中并调整到绝对尺寸" },
}

--- 动作 → 默认热键（从上方分组结构取值；未知动作返回 nil）
function config.defaultHotkeyFor(key)
    for _, a in ipairs(config.action_order or {}) do
        if a.key == key then
            local g = config[a.group]
            if not g then return nil end
            if a.group == "fullscreen" or a.group == "center" then return g.hotkey end
            return g.hotkeys and g.hotkeys[key]
        end
    end
    return nil
end

--- 热键字符串双向转换：hs.hotkey {mods, key} ↔ "ctrl+alt+cmd+left"
--- @param hk table|nil { { "ctrl", "alt", "cmd" }, "Left" }
--- @return string 如 "ctrl+alt+cmd+Left"；非法输入返回 ""
function config.hotkeyToString(hk)
    if type(hk) ~= "table" or type(hk[1]) ~= "table" or type(hk[2]) ~= "string" then return "" end
    return table.concat(hk[1], "+") .. "+" .. hk[2]
end

--- @param s string "ctrl+alt+cmd+left" / "ctrl+cmd+f5"
--- @return table|nil { { "ctrl", "alt", "cmd" }, "Left" }；非法返回 nil
function config.parseHotkeyString(s)
    if type(s) ~= "string" then return nil end
    local parts = {}
    for p in s:gmatch("[^+]+") do parts[#parts + 1] = p end
    if #parts < 2 then return nil end
    local key = table.remove(parts)
    key = key:sub(1, 1):upper() .. key:sub(2)   -- left→Left、f5→F5、m→M
    return { parts, key }
end

return config

--- QuantumWindow.internal.notify
--- 统一的"HUD 命令提示"工具。
--- 在执行命令前，于屏幕中央弹出一个带毛玻璃/圆角的标签，短暂显示命令名，
--- 确认按键生效、提升操作手感。类似常见窗口管理工具的 HUD 提示。
local notify = {}

-- 样式配置
local DEFAULT_STYLE = {
    strokeColor = hs.drawing.color.white,
    strokeWidth = 2,
    fillColor = { alpha = 0.75, red = 0.1, green = 0.1, blue = 0.1 },
    textColor = hs.drawing.color.white,
    textSize = 32,
    radius = 8,
    textFont = "Helvetica Neue",
}

-- 显示时长（秒）
local DURATION = 0.6

-- 是否启用 HUD（可在外层 config 关闭）
notify.enabled = true

--- notify.show(label)
--- 在屏幕中央显示一条命令提示。
--- @param label string  命令名，如 "左半屏"、"铺满"
function notify.show(label)
    if not notify.enabled then return end
    if not label or label == "" then return end
    hs.alert.show(label, {
        atScreenEdge = 0,          -- 0 = 居中
        fillColor = DEFAULT_STYLE.fillColor,
        strokeColor = DEFAULT_STYLE.strokeColor,
        strokeWidth = DEFAULT_STYLE.strokeWidth,
        textColor = DEFAULT_STYLE.textColor,
        textSize = DEFAULT_STYLE.textSize,
        textFont = DEFAULT_STYLE.textFont,
        radius = DEFAULT_STYLE.radius,
        fadeInDuration = 0.05,
        fadeOutDuration = 0.2,
    }, DURATION)
end

--- notify.keyLabel(mods, key)
--- 把 Hammerspoon 修饰键/按键转换为可读符号，用于 HUD 显示按键组合。
--- 如 { 'ctrl','alt','cmd' } + '→' -> '⌃⌥⌘→'
--- @param mods table|string  修饰键
--- @param key string  按键
--- @return string
function notify.keyLabel(mods, key)
    local map = {
        ctrl = "⌃", control = "⌃",
        alt = "⌥", option = "⌥",
        cmd = "⌘", command = "⌘",
        shift = "⇧",
    }
    local prefix = ""
    if type(mods) == "table" then
        for _, m in ipairs(mods) do
            prefix = prefix .. (map[m] or m)
        end
    elseif type(mods) == "string" then
        prefix = map[mods] or mods
    end
    local keymap = {
        space = "Space", Left = "←", Right = "→", Up = "↑", Down = "↓",
        tab = "⇥", ["return"] = "⏎", returnKey = "⏎",
    }
    local k = keymap[key] or key
    return prefix .. k
end

--- notify.with(label, fn)
--- 先显示提示，再执行 fn，并返回 fn 的结果。
--- 若 fn 返回 (false, reason)，则 HUD 追加显示失败原因，便于排查。
--- @param label string  命令名，如 "左半屏"、"铺满"
--- @param fn function  返回 boolean|nil, 可选失败原因
--- @return ... fn 的返回值
function notify.with(label, fn)
    if not fn then notify.show(label) return end
    -- 先显示命令名
    notify.show(label)
    -- 执行并收集结果
    local ok, res, reason = pcall(fn)
    if not ok then
        -- fn 抛错：显示错误
        notify.show(label .. "\n⚠ " .. tostring(res))
        return nil, res
    end
    -- fn 返回 (false, reason)：显示失败原因
    if res == false and reason then
        notify.show(tostring(reason))
    end
    return res, reason
end

return notify

-- ===== config_test.lua：动作清单 / 热键字符串双向转换 / 默认热键查找 =====
local config = dofile(spoonDir .. "/internal/config.lua")

-- 动作清单：10 个、key 唯一、group 都能取到默认热键
check("action_order 有 10 个动作", #config.action_order == 10,
    "got " .. tostring(#config.action_order))
local seen = {}
local allOk = true
for _, a in ipairs(config.action_order) do
    if seen[a.key] then allOk = false end
    seen[a.key] = true
    if not config.defaultHotkeyFor(a.key) then allOk = false end
end
check("动作 key 唯一且全部有默认热键", allOk)

-- 关键动作齐全（分屏 4 + 空间 4 + 铺满 + 居中）
local keys = {}
for _, a in ipairs(config.action_order) do keys[a.key] = true end
local expectKeys = { "left_half", "right_half", "top_half", "bottom_half",
    "space_left", "space_right", "screen_north", "screen_south",
    "toggleFullscreen", "centerAbsolute" }
local allKey = true
for _, k in ipairs(expectKeys) do if not keys[k] then allKey = false end end
check("10 个动作 key 与绑定动作一致", allKey)

-- 默认热键取值
local lh = config.defaultHotkeyFor("left_half")
expectEqual("left_half 默认热键 mods", table.concat(lh[1], "+"), "ctrl+alt+cmd")
expectEqual("left_half 默认热键 key", lh[2], "Left")
local fs = config.defaultHotkeyFor("toggleFullscreen")
expectEqual("toggleFullscreen 默认热键 key", fs[2], "M")
local cs = config.defaultHotkeyFor("centerAbsolute")
expectEqual("centerAbsolute 默认热键 key", cs[2], "C")
expectNil("未知动作返回 nil", config.defaultHotkeyFor("nope"))

-- hotkeyToString
expectEqual("toString 标准组合", config.hotkeyToString({ { "ctrl", "alt", "cmd" }, "Left" }), "ctrl+alt+cmd+Left")
expectEqual("toString 单修饰", config.hotkeyToString({ { "cmd" }, "M" }), "cmd+M")
expectEqual("toString 非法输入", config.hotkeyToString(nil), "")
expectEqual("toString 非法输入2", config.hotkeyToString({ "x" }), "")

-- parseHotkeyString：round trip
local p = config.parseHotkeyString("ctrl+alt+cmd+left")
check("parse 三段 mods", p and table.concat(p[1], "+") == "ctrl+alt+cmd", p and table.concat(p[1], "+"))
expectEqual("parse 主键首字母大写", p and p[2], "Left")
local p2 = config.parseHotkeyString("ctrl+cmd+f5")
expectEqual("parse F5 原样", p2 and p2[2], "F5")
local p3 = config.parseHotkeyString("ctrl+shift+v")
expectEqual("parse 单字符大写", p3 and p3[2], "V")
expectNil("parse 无修饰键", config.parseHotkeyString("left"))
expectNil("parse 空串", config.parseHotkeyString(""))
expectNil("parse 非字符串", config.parseHotkeyString(123))

-- round trip：toString ∘ parse = 原值
local orig = { { "ctrl", "alt", "cmd" }, "Left" }
local rt = config.parseHotkeyString(config.hotkeyToString(orig))
check("round trip 一致", rt and rt[2] == orig[2] and table.concat(rt[1], "+") == table.concat(orig[1], "+"))

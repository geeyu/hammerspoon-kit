-- ===== actions_test.lua：绑定映射 / 覆盖清洗 / 页面行展开 / settings.json 读写 =====
local config = dofile(spoonDir .. "/internal/config.lua")
local actions = dofile(spoonDir .. "/internal/actions.lua")

-- 字符串键表计数（# 只对数组有效）
local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- ── buildMapping ──
local m = actions.buildMapping(config, nil)
check("无覆盖 → 10 个动作全绑", count(m) == 10, "got " .. tostring(count(m)))
expectEqual("默认 left_half 热键", table.concat(m.left_half[1], "+") .. "+" .. m.left_half[2], "ctrl+alt+cmd+Left")

local m2 = actions.buildMapping(config, { left_half = { enabled = false, hotkey = "" } })
check("禁用 → 不绑", m2.left_half == nil)
check("禁用一个不影响其他", count(m2) == 9, "got " .. tostring(count(m2)))

local m3 = actions.buildMapping(config, { right_half = { enabled = true, hotkey = "ctrl+shift+r" } })
expectEqual("覆盖热键生效", table.concat(m3.right_half[1], "+") .. "+" .. m3.right_half[2], "ctrl+shift+R")

local m4 = actions.buildMapping(config, { top_half = { enabled = true, hotkey = "" } })
check("空热键（用户清空）→ 不绑", m4.top_half == nil)

local m5 = actions.buildMapping(config, { bottom_half = { enabled = true, hotkey = "garbage" } })
check("非法热键串 → 不绑（不猜默认）", m5.bottom_half == nil)

local m6 = actions.buildMapping(config, { unknown_action = { enabled = true, hotkey = "cmd+x" } })
check("未知动作忽略", m6.unknown_action == nil and count(m6) == 10)

-- ── sanitize ──
local s = actions.sanitize(config, { left_half = { enabled = false, hotkey = "cmd+1" },
                                     unknown = { enabled = true, hotkey = "cmd+2" },
                                     centerAbsolute = { hotkey = 42 } })
check("未知动作被丢弃", s.unknown == nil)
check("enabled 规范化", s.left_half.enabled == false)
check("hotkey 保留", s.left_half.hotkey == "cmd+1")
check("hotkey 非字符串 → 空串", s.centerAbsolute.hotkey == "")
check("仅保留已知动作", count(s) == 2)
expectEqual("sanitize 非表 → 空", count(actions.sanitize(config, nil)), 0)

-- ── flatten ──
local f = actions.flatten(config, nil)
check("flatten 10 行", #f == 10)
expectEqual("flatten 顺序第一是 left_half", f[1].key, "left_half")
expectEqual("flatten 最后是 centerAbsolute", f[10].key, "centerAbsolute")
expectEqual("flatten 默认启用", f[1].enabled, true)
expectEqual("flatten 默认热键字符串", f[1].hotkey, "ctrl+alt+cmd+Left")
expectEqual("flatten 标签", f[5].label, "上一个 Space")

local f2 = actions.flatten(config, { left_half = { enabled = false, hotkey = "cmd+shift+h" },
                                     space_left = { enabled = true, hotkey = "" },
                                     right_half = { enabled = true, hotkey = "garbage" } })
expectEqual("覆盖 enabled", f2[1].enabled, false)
expectEqual("覆盖热键", f2[1].hotkey, "cmd+shift+H")
expectEqual("清空覆盖热键 → 显示空", f2[5].hotkey, "")
expectEqual("非法串 → 显示空（与不绑一致）", f2[2].hotkey, "")

-- ── load / save round trip（临时文件）──
local tmp = os.getenv("TMPDIR") or "/tmp"
local file = tmp .. "qw_settings_test.json"
os.remove(file)
expectEqual("无文件 → 空覆盖", count(actions.load(file)), 0)

check("save 成功", actions.save(file, { left_half = { enabled = false, hotkey = "cmd+1" } }))
local loaded = actions.load(file)
check("load 读回", loaded.left_half and loaded.left_half.enabled == false and loaded.left_half.hotkey == "cmd+1")

-- 损坏文件 → 空覆盖
local bad = tmp .. "qw_settings_bad.json"
local fh = io.open(bad, "w")
fh:write("not json{{{")
fh:close()
expectEqual("损坏文件 → 空覆盖", count(actions.load(bad)), 0)

os.remove(file)
os.remove(bad)

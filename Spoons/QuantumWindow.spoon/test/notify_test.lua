--- notify HUD 工具纯函数测试（keyLabel 边界；不触 hs.alert 显示）
local notify = dofile(spoonDir .. "/internal/notify.lua")

print("[notify]")

-- keyLabel 正常组合
expectEqual("三键组合", notify.keyLabel({ "ctrl", "alt", "cmd" }, "Left"), "⌃⌥⌘←")
expectEqual("单修饰键", notify.keyLabel({ "alt" }, "space"), "⌥Space")
expectEqual("方向键映射", notify.keyLabel({ "ctrl" }, "Down"), "⌃↓")
expectEqual("未知键原样", notify.keyLabel({ "cmd" }, "F5"), "⌘F5")
expectEqual("字符串 mods", notify.keyLabel("ctrl", "Up"), "⌃↑")

-- nil 防御：动作未绑定/直接调用公开方法（:leftHalf() 等）时不得崩溃
expectEqual("nil key 返回纯修饰键", notify.keyLabel({ "ctrl" }, nil), "⌃")
expectEqual("全 nil 返回空串", notify.keyLabel(nil, nil), "")

-- keyLabel 空表 mods
expectEqual("空 mods", notify.keyLabel({}, "Left"), "←")

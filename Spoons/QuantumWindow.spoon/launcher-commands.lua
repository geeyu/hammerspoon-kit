-- QuantumWindow 命令提供者（Launcher 自动发现）
-- 主页「窗口管理」卡片 → 配置展示页（模块开关 + 热键清单）。
return {
    name = "quantumwindow",
    cards = {
        ["窗口管理"] = {
            description = "窗口布局与快捷热键",
            kind = "page",
            icon = "🪟",
            url = "settings",
        },
    },
    pages = {
        { name = "窗口管理", icon = "🪟", config = "settings" },
    },
}

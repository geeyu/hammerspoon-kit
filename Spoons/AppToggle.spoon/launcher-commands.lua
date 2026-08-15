-- AppToggle 命令提供者（Launcher 自动发现）
-- 主页「应用显隐」卡片 → 管理页（应用列表 + 热键录制 + 布局管理）。
return {
    name = "apptoggle",
    cards = {
        ["应用显隐"] = {
            description = "一键显隐应用（全局热键 + 布局锁定）",
            kind = "page",
            icon = "🔄",
            url = "apps",
        },
    },
    pages = {
        { name = "应用显隐", icon = "🔄", config = "apps" },
    },
}

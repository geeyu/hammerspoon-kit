-- StayAwake 命令提供者（Launcher 自动发现）
-- pages：统一页面注册表（仅 config，无 search → Tab 注入无效并提示）。
return {
    name = "stayawake",
    cards = {
        ["防睡眠"] = {
            description = "防睡眠控制面板（子页面）",
            kind = "page",
            icon = "🌙",
            url = "control",
        },
    },
    pages = {
        { name = "防睡眠", icon = "🌙", config = "control" },
    },
}

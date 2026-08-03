-- Clipboard 命令提供者（Launcher 自动发现：Spoons/*.spoon/launcher-commands.lua）
-- pages：统一页面注册表（config 配置页 / search 搜索页，支持目录名简写推断）。
--   简写规则：值不含 "/" 时按 /<name>/view/pages/<值>/index.html 推断。
--   search 页支持 Tab 注入（launcher 搜索框输入 postMessage 转发，?embed=1 时隐藏自带输入框）。
return {
    name = "clipboard",
    cards = {
        ["剪贴板"] = {
            description = "剪贴板设置（历史记录可用 Ctrl+V 呼出）",
            kind = "page",
            icon = "📋",
            url = "settings",
        },
    },
    pages = {
        { name = "剪贴板", icon = "📋", config = "settings", search = "history" },
    },
}

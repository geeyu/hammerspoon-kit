-- BingDaily 命令提供者（Launcher 自动发现）
-- 主页「Bing 壁纸」卡片 → 设置页；search 页支持 Tab 注入（浏览最近壁纸直接切换）。
return {
    name = "bingdaily",
    cards = {
        ["Bing 壁纸"] = {
            description = "Bing 每日壁纸（轮询 + 一键执行 + 历史切换）",
            kind = "page",
            icon = "🖼️",
            url = "settings",
        },
    },
    pages = {
        { name = "Bing 壁纸", icon = "🖼️", config = "settings", search = "search" },
    },
}

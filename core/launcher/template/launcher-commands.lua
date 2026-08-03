-- ============================================================
-- Launcher 命令提供者模板（Spoon 接入协议）
-- 放到你的 spoon 根目录，命名为 launcher-commands.lua，重启 Hammerspoon 即被自动发现。
-- 协议文档：core/launcher/README.md「Spoon 接入协议」
-- 运行时注册（免重启）：launcher:registerCommands("你的spoon名", manifest)
-- ============================================================
return {
    name = "myspoon",   -- 提供者名（日志/去重用）

    -- ===== 功能卡片（常驻卡片墙「快捷命令」Tab）=====
    cards = {
        -- 1) shell：后台执行（argv 内 ${query} 替换，卡片墙场景无 query）
        -- ["打开项目"] = {
        --     description = "在 Finder 打开项目目录",
        --     kind = "shell",
        --     exec = { "/usr/bin/open", { "$HOME/Projects" } },
        -- },

        -- 2) openurl：默认浏览器打开
        -- ["搜索官网"] = {
        --     description = "打开官网搜索",
        --     kind = "openurl",
        --     url = "https://example.com/search?q=${query}",
        -- },

        -- 3) screen：截屏
        -- ["选区截图"] = {
        --     description = "交互式选区截屏",
        --     kind = "screen",
        --     sub = { kind = "interactive", postUI = true },
        -- },

        -- 4) page：面板内 iframe 打开自家 view（子页面协议）
        --    自家 init.lua 需 app:static("/myspoon/view", spoonPath .. "views")
        --    子页面内可调 window.parent.closePage() 关闭
        -- ["控制面板"] = {
        --     description = "打开控制面板",
        --     kind = "page",
        --     url = "/myspoon/view/index.html",
        -- },

        -- 5) runFunction + config schema（配置表单驱动）
        -- ["定时任务"] = {
        --     description = "执行 Lua 闭包（表单配置）",
        --     kind = "runFunction",
        --     fn = function(cfg)
        --         local spoon = hs.loadSpoon("MySpoon")
        --         if spoon then spoon:doIt(cfg.mode, cfg.duration) end
        --     end,
        --     config = {
        --         { key = "mode", label = "模式", type = "select",
        --           options = { { label = "A", value = "a" }, { label = "B", value = "b" } } },
        --         { key = "duration", label = "时长（分钟）", type = "text" },
        --     },
        -- },
    },

    -- ===== 关键词命令（输入 keyword 触发）=====
    -- custom_commands = {
    --     ["示例命令"] = {
    --         keyword = "demo",   -- 输入 "demo ..." 即命中（置顶不独占）
    --         title = "示例命令",
    --         kind = "shell",
    --         exec = { "/bin/echo", { "hello ${query}" } },
    --     },
    -- },

    -- ===== 书签/动作（裸搜索 + add/del 关键词维护）=====
    -- user_actions = {
    --     ["官网"] = { url = "https://example.com" },
    --     ["通知"] = { fn = function() hs.alert.show("hi") end, description = "弹提示" },
    -- },
}

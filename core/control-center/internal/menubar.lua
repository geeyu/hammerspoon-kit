--- ControlCenter.internal.menubar
--- 菜单栏控制中心:hs.menubar 常驻按钮(🛠),每次打开菜单时基于 sources 最新扫描结果
--- 重建菜单(数据新鲜),点击配置入口经 panel 单例打开对应配置页。
---
--- 菜单结构:
---   ① 「打开控制中心」   → panel.showAggregate()(切回聚合配置页)
---   ② 分隔线
---   ③ 各 Spoon 配置入口:
---      * provider.pages 非空     → 子菜单:每配置页一项(name+icon,点击 panel.open(configUrl))
---      * 无 pages 但有 page 卡   → 单项(打开该卡 url)
---      * 两者皆无               → 禁用项(provider 名)
---   ④ 分隔线(仅在有配置入口时)
---   ⑤ 「重载 Hammerspoon」     → hs.reload()
---   ⑥ 「退出 Hammerspoon」     → hs.exit()
---
--- 零侵入:只新增本文件;不写 launcher cfg/registry、不挂路由、不改任何既有文件。
--- 降级:扫描失败/为空时菜单仍保留 ①⑤⑥ 三项,绝不抛错阻塞启动。
---
--- 依赖:同目录 sources.lua / panel.lua(与 launcher 内部模块一致,按路径 dofile 加载);
---       装配(init.lua)或测试可经 setup() 注入同一实例(注意:panel 是惰性单例,
---       若先 dofile panel.lua 并 panel.setup({aggregateUrl=...}),应经 menubar.setup
---       ({panel=...}) 注入该实例,避免双实例导致「打开控制中心」目标缺失)。
local menubar = {}

local HSUtil = require("core.hsutil")
local logger = HSUtil.log.new("ControlCenter.menubar")

-- ============================================================
-- 状态(依赖注入点;setup 可覆盖)
-- ============================================================
local sources = nil      -- 数据源(scan/get)
local panel = nil        -- 配置面板(open/showAggregate)
local bar = nil          -- hs.menubar 单例
local barTitle = "🛠"    -- 菜单栏标题(emoji)
local barTooltip = "ControlCenter 控制中心"

--- 定位本文件所在目录(source 形如 core/control-center/internal/menubar.lua)
local function moduleDir()
    local src = debug.getinfo(1, "S").source:sub(2)
    return src:match("^(.*[/\\])") or ""
end

--- 加载依赖(默认 dofile 同目录兄弟模块;失败时降级为 no-op 替身,绝不抛错)
local function ensureDeps()
    if not sources or not panel then
        local dir = moduleDir()
        if not sources then
            local ok, mod = pcall(dofile, dir .. "sources.lua")
            if ok and type(mod) == "table" then
                sources = mod
            else
                logger.ef("加载 sources.lua 失败,配置入口将不可用: %s", tostring(mod))
                sources = { scan = function() return {} end, get = function() return {} end }
            end
        end
        if not panel then
            local ok, mod = pcall(dofile, dir .. "panel.lua")
            if ok and type(mod) == "table" then
                panel = mod
            else
                logger.ef("加载 panel.lua 失败,配置面板将不可用: %s", tostring(mod))
                panel = { open = function() return false end, showAggregate = function() return false end }
            end
        end
    end
end

-- ============================================================
-- 菜单构建
-- ============================================================

--- 构建一个提供者的菜单项列表(0..n 项)
--- 显示名:卡片中文名(cards[1].key)优先 → pages[1].name → 内部 name 兑底。
--- 规则:有 pages 且仅 1 个配置页 → 单项直达(不套子菜单);多个配置页 → 子菜单;
---       无 pages 且 kind="page" 卡片 → 每卡单项;两者皆无 → 禁用项。
--- @param p table provider { name, icon?, cards?, pages? }
--- @return table 菜单项列表(可能为 {禁用项} 或空)
local function providerItems(p)
    -- 显示名:卡片中文名优先(如「防睡眠」),不用内部英文名
    local display = tostring(p.name or "?")
    if type(p.cards) == "table" and #p.cards > 0 and type(p.cards[1].key) == "string"
        and p.cards[1].key ~= "" then
        display = p.cards[1].key
    elseif type(p.pages) == "table" and #p.pages > 0 and type(p.pages[1].name) == "string"
        and p.pages[1].name ~= "" then
        display = p.pages[1].name
    end
    local icon = (type(p.icon) == "string" and p.icon ~= "") and (p.icon .. " ") or ""
    local title = icon .. display

    -- ① 有 pages:收集配置页
    if type(p.pages) == "table" and #p.pages > 0 then
        local sub = {}
        for _, pg in ipairs(p.pages) do
            if type(pg.configUrl) == "string" then
                local pgIcon = (type(pg.icon) == "string" and pg.icon ~= "") and (pg.icon .. " ") or ""
                sub[#sub + 1] = {
                    title = pgIcon .. tostring(pg.name or "配置"),
                    fn = function() panel.open(pg.configUrl) end,
                }
            end
        end
        if #sub == 1 then
            -- 单个配置页:直接展示「组件名 → 配置」单项,不套子菜单(少一级点击)
            return { { title = title, fn = sub[1].fn } }
        end
        if #sub > 1 then
            return { { title = title, menu = sub } }
        end
        -- pages 全是搜索页(无配置页):降级为禁用项
        return { { title = title, disabled = true } }
    end

    -- ② 无 pages:kind="page" 卡片建单项(打开该卡 url)
    local items = {}
    if type(p.cards) == "table" then
        for _, c in ipairs(p.cards) do
            if c.kind == "page" and type(c.url) == "string" then
                local cIcon = (type(c.icon) == "string" and c.icon ~= "") and (c.icon .. " ") or ""
                items[#items + 1] = {
                    title = cIcon .. tostring(c.key or "配置"),
                    fn = function() panel.open(c.url) end,
                }
            end
        end
    end
    if #items > 0 then return items end

    -- ③ 两者皆无:禁用项(provider 显示名)
    return { { title = title, disabled = true } }
end

--- ControlCenter.menubar.buildMenu()
--- 构建完整菜单(每次打开菜单时调用;setMenu 传函数实现重建)。
--- ① 打开控制中心 ② 分隔线 ③ 各 Spoon 配置入口 ④ 分隔线 ⑤ 重载 ⑥ 退出。
--- 每次重新扫描(数据新鲜);扫描失败时回退缓存,仍失败则降级为固定三项,绝不抛错。
--- @return table hs.menubar 菜单表
function menubar.buildMenu()
    ensureDeps()

    local menu = {
        { title = "打开控制中心", fn = function() panel.showAggregate() end },
        { title = "-" },
    }

    -- 每次打开菜单都重新扫描(数据新鲜);异常时回退缓存
    local ok, list = pcall(function() return sources.scan() end)
    if not ok or type(list) ~= "table" then
        logger.w("sources.scan() 失败,回退缓存")
        local okC, cached = pcall(function() return sources.get() end)
        list = (okC and type(cached) == "table") and cached or {}
    end
    local added = 0
    for _, p in ipairs(list) do
        local okP, items = pcall(providerItems, p)
        if okP and type(items) == "table" then
            for _, it in ipairs(items) do
                menu[#menu + 1] = it
                added = added + 1
            end
        end
    end

    -- ④ 分隔线:仅在有配置入口时加(空时避免双分隔线)
    if added > 0 then
        menu[#menu + 1] = { title = "-" }
    end
    menu[#menu + 1] = { title = "重载 Hammerspoon", fn = function() hs.reload() end }
    -- 注:HS 1.1.1 已移除 hs.exit(),直接调用会报 "attempt to call a nil value"。
    -- 兼容:有 hs.exit 则用之(旧版本/单测 mock),否则经 application:kill 退出。
    menu[#menu + 1] = { title = "退出 Hammerspoon", fn = function()
        if type(hs.exit) == "function" then
            hs.exit()
        else
            local app = hs.application.get("Hammerspoon")
            if app then app:kill() end
        end
    end }
    return menu
end

-- ============================================================
-- 对外 API
-- ============================================================

--- ControlCenter.menubar.setup(opts)
--- 可选初始化(须在 start() 前调用):
---   opts.sources / opts.panel   依赖注入(默认 dofile 同目录兄弟模块;装配时注入同一
---                               实例可避免 panel 双实例,保证「打开控制中心」可达)
---   opts.aggregateUrl           聚合配置页 URL(透传给内部 panel.setup)
---   opts.title                  菜单栏标题,默认 "🛠"
---   opts.tooltip                悬浮提示,默认 "ControlCenter 控制中心"
function menubar.setup(opts)
    opts = opts or {}
    if opts.sources then sources = opts.sources end
    if opts.panel then panel = opts.panel end
    if type(opts.title) == "string" and opts.title ~= "" then barTitle = opts.title end
    if type(opts.tooltip) == "string" then barTooltip = opts.tooltip end
    if opts.aggregateUrl then
        ensureDeps()
        if type(panel.setup) == "function" then
            pcall(function() panel.setup({ aggregateUrl = opts.aggregateUrl }) end)
        end
    end
    return menubar
end

--- ControlCenter.menubar.start()
--- 创建常驻菜单栏按钮(幂等):hs.menubar.new(true) 全局菜单栏;
--- setMenu 传函数 → 每次打开菜单时重新调用 buildMenu,数据新鲜。
function menubar.start()
    ensureDeps()
    if bar then return menubar end
    -- autosaveName 让 macOS 记住图标位置(跨 reload/重启恢复),避免每次重载
    -- 都新建到菜单栏最右端;名称须唯一(同 app 内多个菜单栏图标不能重名)。
    bar = hs.menubar.new(true, "ControlCenter")
    if not bar then
        logger.e("创建菜单栏按钮失败")
        return menubar
    end
    bar:setTitle(barTitle)
    if barTooltip ~= "" then bar:setTooltip(barTooltip) end
    bar:setMenu(function()
        return menubar.buildMenu()
    end)
    logger.f("ControlCenter 菜单栏就绪(%s)", barTitle)
    return menubar
end

--- ControlCenter.menubar.stop()
--- 移除菜单栏按钮(幂等;模块 stop 时调用)
function menubar.stop()
    if bar then
        pcall(function() bar:remove() end)
        bar = nil
    end
    return menubar
end

return menubar

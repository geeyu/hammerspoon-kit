--- Launcher.internal.registry
--- 源注册、候选聚合、关键词解析、runner 注入。替代 Seal 的 loader/chooser/commands。
local registry = {}

local HSUtil = require("core.hsutil")
local logger = HSUtil.log.new("Launcher.registry")
local pathUtil = HSUtil.path

-- =====================================================================
-- manifest 校验（Spoon 接入协议，见 README「Spoon 接入协议」）
-- 规则：非法条目警告 + 跳过，绝不抛出；只校验 provider 输入，
--       用户直接写 config.cards 的宽松行为（未知 kind 默认 shell）不变。
-- =====================================================================

local CARD_KINDS = {
    shell = true, openurl = true, screen = true, page = true, runFunction = true,
}
local SCHEMA_TYPES = { select = true, radio = true, checkbox = true, text = true }

--- 校验一个配置字段；非法返回 nil + 原因
--- （声明在 sanitizeCard 之前：sanitizeCard 的 config 逐字段校验引用它）
local function sanitizeField(f)
    if type(f) ~= "table" then return nil, "非 table" end
    if type(f.key) ~= "string" or f.key == "" then return nil, "缺 key" end
    if type(f.label) ~= "string" or f.label == "" then return nil, "缺 label" end
    local t = f.type
    if not t or not SCHEMA_TYPES[t] then return nil, "未知 type=" .. tostring(t) end
    if (t == "select" or t == "radio") and type(f.options) ~= "table" then
        return nil, "select/radio 需要 options"
    end
    return f
end

--- 页面 URL 简写推断：值不含 "/" 视为页面目录名 → /<modName>/view/pages/<v>/index.html
--- 以 "/" 开头视为完整 URL 原样使用
local function resolvePageUrl(modName, v)
    if type(v) ~= "string" or v == "" then return nil end
    if v:find("/", 1, true) then return v end
    return "/" .. modName .. "/view/pages/" .. v .. "/index.html"
end

--- 校验一张卡片；非法返回 nil + 原因，合法返回归一化后的卡片（原样）
local function sanitizeCard(key, c, modName)
    if type(c) ~= "table" then return nil, "非 table" end
    local kind = c.kind
    if not kind or not CARD_KINDS[kind] then
        return nil, "未知 kind=" .. tostring(kind)
    end
    if kind == "shell" then
        if type(c.exec) ~= "table" or type(c.exec[1]) ~= "string" or c.exec[1] == "" then
            return nil, "kind=shell 需要 exec={cmd,{argv}}"
        end
    elseif kind == "openurl" or kind == "page" then
        if type(c.url) ~= "string" or c.url == "" then
            return nil, "kind=" .. kind .. " 需要 url"
        end
        -- 页面卡 url 简写推断（不含 "/" 视为页面目录名）；拷贝避免改原协议表
        local resolved = resolvePageUrl(modName, c.url)
        if not resolved then return nil, "url 推断失败" end
        local copy = {}
        for kk, vv in pairs(c) do copy[kk] = vv end
        copy.url = resolved
        c = copy
    elseif kind == "runFunction" then
        if type(c.fn) ~= "function" then
            return nil, "kind=runFunction 需要 fn"
        end
    end
    -- config schema 逐字段校验：非法字段丢弃（警告），合法保留
    if type(c.config) == "table" then
        local kept = {}
        for _, f in ipairs(c.config) do
            local okField, reason = sanitizeField(f)
            if okField then kept[#kept + 1] = okField
            else logger.wf("提供者卡片 %s 的配置字段被丢弃: %s", key, reason) end
        end
        c.config = kept
    end
    return c
end

--- 校验一条 custom 命令；非法返回 nil + 原因
local function sanitizeCustom(key, c)
    if type(c) ~= "table" then return nil, "非 table" end
    if type(c.keyword) ~= "string" or c.keyword == "" then
        return nil, "缺 keyword"
    end
    if c.kind ~= "shell" or type(c.exec) ~= "table" or type(c.exec[1]) ~= "string" or c.exec[1] == "" then
        return nil, "kind 需为 shell 且 exec={cmd,{argv}}"
    end
    return c
end

--- 校验一条 user action；非法返回 nil + 原因
local function sanitizeAction(key, v)
    if type(v) ~= "table" then return nil, "非 table" end
    if type(v.url) ~= "string" and type(v.fn) ~= "function" then
        return nil, "需要 url 或 fn 至少其一"
    end
    return v
end

--- 校验一个组件配置页；非法返回 nil + 原因
--- { name=显示名, icon=emoji?, url=/<pkg>/view/... }
local function sanitizeConfigPage(v)
    if type(v) ~= "table" then return nil, "非 table" end
    if type(v.name) ~= "string" or v.name == "" then return nil, "缺 name" end
    if type(v.url) ~= "string" or v.url == "" then return nil, "缺 url" end
    return v
end

--- pages 条目：{ name, icon?, config?|search? }（config/search 支持简写）
--- @return table|nil, string page 表（configUrl/searchUrl 已推断）或错误原因
local function sanitizePage(v, modName)
    if type(v) ~= "table" then return nil, "非 table" end
    if type(v.name) ~= "string" or v.name == "" then return nil, "缺 name" end
    local out = { name = v.name, icon = v.icon }
    local configV = v.config or v.url   -- url 为 config_pages 老字段，视为 config
    if configV then
        local url = resolvePageUrl(modName, configV)
        if not url then return nil, "config 非法" end
        out.configUrl = url
    end
    if v.search then
        local url = resolvePageUrl(modName, v.search)
        if not url then return nil, "search 非法" end
        out.searchUrl = url
    end
    if not out.configUrl and not out.searchUrl then return nil, "config/search 至少一个" end
    return out
end

local cfg
local sources_lib
local runner_lib
local store_lib        -- SQLite 存储单实例（setup 创建，stop 对称关闭；勿重复声明）

-- 定位本文件目录（load 内部模块）
local dir = (function()
    local s = debug.getinfo(1, "S").source:sub(2)
    return s:match("(.*[/\\])") or ""
end)()

--- 自定义命令源：把 config.custom_commands 变成"源"
--- @return table 源对象（name="custom", keywords=custom_commands 的 keyword 表）
function registry.customSource()
    if not cfg or not cfg.custom_commands then
        return { name = "custom", keywords = {}, build = function() return {} end, keywords_meta = {} }
    end
    local keywords = {}
    local meta = {}
    for k, cmd in pairs(cfg.custom_commands) do
        if cmd.keyword then
            keywords[cmd.keyword] = true
            meta[cmd.keyword] = cmd
        end
    end
    return {
        name = "custom",
        keywords = keywords,
        keywords_meta = meta,
        -- 关键词模式：调用 buildCustom(kw, rest)
        build = function() return {} end,
    }
end

--- 供 registry.query 关键词模式调用：生成 custom 命令候选
--- @param text string 关键词剩余部分
function registry.buildCustom(kw, text)
    local src = registry.customSource()
    local cmd = src.keywords_meta[kw]
    if not cmd then return {} end
    local arg = text
    if arg == ".*" then arg = "" end
    return {{
        text = cmd.title or kw, subText = (cmd.kind or "shell") .. " command · " .. (cmd.exec[1] or ""),
        plugin = "custom", type = "custom", cmd = cmd, arg = arg,
    }}
end

--- 初始化：加载 sources + runner，注入依赖，激活各源
--- @param config table 配置单点
function registry.setup(config)
    cfg = config
    sources_lib = dofile(dir .. "sources.lua")
    runner_lib  = dofile(dir .. "runner.lua")

    -- 打开 SQLite 存储（应用启动频次 + 动态书签），单实例注入给 apps/useractions 源
    store_lib = dofile(dir .. "store.lua")
    pcall(store_lib.open, cfg and cfg.data_dir)
    if sources_lib and sources_lib.apps then
        sources_lib.apps.statsStore = store_lib
    end
    if sources_lib and sources_lib.useractions then
        sources_lib.useractions.store = store_lib
    end

    -- 注入 runner 依赖
    runner_lib.showPostUI = sources_lib.screencapture.showPostUI == true
    runner_lib.onAddURL = function(row) sources_lib.useractions:saveAdd(row) end
    runner_lib.onDelURL = function(row) sources_lib.useractions:saveDel(row) end
    runner_lib.onCustom = nil -- 默认走 runner 内置 hs.task 分支
    runner_lib.bumpAppLaunch = function(path)
        if sources_lib.apps and sources_lib.apps.bumpLaunch then
            sources_lib.apps:bumpLaunch(path)
        end
    end

    -- 命令发现：扫描 Spoons/*.spoon/ 与 core/*/ 下的 launcher-commands.lua
    pcall(registry.scanCommandDirs, {
        pathUtil.join(hs.configdir, "Spoons"),
        pathUtil.join(hs.configdir, "core"),
    })

    -- 激活各源（apps 起 spotlight 等）
    for _, s in pairs(sources_lib) do
        if type(s) == "table" and s.name and s.activate and not s._activated then
            pcall(function() s.activate(s, cfg) end)
            s._activated = true
        end
    end
    return registry
end

--- 源是否启用
local function enabled(name)
    if not cfg or not cfg.enabled_sources then return true end
    for _, n in ipairs(cfg.enabled_sources) do
        if n == name then return true end
    end
    return false
end

--- 开启的源列表（内置 + custom 追加）
local function activeSources()
    local list = {}
    for _, s in pairs(sources_lib) do
        if type(s) == "table" and s.name and enabled(s.name) then
            list[#list + 1] = s
        end
    end
    if enabled("custom") then list[#list + 1] = registry.customSource() end
    return list
end

--- 关键词模式：返回 {source, keyword, rest}
local function parseKeyword(text)
    local firstWord = text:match("^(%S+)")
    if not firstWord then return nil end
    for _, s in ipairs(activeSources()) do
        if s.keywords and s.keywords[firstWord] then
            local rest = text:sub(#firstWord + 1):gsub("^%s+", "")
            return s, firstWord, rest
        end
    end
    return nil
end

--- 聚合候选
--- @param text string 用户输入
--- @return table { rows={...}, keyword=string|nil, source=string|nil, home=boolean|nil }
function registry.query(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local result = { rows = {}, keyword = nil }
    -- 新查询：清空旧行存储（重新分配 id）
    registry._store = {}
    registry._counter = 1

    local function addRows(rows, section)
        if not rows then return end
        for _, r in ipairs(rows) do
            r.id = registry._counter
            registry._counter = registry._counter + 1
            if section then r.section = section end
            -- pages 注入：候选名匹配协议注册页时携带 searchUrl（Tab 注入依据）
            if not r.searchUrl and cfg and cfg.pages then
                local pg = cfg.pages[r.text]
                if pg and pg.searchUrl then r.searchUrl = pg.searchUrl end
            end
            registry._store[r.id] = r
            result.rows[#result.rows + 1] = r
        end
    end

    -- 空输入：分组返回「最近使用」应用 + 「快捷命令」卡片
    if text == "" then
        if sources_lib and sources_lib.apps and sources_lib.apps.homeApps then
            -- 常用应用（运行中 + 按频次），供搜索场景参考（已无独立视图，保留数据）
            local ok, rows = pcall(sources_lib.apps.homeApps, sources_lib.apps, 24)
            if ok then addRows(rows, "最近使用") end
        end
        if sources_lib and sources_lib.cards and sources_lib.cards.build then
            local ok2, rows2 = pcall(sources_lib.cards.build, sources_lib.cards, "")
            if ok2 then addRows(rows2, "快捷命令") else logger.ef("快捷命令构建异常: %s", tostring(rows2)) end
        end
        result.home = true
        return result
    end

    -- 1) 关键词模式（置顶不独占）：命中先加关键词结果
    local src, kw, kwrest = parseKeyword(text)
    if src then
        result.keyword = kw
        result.source = src.name
        local fn = type(src[kw]) == "function" and src[kw]
            or (type(src.keywords[kw]) == "function" and src.keywords[kw] or nil)
        if not fn and src.name == "custom" then
            fn = function(self_, t) return registry.buildCustom(kw, t) end
        end
        if type(fn) == "function" then
            local ok, rows = pcall(fn, src, kwrest)
            if ok then addRows(rows) else logger.ef("关键词 %s 生成候选异常: %s", kw, tostring(rows)) end
        end
    end

    -- 1.5) pages 匹配：协议注册的应用名命中 → 候选（cardPage + searchUrl，Tab 注入依据）
    if cfg and cfg.pages then
        local needle = text:lower()
        for pname, pg in pairs(cfg.pages) do
            if pname:lower():find(needle, 1, true) then
                addRows({
                    { text = pname,
                      subText = pg.searchUrl and "应用搜索（Tab 注入）" or "组件配置页",
                      icon = pg.icon or "🧩",
                      plugin = "cards",
                      type = "cardPage",
                      pageUrl = pg.configUrl,
                      searchUrl = pg.searchUrl },
                }, "应用")
            end
        end
    end

    -- 2) 裸搜索：所有源（关键词模式时跳过已用源，避免重复）
    for _, s in ipairs(activeSources()) do
        if (not src or s.name ~= src.name) and type(s.build) == "function" then
            local ok, rows = pcall(s.build, s, text)
            if ok then addRows(rows) else logger.ef("源 %s 裸搜索异常: %s", s.name, tostring(rows)) end
        end
    end
    return result
end

--- 启用源/关键词列表
function registry.getSourcesMeta()
    local list = {}
    for _, s in ipairs(activeSources()) do
        local ks = {}
        if s.keywords then for k in pairs(s.keywords) do ks[#ks + 1] = k end end
        list[#list + 1] = { name = s.name, keywords = ks }
    end
    return list
end

--- 执行一条候选。前端只发 row.id，这里从行存储重浄原始行（含 fn/cmd）。
--- @param row table 前端发来的 { id=number, ... }
function registry.runRow(row)
    if not runner_lib then return false end
    local id = row and row.id
    local raw = id and registry._store and registry._store[id]
    if not raw then
        logger.wf("run: 找不到行存储中的 row id=%s", tostring(id))
        return false
    end
    -- overrides：命令详情变体参数（如 cardScreen 的 subKind），浅拷贝覆盖，不污染行存储
    if row.overrides and type(row.overrides) == "table" then
        local r2 = {}
        for k, v in pairs(raw) do r2[k] = v end
        for k, v in pairs(row.overrides) do r2[k] = v end
        raw = r2
    end
    -- 二级操作：前端选中应用后 Tab 展开，选择具体 action 时携带 action 字段。
    -- 这里把 action 映射到对应 type，再交给 runner 执行（raw 本身含 path/pid/bundleID）。
    local action = row.action
    if action and raw.type == "launchOrFocus" then
        local map = {
            open = "openApp", focus = "focusApp", kill = "kill",
            newWindow = "newWindow", reveal = "reveal",
        }
        local t2 = map[action]
        if t2 then
            local r2 = {}
            for k, v in pairs(raw) do r2[k] = v end
            r2.type = t2
            return runner_lib.run(r2)
        end
    end
    return runner_lib.run(raw)
end

--- 启动/停止运行期资源（apps spotlight）
function registry.start()
    for _, s in pairs(sources_lib) do
        if type(s) == "table" and s.name and s.activate and not s._activated then
            pcall(function() s.activate(s, cfg) end)
            s._activated = true
        end
    end
end
function registry.stop()
    for _, s in pairs(sources_lib) do
        if type(s) == "table" and s.teardown then pcall(function() s.teardown(s) end) end
        if type(s) == "table" then s._activated = false end
    end
    -- 对称清理：关闭 SQLite（原实现只开不关）
    if store_lib then pcall(function() store_lib.close() end) end
end

--- 合并一份 manifest（校验 + merge + 实时刷新源）。静态扫描与运行时注册共用。
--- @param name string 提供者名
--- @param mod table manifest（cards/custom_commands/user_actions）
--- @return table { merged = number, skipped = number }
function registry._mergeManifest(name, mod)
    local stat = { merged = 0, skipped = 0 }
    if type(mod) ~= "table" then
        logger.wf("命令提供者 %s 返回非 table 类型: %s", name, type(mod))
        stat.skipped = 1
        return stat
    end
    -- cards
    if type(mod.cards) == "table" then
        for k, v in pairs(mod.cards) do
            local ok, reason = sanitizeCard(k, v, mod.name or name)
            if ok then
                -- 仅写 cfg.cards：activate 已把 sources_lib.cards.cards 绑定到 cfg.cards 同表，
                -- 运行时注册实时可见；静态扫描路径下写源表会被 activate 重绑定丢弃（死代码）
                cfg.cards[k] = ok
                stat.merged = stat.merged + 1
            else
                logger.wf("提供者 %s 的卡片 %s 被跳过: %s", name, k, reason)
                stat.skipped = stat.skipped + 1
            end
        end
    end
    -- custom_commands
    if type(mod.custom_commands) == "table" then
        for k, v in pairs(mod.custom_commands) do
            local ok, reason = sanitizeCustom(k, v)
            if ok then
                cfg.custom_commands[k] = ok
                stat.merged = stat.merged + 1
            else
                logger.wf("提供者 %s 的 custom 命令 %s 被跳过: %s", name, k, reason)
                stat.skipped = stat.skipped + 1
            end
        end
    end
    -- user_actions
    if type(mod.user_actions) == "table" then
        for k, v in pairs(mod.user_actions) do
            local ok, reason = sanitizeAction(k, v)
            if ok then
                cfg.user_actions[k] = ok
                if sources_lib and sources_lib.useractions then
                    sources_lib.useractions:registerAction(k, ok)
                end
                stat.merged = stat.merged + 1
            else
                logger.wf("提供者 %s 的动作 %s 被跳过: %s", name, k, reason)
                stat.skipped = stat.skipped + 1
            end
        end
    end
    -- pages（统一页面注册表：config 配置页 + search 搜索页，支持简写推断）
    if type(mod.pages) == "table" then
        cfg.pages = cfg.pages or {}
        for _, v in ipairs(mod.pages) do
            local page, reason = sanitizePage(v, mod.name or name)
            if page then
                cfg.pages[page.name] = page
                -- 兼容老消费者：configUrl 同步进 config_pages
                if page.configUrl then
                    cfg.config_pages = cfg.config_pages or {}
                    cfg.config_pages[page.name] = { name = page.name, icon = page.icon, url = page.configUrl }
                end
                stat.merged = stat.merged + 1
            else
                logger.wf("提供者 %s 的页面条目被跳过: %s", name, reason)
                stat.skipped = stat.skipped + 1
            end
        end
    end
    -- config_pages（老字段，兼容：仅当 pages 未声明该 name 的 config 时补充）
    if type(mod.config_pages) == "table" then
        cfg.pages = cfg.pages or {}
        for _, v in ipairs(mod.config_pages) do
            local page, reason = sanitizePage(v, mod.name or name)
            if page then
                local existing = cfg.pages[page.name]
                if existing and existing.configUrl then
                    stat.skipped = stat.skipped + 1   -- pages 已声明，跳过
                else
                    if existing then existing.configUrl = page.configUrl
                    else cfg.pages[page.name] = page end
                    cfg.config_pages = cfg.config_pages or {}
                    cfg.config_pages[page.name] = { name = page.name, icon = page.icon, url = page.configUrl }
                    stat.merged = stat.merged + 1
                end
            else
                logger.wf("提供者 %s 的配置页被跳过: %s", name, reason)
                stat.skipped = stat.skipped + 1
            end
        end
    end
    logger.f("命令提供者已加载: %s（合并 %d，跳过 %d）", name, stat.merged, stat.skipped)
    return stat
end

--- 运行时注册命令提供者（Spoon 接入协议：launcher:registerCommands）
--- @param name string 提供者名
--- @param manifest table manifest（cards/custom_commands/user_actions）
function registry.registerProvider(name, manifest)
    registry._mergeManifest(name, manifest)
end

--- 命令发现：加载外部命令提供者文件并 merge 到配置
--- @param providers table { [名字] = 文件路径 }（测试可注入；运行时由 setup 扫描目录生成）
function registry.scanCommandProviders(providers)
    for name, path in pairs(providers or {}) do
        -- pcall(dofile, ...) 可能返回多值，用表收集避免只取第一个
        local results = { pcall(dofile, path) }
        local ok = table.remove(results, 1)
        local mod = results[1]
        if not ok then
            logger.ef("命令提供者 %s 加载失败: %s", name, tostring(mod))
        else
            registry._mergeManifest(name, mod)
        end
    end
end

--- 扫描目录下的命令提供者文件
function registry.scanCommandDirs(dirs)
    local providers = {}
    for _, dir in ipairs(dirs or {}) do
        -- dir 形如 ~/.hammerspoon/Spoons：遍历一级子目录（*.spoon），
        -- 检查每个子目录下的 launcher-commands.lua。
        -- 注意：hs.fs.dir 返回 (iteratorFn, dirUserdata) 两个值，dirUserdata 是 for 循环的
        -- state——必须直接 for entry in hs.fs.dir(dir)（不能先 pcall 取第一个返回值再迭代，
        -- 那会丢掉 state 导致 “directory metatable expected, got nil”，且被外层 pcall 吞掉）。
        local ok = pcall(function()
            for entry in hs.fs.dir(dir) do
                if entry:sub(1,1) ~= "." then
                    local sub = pathUtil.join(dir, entry)
                    local okDir, mode = pcall(hs.fs.attributes, sub, "mode")
                    local isDir = okDir and mode == "directory"
                    if isDir then
                        local cmdFile = pathUtil.join(sub, "launcher-commands.lua")
                        local okFile, fmode = pcall(hs.fs.attributes, cmdFile, "mode")
                        local exists = okFile and fmode ~= nil
                        if exists then
                            providers[entry] = cmdFile
                        end
                    end
                end
            end
        end)
        if not ok then
            logger.wf("scanCommandDirs: 目录扫描失败 %s", tostring(dir))
        end
    end
    registry.scanCommandProviders(providers)
end

return registry

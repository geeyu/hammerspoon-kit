--- Launcher.internal.sources
--- 各内置源（apps/cards/calc/screencapture/urlformats/useractions）。
--- 每个源: { name, keywords, activate(self,cfg), build(self,text)->rows, <kw>(self,text)->rows }
--- 候选 row: { text, subText?, image?, type, plugin?, …type-specific }
local sources = {}

-- =====================================================================
-- apps —— Spotlight 应用/PreferencePane/脚本 搜索 + kill/reveal
-- =====================================================================
sources.apps = {
    name = "apps",
    keywords = { kill = true, reveal = true },
    appCache = {},           -- name -> { path, bundleID, kind }（launchOrFocus 用；icon 懒加载）
    iconCache = {},          -- path -> hs.image（懒缓存）
    running = {},            -- pid -> { name, path, bundleID }（kill/二级 用）

    -- 扫描的应用目录（不用 hs.spotlight，避免首启全盘扫描 + 混入脚本/偏好面板）
    -- 每项 { dir, maxDepth }：递归扫到 maxDepth 层。
    --   * /Applications 等：maxDepth 大，覆盖 Utilities 嵌套应用
    --   * CoreServices：仅顶层 .app（取 Finder 等），不深入巨大的深层树，避免慢
    scanDirs = {
        { dir = "/Applications", maxDepth = 6 },
        { dir = "/System/Applications", maxDepth = 6 },
        { dir = "~/Applications", maxDepth = 6 },
        { dir = "/System/Library/CoreServices", maxDepth = 0 },
    },

    -- 递归扫描：只记 path/bundleID（不在此解码图标，避免全盘扫图标导致首启卡顿）。
    -- 显式 self 参数（点调用 self._scanDir(...)）。
    -- isSystem：目录位于 /System/Library/CoreServices 时标记系统辅助应用（首页默认不优先展示）
    _scanDir = function(self, path, seen, depth, maxDepth, isSystem)
        if depth > maxDepth then return end
        isSystem = isSystem or path:find("/System/Library/CoreServices", 1, true) ~= nil
        for entry in hs.fs.dir(path) do
            if entry:sub(1,1) ~= "." then
                local full = path .. "/" .. entry
                if entry:sub(-4) == ".app" then
                    local base = entry:sub(1, -5)
                    if not seen[base] then
                        seen[base] = true
                        local info = hs.application.infoForBundlePath(full)
                        local bundleID = info and info.CFBundleIdentifier or nil
                        self.appCache[base] = { path = full, bundleID = bundleID, kind = "app", isSystem = isSystem }
                    end
                elseif hs.fs.attributes(full, "mode") == "directory" then
                    self._scanDir(self, full, seen, depth + 1, maxDepth, isSystem)
                end
            end
        end
    end,

    -- 懒加载应用图标（带缓存）
    _iconFor = function(self, path, bundleID)
        if not path then return nil end
        if self.iconCache[path] then return self.iconCache[path] end
        local icon
        local ok, r = pcall(hs.image.iconForFile, path)
        if ok and r then icon = r end
        if not icon and bundleID then
            local ok2, r2 = pcall(hs.image.imageFromAppBundle, bundleID)
            if ok2 then icon = r2 end
        end
        self.iconCache[path] = icon
        return icon
    end,

    activate = function(self)
        local seen = {}
        for _, sd in ipairs(self.scanDirs) do
            -- 展开 `~` 到 HOME；单个目录失败不阻断其它目录
            local path = sd.dir
            if path:sub(1,1) == "~" then
                local home = os.getenv("HOME") or hs.configdir
                path = home .. path:sub(2)
            end
            pcall(self._scanDir, self, path, seen, 0, sd.maxDepth)
        end
        self:_refreshRunning()
        -- 运行中应用变化时刷新 running 标记（不重建 appCache）
        if self.watcher then pcall(function() self.watcher:stop() end) end
        self.watcher = hs.application.watcher.new(function(_, etype, app)
            if (etype == hs.application.watcher.activated
                or etype == hs.application.watcher.launched
                or etype == hs.application.watcher.terminated) then
                self:_refreshRunning()
            end
        end)
        self.watcher:start()
    end,

    -- 刷新运行中应用表（name 小写 -> pid/path/bundleID），供 build 标 Running + kill + 二级
    -- 过滤掉系统后台 agent/daemon（位于 /System/Library 下的 CoreServices/Frameworks 等），
    -- 它们在后台运行但用户无法用卡片启动，避免首页一堆 loginwindow/SystemUIServer 之类噪音。
    _refreshRunning = function(self)
        local run = {}
        for _, app in ipairs(hs.application.runningApplications()) do
            local p = app:path() or ""
            local name = app:name() or ""
            local base = name:gsub("%.app$", "", 1)
            -- 跳过系统库下的后台进程（无用户界面），保留 /Applications 与 /System/Applications 的正常应用
            if p:find("/System/Library/", 1, true) then
                -- 跳过
            elseif name ~= "" then
                run[base:lower()] = { pid = app:pid(), path = p, bundleID = app:bundleID(), name = base }
            end
        end
        self.running = run
        return run
    end,

    -- ── 启动频次统计（SQLite，用于首页卡片墙排序）。
    --     store 由 registry.setup 以单个实例 open 后注入到 self.statsStore（避免多实例重复开库）。
    --     不强缓存：每次查询直接读库（24 应用量级很快），避免跨 bump 读到旧缓存。
    _loadStats = function(self)
        if self.statsStore and self.statsStore.all then
            return self.statsStore.all() or {}
        end
        return {}
    end,
    bumpLaunch = function(self, path)
        if not path or path == "" then return end
        if self.statsStore and self.statsStore.bump then self.statsStore.bump(path) end
    end,

    -- 首页卡片墙：运行中应用优先 + 常用应用（按频次/最近使用排序）
    homeApps = function(self, limit)
        limit = limit or 24
        self:_refreshRunning()
        local stats = self:_loadStats()
        local scored = {}
        local order = {}
        for name, app in pairs(self.appCache) do
            local key = name:lower()
            local r = self.running[key]
            local st = stats[app.path]
            local cnt = st and st.count or 0
            -- 首页只收「运行中」或「有使用频次」的应用；纯系统辅助 agent 且无频次一律排除，避免字母序堆一堆乱七八糟
            local keep = r ~= nil or (cnt > 0 and not app.isSystem)
            if keep then
                -- 排序：运行中 rank=0（最前）；其余按频次大靠前，system 且运行中仍可排最前
                local rank = (r ~= nil) and 0 or (-cnt - (st and st.lastused or 0) / 1e10)
                scored[name] = { rank = rank, app = app, running = r }
                order[#order+1] = name
            end
        end
        table.sort(order, function(a, b)
            if scored[a].rank ~= scored[b].rank then return scored[a].rank < scored[b].rank end
            return a < b
        end)
        -- 如果首页太空（无运行中、无频次），退化展示全部用户应用的前几个，避免一片空白
        if #order == 0 then
            for name, app in pairs(self.appCache) do
                if not app.isSystem then scored[name] = { rank = 0, app = app, running = nil } order[#order+1] = name end
                if #order >= limit then break end
            end
            table.sort(order, function(a, b) return a < b end)
        end
        local rows = {}
        for i = 1, math.min(limit, #order) do
            local name = order[i]
            local e = scored[name]
            local r = e.running
            rows[#rows+1] = {
                text = (r and (name .. " (Running)") or name),
                subText = e.app.path,
                image = self:_iconFor(e.app.path, e.app.bundleID),
                path = e.app.path, pid = r and r.pid or nil,
                bundleID = e.app.bundleID, plugin = "apps",
                type = "launchOrFocus",
            }
        end
        return rows
    end,

    build = function(self, text)
        local rows = {}
        if not text or text == "" then return rows end
        local needle = text:lower()
        self:_refreshRunning()
        for name, app in pairs(self.appCache) do
            if name:lower():find(needle, 1, true) then
                local r = self.running[name:lower()]
                local sub = app.path
                local extra = ""
                local pid
                if r then
                    extra = " (Running)"; pid = r.pid
                end
                rows[#rows + 1] = {
                    text = name .. extra, subText = sub,
                    image = self:_iconFor(app.path, app.bundleID), path = app.path, pid = pid,
                    bundleID = app.bundleID, plugin = "apps",
                    type = "launchOrFocus",
                }
            end
        end
        return rows
    end,

    kill = function(self, text)
        local rows = {}
        local needle = (text or ""):lower()
        for base, r in pairs(self.running) do
            if base:find(needle, 1, true) then
                local app = hs.application.get(r.pid)
                if app and app:mainWindow() then
                    rows[#rows + 1] = {
                        text = "Kill " .. r.name,
                        subText = (r.path or "") .. " PID: " .. r.pid,
                        pid = r.pid, plugin = "apps", type = "kill",
                        image = r.bundleID and hs.image.imageFromAppBundle(r.bundleID) or nil,
                    }
                end
            end
        end
        return rows
    end,

    reveal = function(self, text)
        local rows = {}
        for _, row in ipairs(sources.apps.build(sources.apps, text)) do
            rows[#rows + 1] = {
                text = "Reveal " .. row.text, subText = row.path,
                path = row.path, plugin = "apps", type = "reveal",
                image = row.image,
            }
        end
        return rows
    end,

    teardown = function(self)
        if self.watcher then pcall(function() self.watcher:stop() end); self.watcher = nil end
        self.appCache = {}
        self.iconCache = {}
        self.running = {}
    end,
}

--- 给定选中的应用 row（来自 apps.build），追加其二级操作候选。
--- 前端 Tab 时由 registry/api 调用；返回 actions row 列表。
function sources.apps.actionsFor(appRow)
    local list = {}
    local name = (appRow.text or ""):gsub(" %(Running%)$", "")
    local path = appRow.path
    local pid = appRow.pid
    local bundleID = appRow.bundleID
    local function ac(text, subText, type_, fields)
        local r = { text = text, subText = subText, image = appRow.image, plugin = "apps", type = type_ }
        if fields then for k, v in pairs(fields) do r[k] = v end end
        table.insert(list, r)
    end
    ac("打开 " .. name, path or "", "openApp", { path = path })
    if pid then
        ac("聚焦 " .. name, "Bring to front", "focusApp", { pid = pid })
        ac("退出 " .. name, "kill process", "kill", { pid = pid })
    end
    ac("新建窗口 " .. name, "launch a new instance", "newWindow", { path = path, bundleID = bundleID })
    ac("在 Finder 显示", path or "", "reveal", { path = path })
    return list
end

-- =====================================================================
-- calc —— 算术表达式
-- =====================================================================
sources.calc = {
    name = "calc",
    icon = hs.image.imageFromAppBundle("com.apple.Calculator"),
    build = function(self, text)
        local rows = {}
        if not text or text == "" then return rows end
        local q = text:gsub("[%,%$]", "")
        if q:match("[^%d^%.^%+^%-^/^%*^%^^ ^%(^%)]") == nil then
            local fn = load("return " .. q)
            if type(fn) == "function" then
                local result = fn()
                rows[#rows + 1] = {
                    text = tostring(result), subText = "Copy result to clipboard",
                    image = self.icon, plugin = "calc", type = "copyToClipboard",
                }
            end
        end
        return rows
    end,
}

-- =====================================================================
-- screencapture —— sc 关键词
-- =====================================================================
sources.screencapture = {
    name = "screencapture",
    keywords = { sc = true },
    showPostUI = true,
    _items = {
        { text = "Capture menu",                subText = "Show macOS screen capture menu", type = "screenUI" },
        { text = "Capture Screen",              subText = "Capture the current screen",     type = "screen" },
        { text = "Capture Screen to Clipboard", subText = "Capture screen to clipboard",    type = "screen_clipboard" },
        { text = "Capture Interactive",         subText = "Draw a rectangle to capture",    type = "interactive" },
        { text = "Capture Interactive to Clipboard", subText = "Draw to clipboard",         type = "interactive_clipboard" },
    },
    sc = function(self, text)
        local rows = {}
        for _, item in ipairs(self._items) do
            if item.text:lower():find((text or ""):lower(), 1, true) then
                rows[#rows + 1] = {
                    text = item.text, subText = item.subText,
                    plugin = "screencapture", type = item.type,
                }
            end
        end
        return rows
    end,
}

-- =====================================================================
-- urlformats —— uf 关键词 + URL scheme 裸搜索
-- =====================================================================
sources.urlformats = {
    name = "urlformats",
    keywords = { uf = true },
    providers = {},
    activate = function(self, cfg)
        self.providers = (cfg and cfg.url_providers) or {}
    end,
    uf = function(self, text)
        local rows = {}
        for _, data in pairs(self.providers) do
            -- 把 provider url 里的 %s 作为占位符（转义其它 %）
            local data_url = data.url:gsub("([^%%])%%([^s])", "%1%%%%%2")
            local full = string.format(data_url, text)
            local scheme = full:match("^([^:]+)://")
            rows[#rows + 1] = {
                text = data.name, subText = full, plugin = "urlformats",
                type = "launch", url = full, scheme = scheme,
            }
        end
        return rows
    end,
    build = function(self, text)
        local rows = {}
        local scheme = text and text:match("^([%w%+%.%-]+)://")
        if scheme then
            for _, bundleID in ipairs(hs.urlevent.getAllHandlersForScheme(scheme)) do
                local bi = hs.application.infoForBundleID(bundleID)
                if bi and bi.CFBundleName then
                    rows[#rows + 1] = {
                        text = "Open URI with " .. bi.CFBundleName, subText = text,
                        handler = bundleID, scheme = scheme, url = text,
                        plugin = "urlformats", type = "launch",
                        image = hs.image.imageFromAppBundle(bundleID),
                    }
                end
            end
        end
        return rows
    end,
}

-- =====================================================================
-- useractions —— 书签/静态 action（add/del 关键词 + 裸搜索）
-- =====================================================================
sources.useractions = {
    name = "useractions",
    keywords = { add = true, del = true },
    actions = {},
    stored = {},
    default_icon = hs.image.imageFromName(hs.image.systemImageNames.ActionTemplate),

    activate = function(self, cfg)
        self.actions = (cfg and cfg.user_actions) or {}
        -- 动态书签从 SQLite 读（store 未注入时退化为空，与老 settings 行为一致）
        self.stored = (self.store and self.store.allActions()) or {}
        for _, v in pairs(self.stored) do
            if v.encoded_icon and v.encoded_icon ~= "" then
                v.icon = hs.image.imageFromURL(v.encoded_icon)
            end
        end
        -- 注册每个静态 action 的 keyword（registerAction 复用同一逻辑）
        for k, v in pairs(self.actions) do
            self:registerAction(k, v)
        end
    end,

    -- 注册一个 action 到内存（含 keyword）；activate 与 registry.registerProvider 共用
    registerAction = function(self, name, v)
        self.actions[name] = v
        if v.keyword and not self.keywords[v.keyword] then
            self.keywords[v.keyword] = function(self2, text)
                local arg = text
                if arg == ".*" then arg = "" end
                return {{
                    text = v.keyword .. " " .. arg,
                    subText = v.description or name,
                    image = v.icon, arg = arg, plugin = "useractions",
                    url = v.url, fn = v.fn, type = "invokeKeyword",
                }}
            end
        end
    end,

    -- 合并静态 + 动态书签
    _all = function(self)
        local out = {}
        for k, v in pairs(self.actions) do out[k] = v end
        for k, v in pairs(self.stored) do out[k] = v end
        return out
    end,

    add = function(self, text)
        local url, name = text:match("([^%s]+)%s+(.*)")
        return {{
            text = "add " .. text,
            subText = url and ("New bookmark '" .. name .. "' -> " .. url) or "",
            url = url, name = name, plugin = "useractions", type = "addURL",
        }}
    end,

    del = function(self, text)
        local rows = {}
        for k, v in pairs(self.stored) do
            if k:lower():find((text or ""):lower(), 1, true)
                or (v.url or ""):lower():find((text or ""):lower(), 1, true) then
                rows[#rows + 1] = {
                    text = "delete '" .. k .. "'", subText = v.url,
                    delKey = k, plugin = "useractions", type = "delURL",
                    image = v.icon,
                }
            end
        end
        return rows
    end,

    build = function(self, text)
        local rows = {}
        if not text or text == "" then return rows end
        for action, v in pairs(self:_all()) do
            if action:lower():find(text:lower(), 1, true) then
                local row = { text = action, plugin = "useractions", image = v.icon or self.default_icon }
                if v.description then row.subText = v.description end
                if v.fn then
                    row.type = "runFunction"; row.fn = v.fn
                elseif v.url then
                    row.type = "openURL"; row.url = v.url
                    if v.icon == "favicon" then row.image = self:favIcon(v.url) end
                end
                if row.type then rows[#rows + 1] = row end
            end
        end
        return rows
    end,

    favIcon = function(self, url)
        local q = string.format("http://www.google.com/s2/favicons?sz=64&domain_url=%s",
            hs.http.encodeForQuery(url))
        return hs.image.imageFromURL(q)
    end,

    -- 供 runner/registry 调用：持久化（内存 + SQLite 双写，对齐 Clipboard）
    saveAdd = function(self, row)
        if row.url and row.name then
            self.stored[row.name] = { url = row.url }
            local ico = self:favIcon(row.url)
            local encoded = ico and ico:encodeAsURLString() or nil
            if encoded then self.stored[row.name].encoded_icon = encoded end
            -- 持久化到 SQLite（对齐 Clipboard 的内存 + DB 双写）
            if self.store then
                self.store.upsertAction(row.name, { url = row.url, icon = encoded })
            end
        end
    end,
    saveDel = function(self, row)
        if row.delKey then
            self.stored[row.delKey] = nil
            if self.store then self.store.deleteAction(row.delKey) end
        end
    end,
}

-- =====================================================================
-- cards —— 功能卡片（config.cards 常驻动作，可自建 shell / 开链 / 截屏）
-- =====================================================================
sources.cards = {
    name = "cards",
    icon = hs.image.imageFromName(hs.image.systemImageNames.ActionTemplate),
    cards = {},
    pages = {},        -- 协议注册的应用页（name -> {configUrl, searchUrl}），Tab 注入依据
    activate = function(self, cfg)
        self.cards = (cfg and cfg.cards) or {}
        self.pages = (cfg and cfg.pages) or {}
    end,
    build = function(self, text)
        local rows = {}
        local needle = (text or ""):lower()
        for name, c in pairs(self.cards) do
            if needle == "" or name:lower():find(needle, 1, true)
                or (c.description or ""):lower():find(needle, 1, true) then
                local card = {
                    text = name, subText = c.description or "",
                    plugin = "cards",
                }
                -- 命中协议注册的应用页：附加 searchUrl（前端 Tab 注入依据）
                local page = self.pages and self.pages[name]
                if page and page.searchUrl then card.searchUrl = page.searchUrl end
                -- icon：字符串（emoji）走 icon 字段；hs.image 对象走 image 字段
                if type(c.icon) == "string" and c.icon ~= "" then
                    card.icon = c.icon
                else
                    card.image = c.icon or self.icon
                end
                local kind = c.kind
                if kind == "shell" then
                    card.type = "cardShell"; card.exec = c.exec
                elseif kind == "openurl" then
                    card.type = "cardOpenURL"; card.url = c.url
                elseif kind == "screen" then
                    local sub = c.sub or {}
                    card.type = "cardScreen"; card.subKind = sub.kind or "interactive"; card.postUI = sub.postUI
                elseif kind == "page" then
                    -- 子页面卡片：前端 iframe 打开任意 spoon 的 view（pageUrl 由注册校验保证）
                    card.type = "cardPage"; card.pageUrl = c.url
                elseif kind == "runFunction" then
                    card.type = "runFunction"; card.fn = c.fn; card.config = c.config
                else
                    card.type = "cardShell"; card.exec = c.exec
                end
                rows[#rows + 1] = card
            end
        end
        return rows
    end,
}

return sources

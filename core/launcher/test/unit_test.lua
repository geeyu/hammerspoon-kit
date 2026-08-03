-- Launcher 纯 Lua 单元测试（lua5.4 运行，mock 掉 hs.* 的 IO 部分）
-- 用 -- run:  lua5.4 core/launcher/test/unit_test.lua
-- 覆盖：registry 关键词解析、calc、custom 源、runner 分发调度（不真执行系统命令）

-- =========================================================
-- Mock hs
-- =========================================================
-- 文件系统 mock 数据（scanCommandDirs 用）：目录表 + 文件表，由 hs.fs 的 mock 消费
_mockFS = { dirs = {}, files = {} }

local results = { pass = 0, fail = 0 }
local function check(name, cond, detail)
    if cond then
        print("  [PASS] " .. name); results.pass = results.pass + 1
    else
        print("  [FAIL] " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
        results.fail = results.fail + 1
    end
end

invokedCommands = {}   -- 记录 runner 触发的黑盒副作用（全局，供临时命令文件 fn 访问）

local function mockHSImage()
    return setmetatable({}, { __index = function() return function() return mockHSImage() end end })
end

hs = {
    logger = { new = function() return { i=function()end,w=function()end,e=function()end,f=function()end,wf=function()end,ef=function()end,df=function()end } end },
    configdir = (debug.getinfo(1,"S").source:match("^(.-[/\\])test[/\\]") or "../"),
    fs = {
        displayName = function(p) return p end,
        pathToAbsolute = function(p) return p end,
        -- 模拟 HS 1.1.1：hs.fs.dir 返回 (iteratorFn, dirUserdata) 两个值，
        -- dirUserdata 是 for 循环的 state；迭代器校验 state 参数，缺 state（如被 pcall 丢掉）时报错，
        -- 与真实 HS 行为一致（“directory metatable expected, got nil”）
        dir = function(path)
            local entries = _mockFS.dirs[path] or {}
            local i = 0
            return function(state)
                if not state or state._p ~= path then
                    error("directory metatable expected, got nil")
                end
                i = i + 1
                return entries[i]
            end, { _p = path }
        end,
        attributes = function(path, key)
            if _mockFS.dirs[path] then return "directory" end
            if _mockFS.files[path] then return "file" end
            return nil
        end,
    },
    image = {
        imageFromAppBundle = function() return mockHSImage() end,
        imageFromName = function() return mockHSImage() end,
        iconForFile = function() return mockHSImage() end,
        imageFromURL = function() return mockHSImage() end,
        systemImageNames = { ActionTemplate = "Action" },
    },
    application = {
        enableSpotlightForNameSearches = function() end,
        applicationsForBundleID = function() return {} end,
        runningApplications = function() return {} end,
        get = function() return nil end,
        infoForBundleID = function() return nil end,
        launchOrFocus = function() end,
    },
    spotlight = {
        new = function() local o={}; return setmetatable(o,{__index=function(_,k) return function(...) return o end end}) end,
    },
    urlevent = {
        getAllHandlersForScheme = function() return {} end,
        getDefaultHandler = function() return nil end,
        openURLWithBundle = function() table.insert(invokedCommands,"openURL:"..arg) end,
    },
    pasteboard = { setContents = function(v) table.insert(invokedCommands,"copy:"..tostring(v)) end },
    task = { new = function() return { start = function() end } end },
    hotkey = { new = function() return { enable=function()end, disable=function()end, delete=function()end } end },
    http = { encodeForQuery = function(s) return s end },
    settings = { get = function() return {} end, set = function() end },
    osascript = { applescript = function() end },
    alert = { show = function() end },
    -- SQLite mock（store.lua 加载需要）
    sqlite3 = { open = function() return {
        isopen = function() return true end,
        close = function() end,
        exec = function() end,
        prepare = function() return {
            bind_values = function() end, step = function() end,
            finalize = function() end, nrows = function() return (function() return nil end)() and {} or {} end,
        } end,
    } end },
    loadSpoon = function() return {
        http = { BASE = "http://127.0.0.1:8821", app = {} },
        path = { dataDir = function() return "~/.hammerspoon/data" end, ensureDir = function() end },
        json = { encode=function(v)return require("json") and "" or "" end },
        db = {
            open = function() return {
                isopen = function() return true end, close = function() end,
                exec = function() end, prepare = function() return {
                    bind_values = function() end, step = function() end, finalize = function() end,
                    nrows = function() return {} end,
                } end,
            } end,
            orm = { define = function(def) return {
                bind = function() return _G.__m end, insert = function() return 1 end,
                findById = function() return nil end, query = function() return {}, 0 end,
            } end },
        },
    } end,
}
-- =========================================================
-- SQLite mock（store.lua 需要）：记录 prepare SQL/binds，nrows 返回 mockRows
-- =========================================================
local mockDbLog = {}   -- { {sql=..., binds={...}} }
local mockRows = {}    -- nrows 迭代的数据（测试可预置）

local function mockStmt(sql)
    return {
        bind_values = function(_, ...) table.insert(mockDbLog, { sql = sql, binds = { ... } }) end,
        step = function() end,
        finalize = function() end,
        nrows = function()
            local i = 0
            return function()
                i = i + 1
                return mockRows[i]
            end
        end,
    }
end

local function mockDbHandle()
    return {
        isopen = function() return true end,
        close = function() end,
        exec = function(_, sql) table.insert(mockDbLog, { sql = sql }) end,
        prepare = function(_, sql) return mockStmt(sql) end,
    }
end

-- mock core.hsutil（原 hs.loadSpoon("HSUtil") mock 的替代）
package.loaded["core.hsutil"] = {
    http = { BASE = "http://127.0.0.1:8821", app = {} },
    path = {
        dataDir = function() return "~/.hammerspoon/data" end,
        ensureDir = function() end,
        join = function(a, b) return a .. "/" .. b end,
    },
    json = { encode = function() return "" end, decode = function(s) error("json not mocked") end },
    log = { new = function() return {
        i = function() end, w = function() end, e = function() end,
        f = function() end, d = function() end,
        wf = function() end, ef = function() end, df = function() end,
    } end },
    task = { run = function(cmd, args, onDone)
        table.insert(invokedCommands, cmd .. ":" .. table.concat(args or {}, " "))
        if onDone then onDone("", "", 0) end
    end },
    db = {
        open = mockDbHandle,
        migrate = { register = function() end, apply = function() end },
        orm = { define = function(def) return {
            bind = function() return _G.__m end,
            insert = function() return 1 end,
            findById = function() return nil end,
            query = function()
                local rows = {}
                for _, r in ipairs(mockRows) do rows[#rows + 1] = r end
                return rows, #rows
            end,
        } end },
    },
}

-- 定位 spoon 根（source 形如 @Spoons/.../test/unit_test.lua）
local ROOT = (debug.getinfo(1,"S").source:sub(2):match("^(.-)[/\\]test[/\\]") or "")
-- 保底：相对路径判断（dofile 时 source 无 @ 前缀的情况）
if ROOT == "" then ROOT = "core/launcher/" end
-- 确保以分隔符结尾
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local internalDir = ROOT .. "internal/"
local configModule = dofile(internalDir .. "config.lua")
-- config 里用了 require("core.hsutil") + debug 定位，需覆写 views_dir
-- 让 config 返回的 views_dir 指向真实（但测试聚焦逻辑）

-- =========================================================
-- 1. calc 裸搜索
-- =========================================================
local registry = dofile(internalDir .. "registry.lua")
local testConfig = {
    hotkey_show = {"alt","space"},
    pkg="launcher",
    base_url="http://127.0.0.1:8821/launcher",
    views_dir=ROOT.."views",
    debounce_ms=100,
    enabled_sources={"calc","urlformats","screencapture","useractions","custom","cards"},
    url_providers={ gh={name="GH",url="https://github.com/search?q=%s"} },
    user_actions={ ["示例动作"]={ url="https://example.com/${query}", keyword="ex" } },
    custom_commands={ hello={ keyword="hello", title="打招呼", kind="shell", exec={"/bin/echo",{"hello ${query}"}} } },
    cards={ ["打开项目目录"]={ description="在 Finder 打开 ~/code", kind="shell", exec={"/usr/bin/open",{"$HOME/code"}} },
           ["ex test 卡片"]={ description="关键词置顶验证用", kind="shell", exec={"/bin/echo",{}} },
           ["截图"]={ description="屏幕截图", kind="screen", sub={ kind="fullscreen" } },
           ["内嵌页面"]={ description="测试子页面", kind="page", url="/test/view/index.html" } },
}
registry.setup(testConfig)

local q1 = registry.query("1+2")
local calcRow
for _, r in ipairs(q1.rows) do if r.plugin=="calc" then calcRow=r end end
check("calc '1+2' 产出候选", calcRow ~= nil)
if calcRow then
    check("calc 候选 type=copyToClipboard", calcRow.type=="copyToClipboard", calcRow.type)
    check("calc 结果=3", tostring(calcRow.text)=="3", tostring(calcRow.text))
    check("calc row 入库（run 可重浄）", registry._store and registry._store[calcRow.id] ~= nil)
end

-- =========================================================
-- 2. 关键词 urlformat
-- =========================================================
local q2 = registry.query("uf hammerspoon")
check("'uf hammerspoon' 识别关键词 uf", q2.keyword=="uf", tostring(q2.keyword))
local ur = nil
for _, r in ipairs(q2.rows) do
    if r.plugin=="urlformats" and tostring(r.url):find("hammerspoon") then ur=r end
end
check("uf 产出 provider URL", ur ~= nil)
check("uf 候选 scheme=github", ur and ur.scheme=="https", ur and tostring(ur.scheme))

-- =========================================================
-- 3. useractions 关键词
-- =========================================================
local q3 = registry.query("ex test")
check("'ex test' 识别关键词 ex", q3.keyword=="ex", tostring(q3.keyword))
local kw = q3.rows and q3.rows[1]
check("useractions invokeKeyword 候选", kw and kw.type=="invokeKeyword", kw and kw.type)

-- =========================================================
-- 4. useractions 裸搜索
-- =========================================================
local q4 = registry.query("示例动作")
local ou = nil
for _, r in ipairs(q4.rows) do if r.plugin=="useractions" and r.type=="openURL" then ou=r end end
check("useractions 裸搜索命中 openURL", ou ~= nil)

-- =========================================================
-- 5. custom 命令源
-- =========================================================
local q5 = registry.query("hello pi")
check("'hello pi' 识别 custom 关键词", q5.keyword=="hello", tostring(q5.keyword))
local c = q5.rows and q5.rows[1]
check("custom 候选 type=custom", c and c.type=="custom", c and c.type)
check("custom 候选 arg='pi'", c and c.arg=="pi", c and tostring(c.arg))
local okRun = registry.runRow({ id = c.id })
check("custom runRow 执行（echo hello pi）", #invokedCommands>0 and invokedCommands[#invokedCommands]:find("echo",1,true)~=nil, table.concat(invokedCommands,","))

-- =========================================================
-- 6. runner 分发
-- =========================================================
local runner = dofile(internalDir .. "runner.lua")
check("runner 未知 type 返回 false", runner.run({type="zzz"})==false)
check("runner copyToClipboard 返回 true", runner.run({type="copyToClipboard", text="x"})==true)

-- =========================================================
-- 7. 空输入分组（section）
-- =========================================================
local q0 = registry.query("")
check("空输入 home=true", q0.home == true, tostring(q0.home))
local cardRow = nil
for _, r in ipairs(q0.rows) do if r.plugin == "cards" then cardRow = r end end
check("空输入返回快捷命令卡片", cardRow ~= nil)
check("卡片行带 section=快捷命令", cardRow and cardRow.section == "快捷命令", cardRow and tostring(cardRow.section))
-- mock 下 appCache 为空，homeApps 返回空 → 不强制断言 apps 行存在

-- =========================================================
-- 8. 关键词置顶不独占
-- =========================================================
-- 用 'ex test'：useractions 关键词 ex 命中置顶；裸搜索阶段 cards 的
-- "ex test 卡片" 也会命中（名字含完整子串），验证非独占
local q6 = registry.query("ex test")
check("'ex test' 识别关键词 ex", q6.keyword == "ex", tostring(q6.keyword))
check("关键词结果置顶（rows[1] 为 useractions）", q6.rows[1] and q6.rows[1].plugin == "useractions", q6.rows[1] and q6.rows[1].plugin)
check("关键词后仍有其他源结果（不独占）", #q6.rows > 1, tostring(#q6.rows))
local q6b = registry.query("ex")
check("关键词置顶不影响纯关键词调用", q6b.keyword == "ex", tostring(q6b.keyword))

-- =========================================================
-- 9. runRow overrides（命令详情变体参数）
-- =========================================================
local q7 = registry.query("截图")
local scRow
for _, r in ipairs(q7.rows) do if r.plugin == "cards" and r.type == "cardScreen" then scRow = r end end
check("screen 卡片候选存在", scRow ~= nil)
local ok7 = registry.runRow({ id = scRow.id, overrides = { subKind = "interactive" } })
check("runRow overrides 执行成功", ok7 == true)
local last = invokedCommands[#invokedCommands] or ""
check("overrides 生效（screencapture -i）", last:find("screencapture", 1, true) ~= nil and last:find("-i", 1, true) ~= nil, last)
-- 无 overrides 时默认 subKind
local ok7b = registry.runRow({ id = scRow.id })
check("runRow 无 overrides 仍可执行", ok7b == true)

-- =========================================================
-- 10. 命令发现（launcher-commands.lua merge）
-- =========================================================
-- 造一个临时命令文件，registry.scanCommandProviders 应 merge 其 cards
local tmpCmdFile = os.tmpname()
local f = io.open(tmpCmdFile, "w")
f:write([[
return {
  name = "testprov",
  cards = {
    ["测试命令"] = { description="测试", kind="runFunction",
      fn = function(cfg) table.insert(invokedCommands, "testfn:" .. tostring(cfg and cfg.x)) end,
      config = { { key="x", label="X", type="select", options={ {label="A", value=1} } } } },
  },
}
]])
f:close()
registry.scanCommandProviders({ testprov = tmpCmdFile })
local q8 = registry.query("")
local trow
for _, r in ipairs(q8.rows) do if r.plugin == "cards" and r.text == "测试命令" then trow = r end end
check("命令发现：外部文件卡片已加载", trow ~= nil)
check("命令发现：kind=runFunction", trow and trow.type == "runFunction")
check("命令发现：config schema 透传", trow and trow.config and trow.config[1] and trow.config[1].key == "x")
-- 执行：overrides config 传参
local ok8 = registry.runRow({ id = trow.id, overrides = { config = { x = 1 } } })
check("命令发现：fn(config) 执行", ok8 == true and invokedCommands[#invokedCommands] == "testfn:1", invokedCommands[#invokedCommands])
os.remove(tmpCmdFile)

-- =========================================================
-- 11. store：app_stats ORM 读 + user_actions 存库
-- =========================================================
local storeMod = dofile(internalDir .. "store.lua")
pcall(storeMod.open, nil)   -- 测试实例独立开库（mock db）
mockDbLog = {}
storeMod.upsertAction("书签A", { url = "https://a.com", icon = "data:image/png;base64,xx" })
local upLog = mockDbLog[1] or {}
check("upsertAction 写 user_actions 表", tostring(upLog.sql or ""):find("user_actions", 1, true) ~= nil, tostring(upLog.sql))
check("upsertAction 绑定参数（name 首参）", upLog.binds and upLog.binds[1] == "书签A", upLog.binds and tostring(upLog.binds[1]))

mockRows = { { name = "书签B", url = "https://b.com", icon = "data:image/png;base64,test", created = 1 } }
local acts = storeMod.allActions()
check("allActions 读回书签", acts["书签B"] ~= nil and acts["书签B"].url == "https://b.com", acts["书签B"] and acts["书签B"].url)
check("allActions 字段契约：icon 列映射为 encoded_icon", acts["书签B"] ~= nil and acts["书签B"].encoded_icon == "data:image/png;base64,test", acts["书签B"] and tostring(acts["书签B"].encoded_icon))
check("allActions 不暴露 icon 字段", acts["书签B"] ~= nil and acts["书签B"].icon == nil)

mockDbLog = {}
storeMod.deleteAction("书签B")
local delLog = mockDbLog[1] or {}
check("deleteAction 走绑定参数 DELETE", tostring(delLog.sql or ""):find("DELETE FROM user_actions", 1, true) ~= nil, tostring(delLog.sql))

mockRows = {}
local stats = storeMod.all()
check("app_stats all() 空库安全", type(stats) == "table" and next(stats) == nil)

-- =========================================================
-- 12. useractions saveAdd/saveDel 落库（经 registry 注入的 store）
-- =========================================================
mockDbLog = {}
local qAdd = registry.query("add https://new.example.com 新书签")
local addRow = qAdd.rows and qAdd.rows[1]
check("add 关键词候选存在", addRow ~= nil and addRow.type == "addURL", addRow and tostring(addRow.type))
local okAdd = registry.runRow({ id = addRow and addRow.id })
check("saveAdd 执行成功", okAdd == true)
local foundUp = false
for _, e in ipairs(mockDbLog) do
    if tostring(e.sql or ""):find("user_actions", 1, true) and e.binds and e.binds[1] == "新书签" then
        foundUp = true
    end
end
check("saveAdd 写入 user_actions（绑定参数）", foundUp)

-- saveDel 端到端：先 add 落库一条，再 del 删除
mockDbLog = {}
local qAdd2 = registry.query("add https://del.example.com 待删书签")
local addRow2 = qAdd2.rows and qAdd2.rows[1]
check("saveDel 前置：add 候选存在", addRow2 ~= nil and addRow2.type == "addURL", addRow2 and tostring(addRow2.type))
local okAdd2 = registry.runRow({ id = addRow2 and addRow2.id })
check("saveDel 前置：saveAdd 执行成功", okAdd2 == true)
mockDbLog = {}
local qDel = registry.query("del 待删")
local delRow = qDel.rows and qDel.rows[1]
check("del 关键词候选存在", delRow ~= nil and delRow.type == "delURL", delRow and tostring(delRow.type))
local okDel = registry.runRow({ id = delRow and delRow.id })
check("saveDel 执行成功", okDel == true)
local foundDel = false
for _, e in ipairs(mockDbLog) do
    if tostring(e.sql or ""):find("DELETE FROM user_actions", 1, true)
        and e.binds and e.binds[1] == "待删书签" then
        foundDel = true
    end
end
check("saveDel 写 DELETE（绑定参数）", foundDel)
-- 内存侧清除的间接验证：再次 del 查询应无候选
local qDel2 = registry.query("del 待删")
check("saveDel 同步清内存（再次 del 无候选）", #(qDel2.rows or {}) == 0, tostring(#(qDel2.rows or {})))

-- =========================================================
-- 13. registry.stop 对称清理（关库无错误）
-- =========================================================
local okStop = pcall(registry.stop)
check("registry.stop 无错误", okStop)

-- =========================================================
-- 14. kind="page" 子页面卡片
-- =========================================================
local qp = registry.query("")
local pageRow = nil
for _, r in ipairs(qp.rows) do
    if r.plugin == "cards" and r.type == "cardPage" then pageRow = r end
end
check("kind=page 候选存在", pageRow ~= nil, pageRow and tostring(pageRow.type))
check("cardPage 携带 pageUrl", pageRow and pageRow.pageUrl == "/test/view/index.html",
      pageRow and tostring(pageRow.pageUrl))
local okP = registry.runRow({ id = pageRow and pageRow.id })
check("cardPage runRow 执行（no-op）", okP == true)

-- =========================================================
-- 15. registerProvider 运行时注册 + manifest 校验
-- =========================================================
registry.registerProvider("testruntime", {
    name = "testruntime",
    cards = {
        ["运行时卡片"] = { description = "runtime", kind = "shell", exec = { "/bin/echo", {} } },
    },
})
local qr = registry.query("")
local foundRt = false
for _, r in ipairs(qr.rows) do
    if r.plugin == "cards" and r.text == "运行时卡片" then foundRt = true end
end
check("registerProvider 实时刷新 cards 源", foundRt)

-- 非法条目：未知 kind 应被跳过（不崩溃、不出现）
registry.registerProvider("badprovider", {
    cards = { ["坏卡片"] = { description = "bad", kind = "unknownkind" } },
})
local qb = registry.query("坏卡片")
local badFound = false
for _, r in ipairs(qb.rows) do
    if r.text == "坏卡片" then badFound = true end
end
check("非法 kind 条目被跳过", not badFound)

-- 非法 user_actions（无 url 无 fn）应被跳过
registry.registerProvider("badprovider2", {
    user_actions = { ["坏动作"] = { description = "nofn" } },
})
local qa = registry.query("坏动作")
local badAction = false
for _, r in ipairs(qa.rows) do
    if r.text == "坏动作" then badAction = true end
end
check("非法 user_actions 被跳过", not badAction)

-- pages（统一页面注册表）：候选行携带 searchUrl（Tab 注入依据）+ 非法条目跳过
registry.registerProvider("testpages", {
    cards = {
        ["测试配置页"] = { description = "t", kind = "page", icon = "⚙️", url = "settings" },
    },
    pages = {
        { name = "测试配置页", icon = "⚙️", config = "settings", search = "search" },
        { name = "坏页面" },   -- 缺 config/search
    },
})
local qc = registry.query("测试配置页")
local foundSearch = false
for _, r in ipairs(qc.rows) do
    if r.text == "测试配置页" and r.searchUrl == "/testpages/view/pages/search/index.html" then
        foundSearch = true
    end
end
check("pages 协议：候选行 search 简写推断为 searchUrl", foundSearch)

-- =========================================================
-- 16. scanCommandDirs 目录发现（真实 HS 双返回值模拟）
-- =========================================================
-- 构造真实临时目录结构：provider 文件必须真实存在，dofile 才可加载；
-- _mockFS 让 mock fs 把 tmpRoot 视为目录结构（dir 迭代 + attributes mode 查询）
local tmpRoot = os.tmpname()
os.remove(tmpRoot)
os.execute('mkdir -p "' .. tmpRoot .. '/MySpoon.spoon"')
local pf = io.open(tmpRoot .. "/MySpoon.spoon/launcher-commands.lua", "w")
pf:write([[return {
  name = "myspoon",
  cards = {
    ["扫描发现卡片"] = { description = "来自目录扫描", kind = "shell", exec = { "/bin/echo", {} } },
  },
}]])
pf:close()
_mockFS = {
    dirs = {
        [tmpRoot] = { "MySpoon.spoon" },
        [tmpRoot .. "/MySpoon.spoon"] = {},
    },
    files = { [tmpRoot .. "/MySpoon.spoon/launcher-commands.lua"] = true },
}
local okScan = pcall(registry.scanCommandDirs, { tmpRoot })
check("scanCommandDirs 目录遍历无错误", okScan)
local q16 = registry.query("")
local foundScan = false
for _, r in ipairs(q16.rows) do
    if r.plugin == "cards" and r.text == "扫描发现卡片" then foundScan = true end
end
check("scanCommandDirs 发现提供者并合并卡片", foundScan)
os.execute('rm -rf "' .. tmpRoot .. '"')

-- =========================================================
-- 汇总
-- =========================================================
print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
os.exit(results.fail==0 and 0 or 1)

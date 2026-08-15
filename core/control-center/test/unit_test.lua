-- ControlCenter 纯 Lua 单元测试(lua5.4/lua5.5 运行,mock 掉 hs.* 与 core.hsutil)
-- 运行:  lua core/control-center/test/unit_test.lua
-- 覆盖:
--   A. sources:目录发现(hs.fs.dir 双返回值 state 陷阱)、manifest 提取
--      (name/cards/pages + config_pages 老字段兼容)、页面 URL 简写推断、
--      同名 provider 去重覆盖、异常 manifest/目录容错、get() 缓存
--   B. panel:惰性单例首载 / setUrl 切换 / 同 URL 仅 show / showAggregate /
--      返回 shim 注入时机(导航完成检测)与内容 / teardown 停止轮询
--   C. menubar:菜单结构(聚合页/各 Spoon 入口/重载/退出)、每次打开重新扫描、
--      扫描异常降级、点击入口打开面板配置页(含真实兄弟模块集成)
-- =========================================================

local results = { pass = 0, fail = 0 }
local function check(name, cond, detail)
    if cond then
        print("  [PASS] " .. name); results.pass = results.pass + 1
    else
        print("  [FAIL] " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
        results.fail = results.fail + 1
    end
end

-- 文件系统 mock(共享):A 段与 C 段集成测试均消费 _mockFS 全局
local function makeFSMock()
    return {
        -- 模拟 HS 1.1.1:hs.fs.dir 返回 (iteratorFn, dirUserdata) 两个值,
        -- dirUserdata 是 for 循环的 state;迭代器校验 state 参数,缺 state(如被
        -- pcall 丢掉)时报错,与真实 HS 行为一致("directory metatable expected")。
        -- 未知目录直接报错(与真实 HS 一致),验证模块的 pcall 单目录容错。
        dir = function(path)
            if _mockFS.dirs[path] == nil then
                error("no such file or directory: " .. tostring(path))
            end
            local entries = _mockFS.dirs[path]
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
    }
end

-- 通用日志 mock
local function makeLogger()
    return { i = function() end, w = function() end, e = function() end,
             f = function() end, wf = function() end, ef = function() end, df = function() end }
end

-- 按名取提供者(扫描顺序依赖 hs.fs.dir,按名断言最稳)
local function findProv(list, name)
    for _, p in ipairs(list) do
        if p.name == name then return p end
    end
    return nil
end

-- =========================================================
-- A. sources 只读协议扫描器(30 用例)
-- =========================================================
-- Mock hs + core.hsutil(只 mock sources.lua 用到的部分)
-- 文件系统 mock 数据:目录表 + 文件表,由 hs.fs 的 mock 消费
_mockFS = { dirs = {}, files = {} }

hs = {
    logger = { new = function() return makeLogger() end },
    configdir = "",
    fs = makeFSMock(),
}

-- mock core.hsutil(sources.lua require 到的部分:log + path)
package.preload["core.hsutil"] = function()
    return {
        log = { new = function() return makeLogger() end },
        path = { join = function(a, b) return a .. "/" .. b end },
    }
end

-- 定位本文件目录(source 形如 core/control-center/test/unit_test.lua)
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.-)[/\\]test[/\\]") or "")
if ROOT == "" then ROOT = "core/control-center/" end
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local sources = dofile(ROOT .. "internal/sources.lua")

-- =========================================================
-- 工具:构造真实临时目录结构(dofile 需要真实文件;_mockFS 供 mock fs 消费)
-- =========================================================
local function mkdir(p)
    os.execute('mkdir -p "' .. p .. '"')
end
local function writeFile(p, content)
    local f = io.open(p, "w")
    f:write(content)
    f:close()
end
-- 注册一个提供者:真实目录 + 文件 + _mockFS 目录表/文件表
local function addProvider(fsRoot, relDir, manifestLua)
    local dir = fsRoot .. "/" .. relDir
    mkdir(dir)
    local file = dir .. "/launcher-commands.lua"
    writeFile(file, manifestLua)
    _mockFS.files[file] = true
    _mockFS.dirs[dir] = _mockFS.dirs[dir] or {}
    return dir
end

-- =========================================================
-- A.1 真实仓库布局镜像:5 个 Spoon + core/{hsutil,launcher/template}
--    (与 launcher 实际合并结果一致:5 个提供者;template 在 core/*/ 二层,
--      与 launcher 一样不会被一级扫描发现,且其 cards 为空,无可见贡献)
-- =========================================================
local tmpRoot = os.tmpname()
os.remove(tmpRoot)
mkdir(tmpRoot .. "/Spoons")
mkdir(tmpRoot .. "/core/hsutil")
mkdir(tmpRoot .. "/core/launcher/template")
-- 5 个 Spoon(manifest 内容与仓库真实文件一致)
addProvider(tmpRoot, "Spoons/AppToggle.spoon", [[
return {
    name = "apptoggle",
    cards = {
        ["应用显隐"] = { description = "一键显隐应用（全局热键 + 布局锁定）", kind = "page", icon = "🔄", url = "apps" },
    },
    pages = {
        { name = "应用显隐", icon = "🔄", config = "apps" },
    },
}
]])
addProvider(tmpRoot, "Spoons/BingDaily.spoon", [[
return {
    name = "bingdaily",
    cards = {
        ["Bing 壁纸"] = { description = "Bing 每日壁纸（轮询 + 一键执行 + 历史切换）", kind = "page", icon = "🖼️", url = "settings" },
    },
    pages = {
        { name = "Bing 壁纸", icon = "🖼️", config = "settings", search = "search" },
    },
}
]])
addProvider(tmpRoot, "Spoons/Clipboard.spoon", [[
return {
    name = "clipboard",
    cards = {
        ["剪贴板"] = { description = "剪贴板设置（历史记录可用 Ctrl+V 呼出）", kind = "page", icon = "📋", url = "settings" },
    },
    pages = {
        { name = "剪贴板", icon = "📋", config = "settings", search = "history" },
    },
}
]])
addProvider(tmpRoot, "Spoons/QuantumWindow.spoon", [[
return {
    name = "quantumwindow",
    cards = {
        ["窗口管理"] = { description = "窗口布局与快捷热键", kind = "page", icon = "🪟", url = "settings" },
    },
    pages = {
        { name = "窗口管理", icon = "🪟", config = "settings" },
    },
}
]])
addProvider(tmpRoot, "Spoons/StayAwake.spoon", [[
return {
    name = "stayawake",
    cards = {
        ["防睡眠"] = { description = "防睡眠控制面板（子页面）", kind = "page", icon = "🌙", url = "control" },
    },
    pages = {
        { name = "防睡眠", icon = "🌙", config = "control" },
    },
}
]])
-- 干扰项:点文件、无 manifest 的目录、core 二层 template(不应被发现)
writeFile(tmpRoot .. "/Spoons/.DS_Store", "")
_mockFS.files[tmpRoot .. "/Spoons/.DS_Store"] = true
_mockFS.dirs[tmpRoot .. "/Spoons/NotASpoon"] = {}
_mockFS.dirs[tmpRoot .. "/core/hsutil"] = {}
_mockFS.dirs[tmpRoot .. "/core/launcher"] = { "template" }
_mockFS.dirs[tmpRoot .. "/core/launcher/template"] = {}
addProvider(tmpRoot, "core/launcher/template", [[
-- 模板:cards 全注释(空贡献),且位于 core/*/ 二层不会被一级扫描发现
return {
    name = "myspoon",
    cards = {},
}
]])
-- 顶层目录表
_mockFS.dirs[tmpRoot .. "/Spoons"] = { "AppToggle.spoon", "BingDaily.spoon", "Clipboard.spoon", ".DS_Store", "NotASpoon", "QuantumWindow.spoon", "StayAwake.spoon" }
_mockFS.dirs[tmpRoot .. "/core"] = { "hsutil", "launcher" }

-- 默认扫描(hs.configdir 指向 tmpRoot,走 scan() 无参默认目录)
hs.configdir = tmpRoot
local listA = sources.scan()

check("A1 默认扫描返回 5 个提供者", #listA == 5, tostring(#listA))
check("A2 提供者名齐全", findProv(listA, "apptoggle") ~= nil and findProv(listA, "bingdaily") ~= nil
    and findProv(listA, "clipboard") ~= nil and findProv(listA, "quantumwindow") ~= nil
    and findProv(listA, "stayawake") ~= nil)
check("A3 core/launcher/template 未被扫描（二层，与 launcher 一致）", findProv(listA, "myspoon") == nil)

-- AppToggle:卡片 + 页面 URL 简写推断
local at = findProv(listA, "apptoggle")
check("A4 apptoggle 卡片数=1", at and #at.cards == 1, at and tostring(#at.cards))
if at and at.cards[1] then
    local c = at.cards[1]
    check("A5 卡片字段 key/description/icon/kind", c.key == "应用显隐" and c.description ~= nil
        and c.icon == "🔄" and c.kind == "page")
    check("A6 page 卡 url 简写推断", c.url == "/apptoggle/view/pages/apps/index.html", tostring(c.url))
end
check("A7 apptoggle pages 配置页推断", at and #at.pages == 1
    and at.pages[1].configUrl == "/apptoggle/view/pages/apps/index.html", at and at.pages[1] and tostring(at.pages[1].configUrl))
check("A8 apptoggle 无 searchUrl（可选字段缺省）", at and at.pages[1].searchUrl == nil)

-- Clipboard:search 页推断
local cb = findProv(listA, "clipboard")
check("A9 clipboard 卡片 url 推断", cb and cb.cards[1] and cb.cards[1].url == "/clipboard/view/pages/settings/index.html",
    cb and cb.cards[1] and tostring(cb.cards[1].url))
check("A10 clipboard search 页推断", cb and cb.pages[1] and cb.pages[1].searchUrl == "/clipboard/view/pages/history/index.html",
    cb and cb.pages[1] and tostring(cb.pages[1].searchUrl))

-- StayAwake / QuantumWindow / BingDaily 抽查
local sa = findProv(listA, "stayawake")
check("A11 stayawake control 页推断", sa and sa.pages[1]
    and sa.pages[1].configUrl == "/stayawake/view/pages/control/index.html",
    sa and sa.pages[1] and tostring(sa.pages[1].configUrl))
local qw = findProv(listA, "quantumwindow")
check("A12 quantumwindow 卡片+页面齐全", qw and #qw.cards == 1 and #qw.pages == 1)
local bd = findProv(listA, "bingdaily")
check("A13 bingdaily 配置页+搜索页", bd and bd.pages[1].configUrl == "/bingdaily/view/pages/settings/index.html"
    and bd.pages[1].searchUrl == "/bingdaily/view/pages/search/index.html")

-- get() 缓存语义
local g1 = sources.get()
check("A14 get() 返回缓存（同一份表）", g1 == listA)
local listA2 = sources.scan()
check("A15 scan() 重扫返回新表", listA2 ~= listA and sources.get() == listA2)
check("A16 重扫结果仍 5 个", #listA2 == 5, tostring(#listA2))

-- =========================================================
-- A.2 边界:scan(dirs) 显式目录 + 异常容错
-- =========================================================
local tmpRoot2 = os.tmpname()
os.remove(tmpRoot2)
mkdir(tmpRoot2 .. "/Spoons")
mkdir(tmpRoot2 .. "/core/hsutil")
mkdir(tmpRoot2 .. "/core/dupe")

-- 无 name 字段:回退目录名;openurl 完整 URL 原样透传
addProvider(tmpRoot2, "Spoons/NoName.spoon", [[
return {
    cards = {
        ["官网"] = { description = "打开官网", kind = "openurl", url = "https://example.com/search?q=x" },
    },
}
]])
-- config_pages 老字段:仅老字段也可出页面
addProvider(tmpRoot2, "Spoons/ConfigPages.spoon", [[
return {
    name = "configpages",
    config_pages = {
        { name = "旧配置", icon = "⚙️", url = "legacy" },
    },
}
]])
-- pages 与 config_pages 同名:新字段优先,老字段跳过
addProvider(tmpRoot2, "Spoons/BothPages.spoon", [[
return {
    name = "bothpages",
    pages = {
        { name = "新配置", config = "new" },
    },
    config_pages = {
        { name = "新配置", url = "old" },
    },
}
]])
-- 非法 manifest:非 table / 加载抛错 → 跳过不崩溃
addProvider(tmpRoot2, "Spoons/ZBad.spoon", "return 42")
addProvider(tmpRoot2, "Spoons/ZBroken.spoon", 'error("boom")')
-- 同名 provider 去重覆盖:core 后扫,覆盖 Spoons 同名提供者
addProvider(tmpRoot2, "Spoons/DupeA.spoon", [[
return {
    name = "dupeme",
    cards = {
        ["先扫描卡片"] = { description = "A", kind = "page", icon = "①", url = "a" },
    },
}
]])
addProvider(tmpRoot2, "core/dupe", [[
return {
    name = "dupeme",
    cards = {
        ["后扫描卡片"] = { description = "B", kind = "page", icon = "②", url = "b" },
    },
}
]])
-- 干扰项:点文件、无 manifest 目录
writeFile(tmpRoot2 .. "/Spoons/.DS_Store", "")
_mockFS.files[tmpRoot2 .. "/Spoons/.DS_Store"] = true
_mockFS.dirs[tmpRoot2 .. "/Spoons/Empty.spoon"] = {}
_mockFS.dirs[tmpRoot2 .. "/core/hsutil"] = {}
_mockFS.dirs[tmpRoot2 .. "/Spoons"] = { "NoName.spoon", "ConfigPages.spoon", "BothPages.spoon", "ZBad.spoon", "ZBroken.spoon", "DupeA.spoon", ".DS_Store", "Empty.spoon" }
_mockFS.dirs[tmpRoot2 .. "/core"] = { "dupe", "hsutil" }

-- 显式传目录(含一个不存在的目录,验证 pcall 单目录容错)
local listB = sources.scan({ tmpRoot2 .. "/Spoons", tmpRoot2 .. "/Nope", tmpRoot2 .. "/core" })
-- 4 个提供者:NoName.spoon/configpages/bothpages/dupeme(ZBad/ZBroken/Empty/点文件被跳过)
check("B1 显式目录扫描无错误且结果齐全（不存在的目录被 pcall 容错）", #listB == 4, tostring(#listB))
check("B2 无 name 回退目录名", findProv(listB, "NoName.spoon") ~= nil)
local nn = findProv(listB, "NoName.spoon")
check("B3 openurl 完整 URL 原样透传", nn and nn.cards[1] and nn.cards[1].url == "https://example.com/search?q=x",
    nn and nn.cards[1] and tostring(nn.cards[1].url))
check("B4 config_pages 老字段兼容", findProv(listB, "configpages") ~= nil)
local cp = findProv(listB, "configpages")
check("B5 config_pages 出配置页（简写推断）", cp and cp.pages[1]
    and cp.pages[1].configUrl == "/configpages/view/pages/legacy/index.html",
    cp and cp.pages[1] and tostring(cp.pages[1].configUrl))
local bp = findProv(listB, "bothpages")
check("B6 pages 与 config_pages 同名：新字段优先", bp and #bp.pages == 1
    and bp.pages[1].configUrl == "/bothpages/view/pages/new/index.html",
    bp and #bp.pages and bp.pages[1] and tostring(bp.pages[1].configUrl))
check("B7 非法 manifest（非 table）被跳过", findProv(listB, "ZBad.spoon") == nil)
check("B8 加载抛错的 manifest 被跳过", findProv(listB, "ZBroken.spoon") == nil)
check("B9 点文件/无 manifest 目录不产生提供者", findProv(listB, ".DS_Store") == nil and findProv(listB, "Empty.spoon") == nil)
-- 同名覆盖:core/dupe 后扫覆盖 Spoons/DupeA.spoon
local dm = findProv(listB, "dupeme")
check("B10 同名 provider 去重为 1 个", dm ~= nil)
local dmCount = 0
for _, p in ipairs(listB) do if p.name == "dupeme" then dmCount = dmCount + 1 end end
check("B11 dupeme 全局唯一", dmCount == 1, tostring(dmCount))
check("B12 后扫描者覆盖（卡片=后扫描卡片）", dm and #dm.cards == 1 and dm.cards[1].key == "后扫描卡片"
    and dm.cards[1].url == "/dupeme/view/pages/b/index.html",
    dm and dm.cards[1] and tostring(dm.cards[1].key))

-- =========================================================
-- A.3 只读零侵入:manifest 文件未被改写,源表未被污染
-- =========================================================
local f = io.open(tmpRoot .. "/Spoons/AppToggle.spoon/launcher-commands.lua", "r")
local contentA = f:read("*a"); f:close()
check("C1 manifest 文件未被改写", contentA:find("一键显隐应用", 1, true) ~= nil
    and contentA:find("url = \"apps\"", 1, true) ~= nil)
check("C2 原 manifest 表未被修改（url 推断生成新表）",
    findProv(listA, "apptoggle").cards[1].url == "/apptoggle/view/pages/apps/index.html"
    and contentA:find("url = \"apps\"", 1, true) ~= nil)

-- =========================================================
-- B. panel 配置面板单例(31 用例)
-- =========================================================
package.loaded["core.hsutil"] = nil

-- Mock 状态
local M = {
    created = {},        -- HSUtil.webview.new 收到的 opts
    view = nil,          -- 最近创建的 fake View
    evals = {},          -- fake webview evaluateJavaScript 记录
    timerStopped = false,-- 最近一次 doEvery 返回的 timer 是否被 stop
    lastTimerCb = nil,   -- 最近一次 doEvery 的回调(测试手动触发)
    loading = false,     -- fake webview loading() 返回值(测试控制)
}

-- 重置 mock(每个测试用例前)
local function resetMocks()
    M.created = {}
    M.view = nil
    M.evals = {}
    M.timerStopped = false
    M.lastTimerCb = nil
    M.loading = false
end

local function newFakeView(opts)
    local raw = {
        _url = nil,
        loading = function() return M.loading end,
        url = function(self, v)
            if v ~= nil then self._url = v; return self end
            return self._url
        end,
        evaluateJavaScript = function(_, js)
            M.evals[#M.evals + 1] = js
        end,
    }
    local v = {
        _raw = nil,
        _visible = false,
        show = function(self)
            -- 模拟 HSUtil.webview:首次 show 惰性创建底层 webview 并加载首载 URL
            if not self._raw then
                self._raw = raw
                raw._url = opts.url
            end
            self._visible = true
            return true
        end,
        hide = function(self) self._visible = false end,
        visible = function(self) return self._visible end,
        teardown = function(self) self._raw = nil; self._visible = false end,
        raw = function(self) return self._raw end,
    }
    return v
end

local mockHS = {
    logger = { new = function() return makeLogger() end },
    screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end },
    timer = {
        doEvery = function(_, cb)
            M.lastTimerCb = cb
            return { stop = function() M.timerStopped = true end }
        end,
    },
}
hs = mockHS

package.preload["core.hsutil"] = function()
    return {
        log = { new = function() return makeLogger() end },
        webview = {
            new = function(opts)
                M.created[#M.created + 1] = opts
                M.view = newFakeView(opts)
                return M.view
            end,
        },
        json = { encode = function(v) return '"' .. tostring(v):gsub('"', '\\"') .. '"' end },
    }
end

-- 每个用例重新 dofile panel.lua(模块级单例状态随 chunk 重置)
local PANEL_PATH = ROOT .. "internal/panel.lua"
local function newPanel()
    resetMocks()
    return dofile(PANEL_PATH)
end

-- 手动触发一次 shim 轮询
local function tick()
    if not M.lastTimerCb then return end
    M.lastTimerCb()
end

local AGG = "http://127.0.0.1:8821/cc/view/pages/aggregate/index.html"
local P1 = "http://127.0.0.1:8821/stayawake/view/pages/control/index.html"
local P2 = "http://127.0.0.1:8821/quantumwindow/view/pages/settings/index.html"

-- 1) 首次 open:惰性创建,首载 URL 透传,show 触发
do
    local panel = newPanel()
    local ok = panel.open(P1)
    check("D1 open 返回 true", ok == true)
    check("D2 单例以首载 url 创建", #M.created == 1 and M.created[1].url == P1)
    check("D3 尺寸比例同 launcher(0.52/0.62/0.22)",
        M.created[1].widthRatio == 0.52 and M.created[1].heightRatio == 0.62 and M.created[1].yRatio == 0.22)
    check("D4 首次 show 后底层 webview 已建且指向首载 url",
        M.view:raw() ~= nil and M.view:raw():url() == P1)
    check("D5 面板可见", panel.visible() == true)
end

-- 2) 已创建且 url 不同:setUrl 切换后 show
do
    local panel = newPanel()
    panel.open(P1)
    local ok = panel.open(P2)
    check("D6 open 返回 true", ok == true)
    check("D7 setUrl 切换:底层 url 指向新页", M.view:raw():url() == P2)
    check("D8 同一单例(未新建 webview)", #M.created == 1)
end

-- 3) 已创建且 url 相同:仅 show,不触发 setUrl
do
    local panel = newPanel()
    panel.open(P1)
    tick()   -- 首载完成后注入一次 shim
    check("D9 首载注入一次", #M.evals == 1)
    local evalsBefore = #M.evals
    local ok = panel.open(P1)
    check("D10 open 返回 true", ok == true)
    check("D11 同 URL 不触发导航(底层 url 不变)", M.view:raw():url() == P1)
    tick()
    check("D12 同 URL 页面不重复注入 shim", #M.evals == evalsBefore)
end

-- 4) open 缺 url 且未 setup:忽略不崩
do
    local panel = newPanel()
    check("D13 open(nil) 未 setup 时返回 false", panel.open() == false)
end

-- 5) showAggregate 未 setup:返回 false
do
    local panel = newPanel()
    check("D14 showAggregate 未 setup 返回 false", panel.showAggregate() == false)
end

-- 6) setup 后 showAggregate:切回聚合页 URL
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    panel.showAggregate()
    check("D15 showAggregate setUrl 到聚合页", M.view:raw():url() == AGG)
end

-- 7) shim 注入时机:导航完成(不加载中)才注入,每文档一次
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    check("D16 导航未完成前不注入", #M.evals == 0)
    tick()
    check("D17 导航完成后注入一次", #M.evals == 1)
    tick()
    check("D18 同一文档不重复注入", #M.evals == 1)
    -- 切换新页后再次注入
    panel.open(P2)
    tick()
    check("D19 切换新页后重新注入", #M.evals == 2)
end

-- 8) 加载中不注入,加载完成才注入
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    M.loading = true
    tick()
    check("D20 loading 中不注入", #M.evals == 0)
    M.loading = false
    tick()
    check("D21 加载完成注入", #M.evals == 1)
end

-- 9) shim 内容:closePage / closeStayAwake = 切回聚合页
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    tick()
    local js = M.evals[1] or ""
    check("D22 shim 定义 window.closePage", js:find("window%.closePage", 1, false) ~= nil)
    check("D23 shim 定义 window.closeStayAwake", js:find("window%.closeStayAwake", 1, false) ~= nil)
    check("D24 shim 目标是聚合页 URL(json 编码)", js:find('agg = "' .. AGG .. '"', 1, false) ~= nil)
    check("D25 shim 幂等标记", js:find("__ccPanelShim", 1, false) ~= nil)
end

-- 10) shim 兜底:未 setup 时注入目标回退为当前页(不崩,不注入 nil)
do
    local panel = newPanel()
    panel.open(P1)
    tick()
    check("D26 未 setup 时 shim 兜底为当前 url", #M.evals == 1 and M.evals[1]:find('agg = "' .. P1 .. '"', 1, false) ~= nil)
end

-- 11) hide / visible 透传
do
    local panel = newPanel()
    panel.open(P1)
    panel.hide()
    check("D27 hide 后不可见", panel.visible() == false)
    panel.open(P1)
    check("D28 再次 open 可见", panel.visible() == true)
end

-- 12) teardown:停止轮询并销毁单例
do
    local panel = newPanel()
    panel.open(P1)
    panel.teardown()
    check("D29 teardown 停止 shim 轮询", M.timerStopped == true)
    check("D30 teardown 后可见性归零", panel.visible() == false)
    -- 重新 open 重建单例
    local ok = panel.open(P1)
    check("D31 teardown 后可重建", ok == true and #M.created == 2)
end

-- =========================================================
-- C. menubar 菜单栏(26 用例)
-- =========================================================
package.loaded["core.hsutil"] = nil

-- Mock 状态:菜单栏创建 / 菜单构建 / reload / exit / webview(集成用)
local barCalls = { created = {}, titles = {}, tooltips = {}, removes = 0 }
local hsCalls = { reloads = 0, exits = 0 }
local fakeBar = nil

-- 集成用 webview mock 状态(点击入口 → 真实 panel.open → HSUtil.webview.new)
local W = { created = {}, view = nil, timerCb = nil, loading = false }

local function resetBarCalls()
    barCalls.created = {}
    barCalls.titles = {}
    barCalls.tooltips = {}
    barCalls.removes = 0
    hsCalls.reloads = 0
    hsCalls.exits = 0
    fakeBar = nil
    W.created = {}
    W.view = nil
    W.timerCb = nil
    W.loading = false
end

local function newFakeView2(opts)
    local raw = {
        _url = nil,
        loading = function() return W.loading end,
        url = function(self, v)
            if v ~= nil then self._url = v; return self end
            return self._url
        end,
        evaluateJavaScript = function() end,
    }
    local v = {
        _raw = nil,
        _visible = false,
        show = function(self)
            if not self._raw then self._raw = raw; raw._url = opts.url end
            self._visible = true
            return true
        end,
        hide = function(self) self._visible = false end,
        visible = function(self) return self._visible end,
        teardown = function(self) self._raw = nil; self._visible = false end,
        raw = function(self) return self._raw end,
    }
    return v
end

hs = {
    logger = { new = function() return makeLogger() end },
    configdir = "",
    fs = makeFSMock(),
    screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end },
    timer = {
        doEvery = function(_, cb)
            W.timerCb = cb
            return { stop = function() end }
        end,
    },
    menubar = {
        new = function(globalFlag)
            barCalls.created[#barCalls.created + 1] = globalFlag
            local b = { _menu = nil }
            b.setTitle = function(_, t) barCalls.titles[#barCalls.titles + 1] = t end
            b.setTooltip = function(_, t) barCalls.tooltips[#barCalls.tooltips + 1] = t end
            b.setMenu = function(_, menuFn) b._menu = menuFn end
            b.remove = function() barCalls.removes = barCalls.removes + 1 end
            fakeBar = b
            return b
        end,
    },
    reload = function() hsCalls.reloads = hsCalls.reloads + 1 end,
    exit = function() hsCalls.exits = hsCalls.exits + 1 end,
}

package.preload["core.hsutil"] = function()
    return {
        log = { new = function() return makeLogger() end },
        path = { join = function(a, b) return a .. "/" .. b end },
        webview = {
            new = function(opts)
                W.created[#W.created + 1] = opts
                W.view = newFakeView2(opts)
                return W.view
            end,
        },
        json = { encode = function(v) return '"' .. tostring(v):gsub('"', '\\"') .. '"' end },
    }
end

local MENUBAR_PATH = ROOT .. "internal/menubar.lua"
local function newMenubar()
    resetBarCalls()
    return dofile(MENUBAR_PATH)
end

-- 按标题取菜单项
local function findItem(menu, title)
    for _, it in ipairs(menu) do
        if it.title == title then return it end
    end
    return nil
end

-- 假数据源:scan 可抛错(模拟扫描失败);get 返回缓存
local function makeFakeSources(list, failScan)
    return {
        scan = function()
            if failScan then error("scan boom") end
            return list
        end,
        get = function() return list end,
    }
end
-- 假面板:记录 open/showAggregate 调用(menubar 以点号调用,无 self)
local function makeFakePanel()
    local calls = { open = {}, aggregates = 0 }
    return {
        calls = calls,
        open = function(url) calls.open[#calls.open + 1] = url; return true end,
        showAggregate = function() calls.aggregates = calls.aggregates + 1; return true end,
    }
end

-- 真实仓库布局镜像的 5 个提供者(与 A 段一致,带推断后的 URL)
local function realProviders()
    return {
        { name = "apptoggle", icon = "🔄", cards = {}, pages = { { name = "应用显隐", icon = "🔄", configUrl = "/apptoggle/view/pages/apps/index.html" } } },
        { name = "bingdaily", icon = "🖼️", cards = {}, pages = { { name = "Bing 壁纸", icon = "🖼️", configUrl = "/bingdaily/view/pages/settings/index.html" } } },
        { name = "clipboard", icon = "📋", cards = {}, pages = { { name = "剪贴板", icon = "📋", configUrl = "/clipboard/view/pages/settings/index.html" } } },
        { name = "quantumwindow", icon = "🪟", cards = {}, pages = { { name = "窗口管理", icon = "🪟", configUrl = "/quantumwindow/view/pages/settings/index.html" } } },
        { name = "stayawake", icon = "🌙", cards = {}, pages = { { name = "防睡眠", icon = "🌙", configUrl = "/stayawake/view/pages/control/index.html" } } },
    }
end

-- C.1 启动:创建常驻菜单栏(setTitle emoji + setMenu 传函数)
do
    local m = newMenubar()
    m.setup({ sources = makeFakeSources({}), panel = makeFakePanel() })
    m.start()
    check("E1 menubar.new(true) 全局菜单栏", #barCalls.created == 1 and barCalls.created[1] == true)
    check("E2 菜单栏标题为 emoji 🛠", #barCalls.titles == 1 and barCalls.titles[1] == "🛠")
    check("E3 setMenu 传函数(每次打开菜单重建)", fakeBar ~= nil and type(fakeBar._menu) == "function")
end

-- C.2 降级:扫描抛错且无缓存 → 菜单保留固定三项,不抛错
do
    local m = newMenubar()
    local fake = makeFakeSources({}, true)
    fake.get = function() error("no cache") end
    m.setup({ sources = fake, panel = makeFakePanel() })
    local menu = m.buildMenu()
    check("E4 扫描失败不抛错(菜单可构建)", type(menu) == "table")
    check("E5 降级保留「打开控制中心」", findItem(menu, "打开控制中心") ~= nil)
    check("E6 降级保留「重载 Hammerspoon」", findItem(menu, "重载 Hammerspoon") ~= nil)
    check("E7 降级保留「退出 Hammerspoon」", findItem(menu, "退出 Hammerspoon") ~= nil)
    check("E8 降级结构:4 项,分隔线位于 2", #menu == 4 and menu[2].title == "-",
        tostring(#menu))
end

-- C.3 降级:扫描结果为空表 → 同上固定三项
do
    local m = newMenubar()
    m.setup({ sources = makeFakeSources({}), panel = makeFakePanel() })
    local menu = m.buildMenu()
    check("E9 空结果保留固定三项", findItem(menu, "打开控制中心") ~= nil
        and findItem(menu, "重载 Hammerspoon") ~= nil and findItem(menu, "退出 Hammerspoon") ~= nil)
    check("E10 空结果无 provider 项(仅 4 项)", #menu == 4, tostring(#menu))
end

-- C.4 完整结构:聚合页 + 各 Spoon 入口(子菜单/单项/禁用)+ 重载/退出
do
    local m = newMenubar()
    local panel = makeFakePanel()
    m.setup({ sources = makeFakeSources({
        { name = "apptoggle", icon = "🔄", cards = {}, pages = { { name = "应用显隐", icon = "🔄", configUrl = "/apptoggle/view/pages/apps/index.html" } } },
        { name = "stayawake", icon = "🌙", cards = {}, pages = { { name = "防睡眠", icon = "🌙", configUrl = "/stayawake/view/pages/control/index.html" } } },
        { name = "nopages", icon = "⚙️", cards = { { key = "设置", kind = "page", icon = "🎛️", url = "/nopages/view/pages/settings/index.html" } }, pages = {} },
        { name = "nothing", icon = "🔒" },
        { name = "plain", cards = {} },
    }), panel = panel })
    local menu = m.buildMenu()
    -- 固定骨架:①聚合页 ②分隔线 ... ④分隔线 ⑤重载 ⑥退出
    check("E11 首项为「打开控制中心」", menu[1] and menu[1].title == "打开控制中心")
    check("E12 分隔线在 2/8", menu[2].title == "-" and menu[8].title == "-", tostring(menu[8] and menu[8].title))
    check("E13 末两项为重载/退出", menu[9].title == "重载 Hammerspoon" and menu[10].title == "退出 Hammerspoon")
    -- 有 pages → 子菜单
    local at = findItem(menu, "🔄 apptoggle")
    check("E14 pages provider 建子菜单", at ~= nil and type(at.menu) == "table" and #at.menu == 1)
    check("E15 子菜单项带 name+icon", at and at.menu[1].title == "🔄 应用显隐")
    -- 点击子菜单项 → panel.open(configUrl)
    at.menu[1].fn()
    check("E16 点击子菜单项打开配置页 URL", #panel.calls.open == 1
        and panel.calls.open[1] == "/apptoggle/view/pages/apps/index.html", panel.calls.open[1] or "nil")
    -- 无 pages 但有 page 卡 → 单项
    local np = findItem(menu, "🎛️ 设置")
    check("E17 无 pages 有 page 卡建单项", np ~= nil and type(np.fn) == "function")
    np.fn()
    check("E18 单项点击打开卡片 url", #panel.calls.open == 2
        and panel.calls.open[2] == "/nopages/view/pages/settings/index.html", panel.calls.open[2] or "nil")
    -- 两者皆无 → 禁用项
    check("E19 无 pages 无 page 卡显示禁用项", findItem(menu, "🔒 nothing") ~= nil
        and findItem(menu, "🔒 nothing").disabled == true)
    check("E20 空 cards 也显示禁用项(无 icon 前缀)", findItem(menu, "plain") ~= nil
        and findItem(menu, "plain").disabled == true)
    -- 点击聚合页/重载/退出
    menu[1].fn()
    check("E21 点击「打开控制中心」→ showAggregate", panel.calls.aggregates == 1)
    menu[9].fn()
    check("E22 点击「重载 Hammerspoon」→ hs.reload", hsCalls.reloads == 1)
    menu[10].fn()
    check("E23 点击「退出 Hammerspoon」→ hs.exit", hsCalls.exits == 1)
end

-- C.5 pages 全为搜索页(无 configUrl)→ 降级禁用项
do
    local m = newMenubar()
    m.setup({ sources = makeFakeSources({
        { name = "searchonly", pages = { { name = "搜索", searchUrl = "/searchonly/view/pages/search/index.html" } } },
    }), panel = makeFakePanel() })
    local menu = m.buildMenu()
    local so = findItem(menu, "searchonly")
    check("E24 仅搜索页的 provider 显示禁用项", so ~= nil and so.disabled == true)
end

-- C.6 多个 page 卡:各建单项
do
    local m = newMenubar()
    local panel = makeFakePanel()
    m.setup({ sources = makeFakeSources({
        { name = "multipage", cards = {
            { key = "页一", kind = "page", url = "/multipage/view/pages/one/index.html" },
            { key = "页二", kind = "page", icon = "②", url = "/multipage/view/pages/two/index.html" },
        } },
    }), panel = panel })
    local menu = m.buildMenu()
    local it1 = findItem(menu, "页一")
    local it2 = findItem(menu, "② 页二")
    check("E25 多个 page 卡各建单项", it1 ~= nil and it2 ~= nil)
    it1.fn(); it2.fn()
    check("E26 各单项打开对应卡片 url", #panel.calls.open == 2
        and panel.calls.open[1] == "/multipage/view/pages/one/index.html"
        and panel.calls.open[2] == "/multipage/view/pages/two/index.html")
end

-- C.7 数据新鲜:每次构建(打开菜单)都重新扫描
do
    local m = newMenubar()
    local src = makeFakeSources({})
    local scans = 0
    local origScan = src.scan
    src.scan = function() scans = scans + 1; return origScan() end
    m.setup({ sources = src, panel = makeFakePanel() })
    m.start()
    check("E27 setMenu 函数每次调用都重新扫描(1)", scans == 0)
    fakeBar._menu()
    check("E28 打开菜单触发重扫(2)", scans == 1, tostring(scans))
    fakeBar._menu()
    check("E29 再次打开再次重扫(3)", scans == 2, tostring(scans))
end

-- C.8 扫描失败 → 回退缓存(缓存仍展示,固定项保留)
do
    local m = newMenubar()
    local fake = makeFakeSources({ { name = "cached" } }, true)  -- scan 抛错,get 有缓存
    m.setup({ sources = fake, panel = makeFakePanel() })
    local menu = m.buildMenu()
    check("E30 扫描失败回退缓存展示 provider", findItem(menu, "cached") ~= nil
        and findItem(menu, "cached").disabled == true)
    check("E31 回退缓存时固定三项仍保留", findItem(menu, "打开控制中心") ~= nil
        and findItem(menu, "重载 Hammerspoon") ~= nil and findItem(menu, "退出 Hammerspoon") ~= nil)
end

-- C.9 setup 注入 aggregateUrl → 内部 panel.setup 被调用(聚合页可达)
do
    local m = newMenubar()
    local panel = { setups = {} }
    panel.open = function() return true end
    panel.showAggregate = function() return true end
    panel.setup = function(opts) panel.setups[#panel.setups + 1] = opts end
    m.setup({ sources = makeFakeSources({}), panel = panel, aggregateUrl = "http://127.0.0.1:8821/cc/view/pages/aggregate/index.html" })
    check("E32 aggregateUrl 透传给内部 panel.setup", #panel.setups == 1
        and panel.setups[1].aggregateUrl == "http://127.0.0.1:8821/cc/view/pages/aggregate/index.html")
end

-- C.10 幂等:重复 start 不重建;stop 移除后可重建
do
    local m = newMenubar()
    m.setup({ sources = makeFakeSources({}), panel = makeFakePanel() })
    m.start()
    m.start()
    check("E33 重复 start 幂等(不重建)", #barCalls.created == 1, tostring(#barCalls.created))
    m.stop()
    check("E34 stop 移除菜单栏", barCalls.removes == 1)
    m.start()
    check("E35 stop 后可重建", #barCalls.created == 2, tostring(#barCalls.created))
end

-- C.11 自定义标题
do
    local m = newMenubar()
    m.setup({ sources = makeFakeSources({}), panel = makeFakePanel(), title = "⚙️" })
    m.start()
    check("E36 setup 可自定义标题", #barCalls.titles == 1 and barCalls.titles[1] == "⚙️")
end

-- C.12 集成:不注入依赖,menubar 经 dofile 加载真实 sources/panel,
--     真实扫描(5-Spoon 布局)→ 5 个子菜单;点击配置入口 → 真实 panel.open 建 webview
do
    local m = newMenubar()  -- 未 setup,走默认兄弟模块加载
    hs.configdir = tmpRoot  -- A 段的 5-Spoon 真实布局(_mockFS 仍就位)
    local menu = m.buildMenu()
    check("E37 真实扫描出 5 个 provider 子菜单", findItem(menu, "apptoggle") ~= nil
        and findItem(menu, "stayawake") ~= nil and findItem(menu, "clipboard") ~= nil
        and findItem(menu, "quantumwindow") ~= nil and findItem(menu, "bingdaily") ~= nil)
    check("E38 菜单总项数=10(2 固定+5 provider+2 分隔+重载/退出)", #menu == 10, tostring(#menu))
    -- 每个 provider 子菜单 1 个配置页(真实 manifest 无 provider 级 icon,子菜单标题纯名字)
    local bd = findItem(menu, "bingdaily")
    check("E39 子菜单含配置页(icon+name)", bd and bd.menu and #bd.menu == 1 and bd.menu[1].title == "🖼️ Bing 壁纸")
    -- 点击配置页 → 真实 panel.open → 惰性创建 webview(首载 url=配置页)
    bd.menu[1].fn()
    check("E40 点击配置入口经 panel 打开配置页 URL", #W.created == 1
        and W.created[1].url == "/bingdaily/view/pages/settings/index.html",
        W.created[1] and W.created[1].url or "nil")
    -- 再点另一个 provider 的配置页 → setUrl 切换(同一 webview)
    local sa = findItem(menu, "stayawake")
    sa.menu[1].fn()
    check("E41 切换配置页走 setUrl(同一 webview 单例)", #W.created == 1
        and W.view:raw() ~= nil and W.view:raw():url() == "/stayawake/view/pages/control/index.html",
        W.view and W.view:raw() and W.view:raw():url() or "nil")
end

-- =========================================================
-- 汇总
-- =========================================================
print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)

-- ControlCenter 纯 Lua 单元测试（lua5.4/lua5.5 运行，mock 掉 hs.* 的 IO 部分）
-- 运行：lua core/control-center/test/unit_test.lua
-- 覆盖：sources.scan() 目录发现（hs.fs.dir 双返回值 state 陷阱）、manifest 提取
--       （name/cards/pages + config_pages 老字段兼容）、页面 URL 简写推断、
--       同名 provider 去重覆盖、异常 manifest/目录容错、get() 缓存。

-- =========================================================
-- 测试框架
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

-- 按名取提供者（扫描顺序依赖 hs.fs.dir，按名断言最稳）
local function findProv(list, name)
    for _, p in ipairs(list) do
        if p.name == name then return p end
    end
    return nil
end

-- =========================================================
-- Mock hs + core.hsutil（只 mock sources.lua 用到的部分）
-- =========================================================
-- 文件系统 mock 数据：目录表 + 文件表，由 hs.fs 的 mock 消费
_mockFS = { dirs = {}, files = {} }

hs = {
    logger = { new = function() return { i=function()end,w=function()end,e=function()end,f=function()end,wf=function()end,ef=function()end,df=function()end } end },
    configdir = "",
    fs = {
        -- 模拟 HS 1.1.1：hs.fs.dir 返回 (iteratorFn, dirUserdata) 两个值，
        -- dirUserdata 是 for 循环的 state；迭代器校验 state 参数，缺 state（如被
        -- pcall 丢掉）时报错，与真实 HS 行为一致（"directory metatable expected"）。
        -- 未知目录直接报错（与真实 HS 一致），验证模块的 pcall 单目录容错。
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
    },
}

-- mock core.hsutil（sources.lua require 到的部分：log + path）
package.loaded["core.hsutil"] = {
    log = { new = function() return {
        i = function() end, w = function() end, e = function() end,
        f = function() end, d = function() end,
        wf = function() end, ef = function() end, df = function() end,
    } end },
    path = { join = function(a, b) return a .. "/" .. b end },
}

-- 定位本文件目录（source 形如 core/control-center/test/unit_test.lua）
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.-)[/\\]test[/\\]") or "")
if ROOT == "" then ROOT = "core/control-center/" end
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
local sources = dofile(ROOT .. "internal/sources.lua")

-- =========================================================
-- 工具：构造真实临时目录结构（dofile 需要真实文件；_mockFS 供 mock fs 消费）
-- =========================================================
local function mkdir(p)
    os.execute('mkdir -p "' .. p .. '"')
end
local function writeFile(p, content)
    local f = io.open(p, "w")
    f:write(content)
    f:close()
end
-- 注册一个提供者：真实目录 + 文件 + _mockFS 目录表/文件表
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
-- A. 真实仓库布局镜像：5 个 Spoon + core/{hsutil,launcher/template}
--    （与 launcher 实际合并结果一致：5 个提供者；template 在 core/*/ 二层，
--      与 launcher 一样不会被一级扫描发现，且其 cards 为空，无可见贡献）
-- =========================================================
local tmpRoot = os.tmpname()
os.remove(tmpRoot)
mkdir(tmpRoot .. "/Spoons")
mkdir(tmpRoot .. "/core/hsutil")
mkdir(tmpRoot .. "/core/launcher/template")
-- 5 个 Spoon（manifest 内容与仓库真实文件一致）
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
-- 干扰项：点文件、无 manifest 的目录、core 二层 template（不应被发现）
writeFile(tmpRoot .. "/Spoons/.DS_Store", "")
_mockFS.files[tmpRoot .. "/Spoons/.DS_Store"] = true
_mockFS.dirs[tmpRoot .. "/Spoons/NotASpoon"] = {}
_mockFS.dirs[tmpRoot .. "/core/hsutil"] = {}
_mockFS.dirs[tmpRoot .. "/core/launcher"] = { "template" }
_mockFS.dirs[tmpRoot .. "/core/launcher/template"] = {}
addProvider(tmpRoot, "core/launcher/template", [[
-- 模板：cards 全注释（空贡献），且位于 core/*/ 二层不会被一级扫描发现
return {
    name = "myspoon",
    cards = {},
}
]])
-- 顶层目录表
_mockFS.dirs[tmpRoot .. "/Spoons"] = { "AppToggle.spoon", "BingDaily.spoon", "Clipboard.spoon", ".DS_Store", "NotASpoon", "QuantumWindow.spoon", "StayAwake.spoon" }
_mockFS.dirs[tmpRoot .. "/core"] = { "hsutil", "launcher" }

-- 默认扫描（hs.configdir 指向 tmpRoot，走 scan() 无参默认目录）
hs.configdir = tmpRoot
local listA = sources.scan()

check("A1 默认扫描返回 5 个提供者", #listA == 5, tostring(#listA))
check("A2 提供者名齐全", findProv(listA, "apptoggle") ~= nil and findProv(listA, "bingdaily") ~= nil
    and findProv(listA, "clipboard") ~= nil and findProv(listA, "quantumwindow") ~= nil
    and findProv(listA, "stayawake") ~= nil)
check("A3 core/launcher/template 未被扫描（二层，与 launcher 一致）", findProv(listA, "myspoon") == nil)

-- AppToggle：卡片 + 页面 URL 简写推断
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

-- Clipboard：search 页推断
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
-- B. 边界：scan(dirs) 显式目录 + 异常容错
-- =========================================================
local tmpRoot2 = os.tmpname()
os.remove(tmpRoot2)
mkdir(tmpRoot2 .. "/Spoons")
mkdir(tmpRoot2 .. "/core/hsutil")
mkdir(tmpRoot2 .. "/core/dupe")

-- 无 name 字段：回退目录名；openurl 完整 URL 原样透传
addProvider(tmpRoot2, "Spoons/NoName.spoon", [[
return {
    cards = {
        ["官网"] = { description = "打开官网", kind = "openurl", url = "https://example.com/search?q=x" },
    },
}
]])
-- config_pages 老字段：仅老字段也可出页面
addProvider(tmpRoot2, "Spoons/ConfigPages.spoon", [[
return {
    name = "configpages",
    config_pages = {
        { name = "旧配置", icon = "⚙️", url = "legacy" },
    },
}
]])
-- pages 与 config_pages 同名：新字段优先，老字段跳过
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
-- 非法 manifest：非 table / 加载抛错 → 跳过不崩溃
addProvider(tmpRoot2, "Spoons/ZBad.spoon", "return 42")
addProvider(tmpRoot2, "Spoons/ZBroken.spoon", 'error("boom")')
-- 同名 provider 去重覆盖：core 后扫，覆盖 Spoons 同名提供者
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
-- 干扰项：点文件、无 manifest 目录
writeFile(tmpRoot2 .. "/Spoons/.DS_Store", "")
_mockFS.files[tmpRoot2 .. "/Spoons/.DS_Store"] = true
_mockFS.dirs[tmpRoot2 .. "/Spoons/Empty.spoon"] = {}
_mockFS.dirs[tmpRoot2 .. "/core/hsutil"] = {}
_mockFS.dirs[tmpRoot2 .. "/Spoons"] = { "NoName.spoon", "ConfigPages.spoon", "BothPages.spoon", "ZBad.spoon", "ZBroken.spoon", "DupeA.spoon", ".DS_Store", "Empty.spoon" }
_mockFS.dirs[tmpRoot2 .. "/core"] = { "dupe", "hsutil" }

-- 显式传目录（含一个不存在的目录，验证 pcall 单目录容错）
local listB = sources.scan({ tmpRoot2 .. "/Spoons", tmpRoot2 .. "/Nope", tmpRoot2 .. "/core" })
-- 4 个提供者：NoName.spoon/configpages/bothpages/dupeme（ZBad/ZBroken/Empty/点文件被跳过）
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
-- 同名覆盖：core/dupe 后扫覆盖 Spoons/DupeA.spoon
local dm = findProv(listB, "dupeme")
check("B10 同名 provider 去重为 1 个", dm ~= nil)
local dmCount = 0
for _, p in ipairs(listB) do if p.name == "dupeme" then dmCount = dmCount + 1 end end
check("B11 dupeme 全局唯一", dmCount == 1, tostring(dmCount))
check("B12 后扫描者覆盖（卡片=后扫描卡片）", dm and #dm.cards == 1 and dm.cards[1].key == "后扫描卡片"
    and dm.cards[1].url == "/dupeme/view/pages/b/index.html",
    dm and dm.cards[1] and tostring(dm.cards[1].key))

-- =========================================================
-- C. 只读零侵入：manifest 文件未被改写，源表未被污染
-- =========================================================
local f = io.open(tmpRoot .. "/Spoons/AppToggle.spoon/launcher-commands.lua", "r")
local contentA = f:read("*a"); f:close()
check("C1 manifest 文件未被改写", contentA:find("一键显隐应用", 1, true) ~= nil
    and contentA:find("url = \"apps\"", 1, true) ~= nil)
check("C2 原 manifest 表未被修改（url 推断生成新表）",
    findProv(listA, "apptoggle").cards[1].url == "/apptoggle/view/pages/apps/index.html"
    and contentA:find("url = \"apps\"", 1, true) ~= nil)

-- =========================================================
-- 汇总
-- =========================================================
print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)

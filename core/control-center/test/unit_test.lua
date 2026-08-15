-- ControlCenter 纯 Lua 单元测试（lua5.4/lua5.5 运行，mock 掉 hs.* 与 core.hsutil 的 IO 部分）
-- 运行：lua core/control-center/test/unit_test.lua
-- 覆盖：
--   A/B/C sources.scan()：目录发现（hs.fs.dir 双返回值 state 陷阱）、manifest 提取
--       （name/cards/pages + config_pages 老字段兼容）、页面 URL 简写推断、
--       同名 provider 去重覆盖、异常 manifest/目录容错、get() 缓存、只读零侵入
--   D panel：惰性单例首载 / setUrl 切换 / 同 URL 仅 show / showAggregate /
--       返回 shim 注入时机（导航完成检测）与内容 / teardown 停止轮询
--   E api：路由注册（providers/open/close + 静态挂载）、参数校验 400、pcall 容错 500

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
-- Mock 状态（panel/api 用例共享；每个用例前 resetMocks）
-- =========================================================
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

local function makeLogger()
    return { i = function() end, w = function() end, e = function() end,
             f = function() end, wf = function() end, ef = function() end, df = function() end }
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

-- =========================================================
-- Mock hs + core.hsutil（合并：sources 用 fs/path/log；panel 用 timer/screen/webview/json）
-- =========================================================
-- 文件系统 mock 数据：目录表 + 文件表，由 hs.fs 的 mock 消费
_mockFS = { dirs = {}, files = {} }

hs = {
    logger = { new = function() return makeLogger() end },
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
    screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end },
    timer = {
        doEvery = function(_, cb)
            M.lastTimerCb = cb
            return { stop = function() M.timerStopped = true end }
        end,
    },
}

-- =========================================================
-- 最小 JSON 编解码（测试基础设施：mock http 请求/响应用）
-- =========================================================
local function jsonEncode(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v then return "null" end -- NaN
        return tostring(v)
    end
    if t == "string" then
        return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
            local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
            if map[c] then return map[c] end
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    if t == "table" then
        -- 数组判定：连续 1..n 整数键
        local n, isArr = 0, true
        for k in pairs(v) do
            if type(k) ~= "number" or k < 1 or k ~= n + 1 then isArr = false; break end
            n = n + 1
        end
        local parts = {}
        if isArr and n > 0 then
            for i = 1, n do parts[i] = jsonEncode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        -- 空表/对象
        for k, val in pairs(v) do
            if type(k) == "string" then
                parts[#parts + 1] = jsonEncode(k) .. ":" .. jsonEncode(val)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function jsonDecode(s)
    if type(s) ~= "string" then return nil end
    local pos, len = 1, #s
    local function skip()
        while pos <= len do
            local c = s:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1 else break end
        end
    end
    local function parseString()
        pos = pos + 1 -- 跳过开引号
        local out = {}
        while pos <= len do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                local plain = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['/'] = "/", ["\\"] = "\\", ['"'] = '"' }
                if plain[e] then out[#out + 1] = plain[e]; pos = pos + 2
                elseif e == "u" then
                    -- BMP 直转 UTF-8（测试用最小实现；不处理代理对）
                    local code = tonumber(s:sub(pos + 2, pos + 5), 16) or 0
                    if code < 0x80 then out[#out + 1] = string.char(code)
                    elseif code < 0x800 then
                        out[#out + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
                    else
                        out[#out + 1] = string.char(0xE0 + math.floor(code / 0x1000),
                            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
                    end
                    pos = pos + 6
                else pos = pos + 2 end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return nil
    end
    local function parseValue()
        skip()
        local c = s:sub(pos, pos)
        if c == '"' then return parseString() end
        if c == "{" then
            pos = pos + 1
            local obj = {}
            skip()
            if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
            while true do
                skip()
                if s:sub(pos, pos) ~= '"' then return nil end
                local k = parseString()
                skip()
                if s:sub(pos, pos) ~= ":" then return nil end
                pos = pos + 1
                obj[k] = parseValue()
                skip()
                local sep = s:sub(pos, pos)
                if sep == "}" then pos = pos + 1; return obj end
                if sep ~= "," then return nil end
                pos = pos + 1
            end
        end
        if c == "[" then
            pos = pos + 1
            local arr = {}
            skip()
            if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
            local i = 1
            while true do
                arr[i] = parseValue()
                i = i + 1
                skip()
                local sep = s:sub(pos, pos)
                if sep == "]" then pos = pos + 1; return arr end
                if sep ~= "," then return nil end
                pos = pos + 1
            end
        end
        if c == "t" then if s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end return nil end
        if c == "f" then if s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end return nil end
        if c == "n" then if s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end return nil end
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if num and num ~= "" then pos = pos + #num; return tonumber(num) end
        return nil
    end
    local ok, v = pcall(parseValue)
    if not ok then return nil end
    return v
end

-- =========================================================
-- Mock HTTP app（api.lua 路由记录 + 分发，模拟 HSUtil.http.app）
-- =========================================================
local mockRoutes = {}   -- { method=, pattern=, handler= }
local mockStatic = {}   -- { prefix=, root= }
local mockApp = {}
for _, m in ipairs({ "get", "post", "put", "delete", "patch", "head", "options" }) do
    mockApp[m] = function(_, pattern, handler)
        mockRoutes[#mockRoutes + 1] = { method = m:upper(), pattern = pattern, handler = handler }
        return mockApp
    end
end
function mockApp:static(prefix, root)
    mockStatic[#mockStatic + 1] = { prefix = prefix, root = root }
    return mockApp
end

-- 与真实 router.compilePath 相同的路径编译（:param 支持）
local function compilePath(pattern)
    local regex = pattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    regex = regex:gsub("(:[%w_]+)", "([^/]+)")
    return "^" .. regex .. "$"
end

-- 分发一个请求到 mock 路由（返回 body, code, headers；未命中 404）
local function dispatch(method, path, headers, body)
    local clean = path:match("^([^?]*)") or path
    local req = {
        method = method,
        path = clean,
        headers = headers or {},
        body = body or "",
        query = {},
        params = {},
        json = function(self) return jsonDecode(self.body) end,
    }
    local res = {
        _code = 200,
        _body = "",
        _headers = {},
        status = function(self, c) self._code = c; return self end,
        header = function(self, k, v) self._headers[k] = v; return self end,
        body = function(self, s) self._body = s or ""; return self end,
        text = function(self, s) self._body = s or ""; return self end,
        html = function(self, s) self._body = s or ""; return self end,
        json = function(self, v)
            self._body = jsonEncode(v)
            self._headers["Content-Type"] = "application/json; charset=utf-8"
            return self
        end,
        error = function(self, code, msg)
            self._code = code
            self._body = jsonEncode({ err = msg })
            self._headers["Content-Type"] = "application/json; charset=utf-8"
            return self
        end,
    }
    for _, r in ipairs(mockRoutes) do
        if r.method == method and clean:match(compilePath(r.pattern)) then
            r.handler(req, res)
            return res._body, res._code, res._headers
        end
    end
    return nil, 404
end

-- mock core.hsutil（sources/panel/api require 到的部分）
package.loaded["core.hsutil"] = {
    log = { new = function() return makeLogger() end },
    path = { join = function(a, b) return a .. "/" .. b end },
    webview = {
        new = function(opts)
            M.created[#M.created + 1] = opts
            M.view = newFakeView(opts)
            return M.view
        end,
    },
    json = { encode = function(v) return jsonEncode(v) end },
    http = { app = mockApp },
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
-- D. panel.lua：配置面板单例 + 返回 shim
-- =========================================================
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
-- E. api.lua：路由注册（providers/open/close + 静态挂载）+ 参数校验 + pcall 容错
-- =========================================================
-- dofile api.lua 一次（模块加载时捕获 HSUtil.http.app = mockApp）
local api = dofile(ROOT .. "internal/api.lua")

-- 与 sources.scan() 输出同构的提供者数据（name/icon/cards/pages，含 configUrl/searchUrl）
local apiProviders = {
    {
        name = "apptoggle", icon = "🔄",
        cards = {
            { key = "应用显隐", description = "一键显隐应用（全局热键 + 布局锁定）", icon = "🔄", kind = "page", url = "/apptoggle/view/pages/apps/index.html" },
        },
        pages = {
            { name = "应用显隐", icon = "🔄", configUrl = "/apptoggle/view/pages/apps/index.html" },
        },
    },
    {
        name = "bingdaily",
        cards = {},
        pages = {
            { name = "Bing 壁纸", icon = "🖼️", configUrl = "/bingdaily/view/pages/settings/index.html", searchUrl = "/bingdaily/view/pages/search/index.html" },
        },
    },
}

-- fake 模块：记录调用 + 可注入故障（验证 pcall 容错）
local openedUrls = {}
local hideCalls = 0
local failOpen, failHide, failGet = false, false, false
local fakePanelMod = {
    open = function(url)
        if failOpen then error("panel.open boom") end
        openedUrls[#openedUrls + 1] = url
        return true
    end,
    hide = function()
        if failHide then error("panel.hide boom") end
        hideCalls = hideCalls + 1
    end,
}
local fakeSourcesMod = {
    get = function()
        if failGet then error("sources.get boom") end
        return apiProviders
    end,
}

local VIEWS = "/tmp/cc-views"
api.setup(fakeSourcesMod, fakePanelMod, VIEWS)

-- 注册面
check("E1 静态挂载 /control-center/view", #mockStatic == 1
    and mockStatic[1].prefix == "/control-center/view" and mockStatic[1].root == VIEWS)
check("E2 三个路由已注册（providers/open/close）", #mockRoutes == 3)
local allCCOk = true
for _, r in ipairs(mockRoutes) do
    if r.pattern:sub(1, 18) ~= "/control-center/api/" then allCCOk = false end
end
check("E3 路由全部挂在 /control-center/api 前缀（与 /launcher、/stayawake 命名空间无冲突）", allCCOk)

-- GET providers
local body, code = dispatch("GET", "/control-center/api/providers")
local providersBody = jsonDecode(body)
check("E4 providers 返回 200 合法 JSON", code == 200 and type(providersBody) == "table", tostring(code))
check("E5 providers 数量与数据源一致", providersBody and #providersBody.providers == 2, providersBody and tostring(#providersBody.providers))
local atj = providersBody and providersBody.providers[1]
check("E6 提供者 name/icon 透传", atj and atj.name == "apptoggle" and atj.icon == "🔄")
check("E7 卡片字段透传（key/url）", atj and atj.cards[1].key == "应用显隐"
    and atj.cards[1].url == "/apptoggle/view/pages/apps/index.html")
check("E8 页面 configUrl/searchUrl 透传", atj and atj.pages[1].configUrl == "/apptoggle/view/pages/apps/index.html")
local bdj = providersBody and providersBody.providers[2]
check("E9 searchUrl 透传（bingdaily）", bdj and bdj.pages[1].searchUrl == "/bingdaily/view/pages/search/index.html")

-- GET providers 故障 → 500
failGet = true
local _, codeFail = dispatch("GET", "/control-center/api/providers")
check("E10 sources.get 抛错 → 500 + err", codeFail == 500)
failGet = false

-- POST open
local P_URL = "http://127.0.0.1:8821/stayawake/view/pages/control/index.html"
local ob, oc = dispatch("POST", "/control-center/api/open", {}, jsonEncode({ url = P_URL }))
local oj = jsonDecode(ob)
check("E11 open 带 url → 200 {ok:true}", oc == 200 and oj and oj.ok == true, tostring(oc))
check("E12 open 调用 panel.open(url)", #openedUrls == 1 and openedUrls[1] == P_URL, tostring(#openedUrls))

-- POST open 参数校验 → 400
local _, cNoBody = dispatch("POST", "/control-center/api/open")
check("E13 open 缺 body → 400", cNoBody == 400, tostring(cNoBody))
local _, cNoUrl = dispatch("POST", "/control-center/api/open", {}, jsonEncode({}))
check("E14 open 缺 url → 400", cNoUrl == 400, tostring(cNoUrl))
local _, cBadType = dispatch("POST", "/control-center/api/open", {}, jsonEncode({ url = 123 }))
check("E15 open url 非字符串 → 400", cBadType == 400, tostring(cBadType))
local _, cEmpty = dispatch("POST", "/control-center/api/open", {}, jsonEncode({ url = "" }))
check("E16 open url 空串 → 400", cEmpty == 400, tostring(cEmpty))
local _, cBadJson = dispatch("POST", "/control-center/api/open", {}, "not-json{")
check("E17 open body 非法 JSON → 400", cBadJson == 400, tostring(cBadJson))
check("E18 校验失败不触发 panel.open", #openedUrls == 1)

-- POST open 故障 → 500
failOpen = true
local _, cOpenFail = dispatch("POST", "/control-center/api/open", {}, jsonEncode({ url = P_URL }))
check("E19 panel.open 抛错 → 500 + err", cOpenFail == 500, tostring(cOpenFail))
failOpen = false

-- POST close
local cb_, cc = dispatch("POST", "/control-center/api/close")
local cj = jsonDecode(cb_)
check("E20 close → 200 {ok:true}", cc == 200 and cj and cj.ok == true, tostring(cc))
check("E21 close 调用 panel.hide", hideCalls == 1, tostring(hideCalls))

-- POST close 故障 → 500
failHide = true
local _, cCloseFail = dispatch("POST", "/control-center/api/close")
check("E22 panel.hide 抛错 → 500 + err", cCloseFail == 500, tostring(cCloseFail))
failHide = false

-- 与既有路由无冲突：未注册的路径不被命中
local _, cOther = dispatch("GET", "/launcher/api/query")
check("E23 未注册路径（/launcher/api/query）→ 404", cOther == 404, tostring(cOther))

-- =========================================================
-- 汇总
-- =========================================================
print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)

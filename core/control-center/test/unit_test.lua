-- ControlCenter panel 纯 Lua 单元测试(lua5.5 运行,mock 掉 hs.* 与 core.hsutil)
-- 运行:  lua core/control-center/test/unit_test.lua
-- 覆盖:  惰性单例首载 / setUrl 切换 / 同 URL 仅 show / showAggregate /
--        返回 shim 注入时机(导航完成检测)与内容 / teardown 停止轮询
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

-- =========================================================
-- Mock 状态
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

-- =========================================================
-- Mock core.hsutil
-- =========================================================
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
local PANEL_PATH = (debug.getinfo(1, "S").source:sub(2):match("^(.-[/\\])test[/\\]") or "./")
    .. "internal/panel.lua"
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

-- =========================================================
-- 用例
-- =========================================================

-- 1) 首次 open:惰性创建,首载 URL 透传,show 触发
do
    local panel = newPanel()
    local ok = panel.open(P1)
    check("open 返回 true", ok == true)
    check("单例以首载 url 创建", #M.created == 1 and M.created[1].url == P1)
    check("尺寸比例同 launcher(0.52/0.62/0.22)",
        M.created[1].widthRatio == 0.52 and M.created[1].heightRatio == 0.62 and M.created[1].yRatio == 0.22)
    check("首次 show 后底层 webview 已建且指向首载 url",
        M.view:raw() ~= nil and M.view:raw():url() == P1)
    check("面板可见", panel.visible() == true)
end

-- 2) 已创建且 url 不同:setUrl 切换后 show
do
    local panel = newPanel()
    panel.open(P1)
    local ok = panel.open(P2)
    check("open 返回 true", ok == true)
    check("setUrl 切换:底层 url 指向新页", M.view:raw():url() == P2)
    check("同一单例(未新建 webview)", #M.created == 1)
end

-- 3) 已创建且 url 相同:仅 show,不触发 setUrl
do
    local panel = newPanel()
    panel.open(P1)
    tick()   -- 首载完成后注入一次 shim
    check("首载注入一次", #M.evals == 1)
    local evalsBefore = #M.evals
    local ok = panel.open(P1)
    check("open 返回 true", ok == true)
    check("同 URL 不触发导航(底层 url 不变)", M.view:raw():url() == P1)
    tick()
    check("同 URL 页面不重复注入 shim", #M.evals == evalsBefore)
end

-- 4) open 缺 url 且未 setup:忽略不崩
do
    local panel = newPanel()
    check("open(nil) 未 setup 时返回 false", panel.open() == false)
end

-- 5) showAggregate 未 setup:返回 false
do
    local panel = newPanel()
    check("showAggregate 未 setup 返回 false", panel.showAggregate() == false)
end

-- 6) setup 后 showAggregate:切回聚合页 URL
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    panel.showAggregate()
    check("showAggregate setUrl 到聚合页", M.view:raw():url() == AGG)
end

-- 7) shim 注入时机:导航完成(不加载中)才注入,每文档一次
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    check("导航未完成前不注入", #M.evals == 0)
    tick()
    check("导航完成后注入一次", #M.evals == 1)
    tick()
    check("同一文档不重复注入", #M.evals == 1)
    -- 切换新页后再次注入
    panel.open(P2)
    tick()
    check("切换新页后重新注入", #M.evals == 2)
end

-- 8) 加载中不注入,加载完成才注入
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    M.loading = true
    tick()
    check("loading 中不注入", #M.evals == 0)
    M.loading = false
    tick()
    check("加载完成注入", #M.evals == 1)
end

-- 9) shim 内容:closePage / closeStayAwake = 切回聚合页
do
    local panel = newPanel()
    panel.setup({ aggregateUrl = AGG })
    panel.open(P1)
    tick()
    local js = M.evals[1] or ""
    check("shim 定义 window.closePage", js:find("window%.closePage", 1, false) ~= nil)
    check("shim 定义 window.closeStayAwake", js:find("window%.closeStayAwake", 1, false) ~= nil)
    check("shim 目标是聚合页 URL(json 编码)", js:find('agg = "' .. AGG .. '"', 1, false) ~= nil)
    check("shim 幂等标记", js:find("__ccPanelShim", 1, false) ~= nil)
end

-- 10) shim 兜底:未 setup 时注入目标回退为当前页(不崩,不注入 nil)
do
    local panel = newPanel()
    panel.open(P1)
    tick()
    check("未 setup 时 shim 兜底为当前 url", #M.evals == 1 and M.evals[1]:find('agg = "' .. P1 .. '"', 1, false) ~= nil)
end

-- 11) hide / visible 透传
do
    local panel = newPanel()
    panel.open(P1)
    panel.hide()
    check("hide 后不可见", panel.visible() == false)
    panel.open(P1)
    check("再次 open 可见", panel.visible() == true)
end

-- 12) teardown:停止轮询并销毁单例
do
    local panel = newPanel()
    panel.open(P1)
    panel.teardown()
    check("teardown 停止 shim 轮询", M.timerStopped == true)
    check("teardown 后可见性归零", panel.visible() == false)
    -- 重新 open 重建单例
    local ok = panel.open(P1)
    check("teardown 后可重建", ok == true and #M.created == 2)
end

-- =========================================================
-- 汇总
-- =========================================================
print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)

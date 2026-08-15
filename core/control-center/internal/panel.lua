--- ControlCenter.internal.panel
--- 配置面板单例:基于 HSUtil.webview 的惰性 webview。
---
--- 与 launcher 面板共用框架:创建/居中/失焦自动隐藏/Esc 兜底/加载保护全部由
--- HSUtil.webview 承担(零侵入,不改 core/hsutil 任何文件)。本层额外提供:
---   * setUrl 切换 —— open(url) 时 url 与当前加载页不同,先 view:raw():url(newUrl) 再 show
---   * 返回 shim  —— 顶层 webview 中定义 window.closePage / window.closeStayAwake,
---                   使既有 Spoon 配置页零修改即可返回聚合页
---
--- 子页面协议兼容(关键):
---   launcher 中各 Spoon 配置页在 iframe 里打开,返回按钮调 window.parent.closePage()
---   (StayAwake 旧页面兼容别名 parent.closeStayAwake())。本面板把这些页面以顶层 URL
---   打开 —— 顶层 webview 中 parent === window,parent.closePage 恒为 nil,返回即失效。
---   因此每次导航完成(等价 didFinishNavigation)后 evaluateJavaScript 注入 shim:
---   window.closePage = window.closeStayAwake = 切回聚合页(走 location.href)。
---   既有页面零修改即可返回;QuantumWindow 等页面顶层态自带 history.back() 兜底,
---   setUrl 切换会写入 webview 历史,同样能回到聚合页。
---
--- 零侵入实现:导航完成检测不用 navigationCallback(它是 setter-only,HSUtil.webview
--- 内部已占用且无法链式追加),改用同步 getter 轻轮询 ——
---   wv:url() 已指向新文档 且 wv:loading() == false ⟺ 新文档加载完成。
--- 轮询常驻(0.25s/次,仅同步 getter),任何导航(本层 setUrl / shim 的 location.href /
--- 页面 history.back())后都会自动补注 shim;同一文档只注入一次。
local panel = {}

local HSUtil = require("core.hsutil")
local logger = HSUtil.log.new("ControlCenter.panel")

-- ============================================================
-- 单例状态
-- ============================================================
local view = nil         -- HSUtil.webview 单例(惰性:首次 open 创建,内部 webview 首次 show 创建)
local aggregateUrl = nil -- 聚合页 URL(setup 注入;showAggregate 与 shim 的目标)
local size = { widthRatio = 0.7, heightRatio = 0.78, yRatio = 0.1 }  -- 聚合配置页专用：大面板（宽 70% 高 78%）
local shimTimer = nil    -- 导航完成轻轮询
local shimmedUrl = nil   -- 已注入 shim 的文档 URL(每文档只注入一次)

-- shim 注入脚本:%s 为 json 编码的聚合页 URL。
-- 顶层 webview 中 window.parent === window,这里定义的 closePage 即 parent.closePage;
-- 页面从 spoon 配置页切回聚合页(已是聚合页则 no-op,幂等)。
local SHIM_JS_TMPL = [[
(function () {
  var agg = %s;
  function goAggregate() {
    // 优先 history.back()（WKWebView bfcache/缓存页，秒回不重载资源）；
    // setUrl 切换会写入 webview 历史，back 即回到聚合页。
    // 无历史（首次直达/外部打开）才整页跳转。
    if (window.location.href !== agg) {
      if (window.history && window.history.length > 1) {
        window.history.back();
      } else {
        window.location.href = agg;
      }
    }
  }
  // launcher 子页面协议兼容:顶层打开时 parent === window,
  // 既有页面调 parent.closePage() / parent.closeStayAwake() 即可返回聚合页
  window.closePage = goAggregate;
  window.closeStayAwake = goAggregate;
  window.__ccPanelShim = true;
})();
]]

-- ============================================================
-- setup / 单例创建
-- ============================================================

--- ControlCenter.panel.setup(opts)
--- 可选初始化(首次 open 前调用):
---   opts.aggregateUrl      聚合配置页 URL(showAggregate 与返回 shim 的目标;必填)
---   opts.widthRatio        面板宽/目标屏宽 比例,默认 0.7(聚合页大面板)
---   opts.heightRatio       面板高/目标屏高 比例,默认 0.78
---   opts.yRatio            垂直位置(屏高比例),默认 0.1
---   opts.logger            可选日志器
function panel.setup(opts)
    opts = opts or {}
    aggregateUrl = opts.aggregateUrl
    if opts.widthRatio ~= nil then size.widthRatio = opts.widthRatio end
    if opts.heightRatio ~= nil then size.heightRatio = opts.heightRatio end
    if opts.yRatio ~= nil then size.yRatio = opts.yRatio end
    if opts.logger then logger = opts.logger end
    return panel
end

--- 惰性创建单例(仅首次 open 时);底层 hs.webview 由 HSUtil.webview 在首次 show 时创建
local function ensureView(url)
    if view then return view end
    view = HSUtil.webview.new({
        url = url,
        widthRatio = size.widthRatio,
        heightRatio = size.heightRatio,
        yRatio = size.yRatio,
        logger = logger,
        -- 加载失败只记日志,不弹窗打断(与 launcher 面板一致)
        onLoadFail = function(action, err)
            logger.ef("配置面板加载失败: %s %s", action, tostring(err))
        end,
    })
    return view
end

-- ============================================================
-- 返回 shim:导航完成检测 + 注入
-- ============================================================

local function stopShimPolling()
    if shimTimer then
        shimTimer:stop()
        shimTimer = nil
    end
end

--- 常驻轻轮询:文档变化(url() 指向新文档且不再加载)时注入返回 shim,每文档一次。
--- 覆盖所有导航来源:本层 setUrl、shim 自身的 location.href、页面 history.back()。
local function startShimPolling()
    if shimTimer then return end
    shimTimer = hs.timer.doEvery(0.25, function()
        local wv = view and view:raw()
        if not wv then return end
        local okUrl, cur = pcall(function() return wv:url() end)
        if not okUrl or cur == nil or cur == "" or cur == shimmedUrl then return end
        local okLoad, loading = pcall(function() return wv:loading() end)
        if not okLoad or loading then return end
        -- 新文档加载完成(didFinishNavigation 等价时机),注入 shim
        shimmedUrl = cur
        -- 注:不能用 HSUtil.json.encode —— hs.json.encode 只接受 table,直接传字符串会抛错
        -- ("incorrect type 'string' for argument 1 (expected table)")导致注入永远失败;
        -- %q 生成 JS 兼容的字符串字面量(URL 无引号/反斜杠,与 JSON 编码等价)。
        local js = string.format(SHIM_JS_TMPL, string.format("%q", aggregateUrl or cur))
        local ok = pcall(function()
            wv:evaluateJavaScript(js)
        end)
        if not ok then
            logger.wf("返回 shim 注入失败: %s", cur)
        end
    end)
end

-- ============================================================
-- 对外 API
-- ============================================================

--- 相对路径 → 完整 URL（sources.lua 推断的 configUrl 是 /xxx/view/pages/... 相对路径，
--- wv:url() 只接受完整 URL——相对路径会导致 WebKit 101 "URL can't be shown"）
local function absolutize(url)
    if not url then return nil end
    if url:match("^https?://") or url:match("^file://") then return url end
    return HSUtil.http.BASE .. url
end

--- ControlCenter.panel.open(url)
--- 打开配置面板(单例):
---   * 未创建 —— 惰性创建并 show,url 作为首载 URL(由 HSUtil.webview 首次 show 加载)
---   * 已创建且 url 与当前加载页不同 —— view:raw():url(url) setUrl 切换后 show
---   * 已创建且 url 相同 —— 仅 show
--- url 缺省时回退聚合页 URL(setup 注入);相对路径自动补全为完整 URL
function panel.open(url)
    url = absolutize(url or aggregateUrl)
    if not url then
        logger.w("panel.open 缺少 url(未 setup aggregateUrl?),忽略")
        return false
    end

    if not view then
        -- 首次:创建单例,首载 URL 由 HSUtil.webview show() 触发加载
        ensureView(url)
        local ok = view:show()
        startShimPolling()
        return ok
    end

    local wv = view:raw()
    if not wv then
        logger.e("面板 webview 未创建,无法切换 URL")
        return false
    end
    local ok, cur = pcall(function() return wv:url() end)
    if not ok then cur = nil end
    if url ~= cur then
        -- setUrl 切换:先切后 show(面板隐藏时先切好,避免旧页闪现);
        -- 加载完成后的 shim 注入由常驻轮询负责
        local okSet = pcall(function() wv:url(url) end)
        if not okSet then logger.wf("setUrl 切换失败: %s", url) end
    end
    return view:show()
end

--- ControlCenter.panel.showAggregate()
--- 切回聚合配置页 URL(等价 open(aggregateUrl))
function panel.showAggregate()
    return panel.open(aggregateUrl)
end

--- ControlCenter.panel.hide()
--- 隐藏面板(失焦自动隐藏/Esc 兜底由 HSUtil.webview 承担)
function panel.hide()
    if view then view:hide() end
end

--- ControlCenter.panel.visible()
function panel.visible()
    return view ~= nil and view:visible() or false
end

--- ControlCenter.panel.teardown()
--- 销毁面板与轮询(模块 stop 时)
function panel.teardown()
    stopShimPolling()
    shimmedUrl = nil
    if view then view:teardown(); view = nil end
end

return panel

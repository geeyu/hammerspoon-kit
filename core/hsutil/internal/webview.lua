--- HSUtil.internal.webview
--- 面板 webview 生命周期封装。
--- Clipboard / Launcher 面板的公共逻辑收敛：
--- 创建/居中/玻璃样式、首载 URL + 超时保护、失焦自动隐藏、Esc 兜底、
--- 前端 reset JS 钩子（show 时刷新 或 隐藏时刷新 两种策略）、teardown。
---
--- 用法：
---   local view = HSUtil.webview.new({
---       url = "...",                -- 首屏 URL（必填）
---       width = 560, height = 640,  -- 可选，默认主屏 52% x 62%
---       widthRatio = 0.52,          -- 可选，按「目标屏幕」宽的比例（优先于 width）
---       heightRatio = 0.62,         -- 可选，按「目标屏幕」高的比例（优先于 height）
---       yRatio = 0.22,              -- 可选，垂直位置（屏高比例），默认 0.22
---       level = ...,                -- 可选，默认 screenSaver
---       screenFor = fn(),           -- 可选，返回目标屏幕（每次 show 调用）；
---                                  --   缺省主屏。多屏场景让面板跟随鼠标/焦点屏幕
---       repositionOnShow = true,    -- 可选，每次 show 按目标屏幕重算位置（屏幕布局变化不悬空）
---       resetJs = "QW.reload && QW.reload()",  -- 前端刷新钩子（可选）
---       resetOnShow = true,         -- true=每次 show 刷新（Launcher 模式）；
---                                  -- false=隐藏时刷新（Clipboard 模式，下次展示即最新）
---       logger = <hs.logger>,       -- 可选，默认 HSUtil.webview
---       onLoadFail = fn(action, err),  -- 可选；默认 logger.e + hs.alert
---       onTimeout  = fn(),             -- 可选；默认 logger.w（首载 3s 未就绪）
---   })
---   view:show() / view:hide() / view:visible() / view:toggle()
---   view:reset()   -- 主动调前端 resetJs（隐藏态静默刷新等场景）
---   view:resize({ widthRatio=, heightRatio=, yRatio= })  -- 动态调尺寸/位置（设置保存后即时生效）
---   view:teardown()  -- 销毁（stop 时）
---   view:raw()     -- 底层 hs.webview（需要原始对象时）
local webview = {}

local eventtap = require("hs.eventtap")
local event = eventtap.event

local View = {}
View.__index = View

--- 创建面板（未创建 webview，首次 show 时惰性创建）
--- @param opts table 见文件头
function webview.new(opts)
    opts = opts or {}
    assert(opts.url, "HSUtil.webview.new: url 必填")

    local scr = hs.screen.mainScreen():frame()
    return setmetatable({
        _url = opts.url,
        _widthRatio = opts.widthRatio,   -- 比例优先：按目标屏幕 frame 计算，天然适配副屏
        _heightRatio = opts.heightRatio,
        _width = opts.width or math.floor(scr.w * 0.52),
        _height = opts.height or math.floor(scr.h * 0.62),
        _yRatio = opts.yRatio or 0.22,
        _level = opts.level or hs.drawing.windowLevels.screenSaver,
        _screenFor = opts.screenFor,     -- function() -> hs.screen|nil（缺省主屏）
        _repositionOnShow = opts.repositionOnShow == true,
        _resetJs = opts.resetJs,
        _resetOnShow = opts.resetOnShow ~= false,  -- 默认 show 时刷新
        _logger = opts.logger or hs.logger.new("HSUtil.webview", "info"),
        _onLoadFail = opts.onLoadFail,
        _onTimeout = opts.onTimeout,
        _wv = nil,
        _pageReady = false,
        _loadedOnce = false,
        _readyTimer = nil,
        _escTap = nil,
        _navRetries = 0,    -- 导航失败重试计数（懒加载竞态：webview 扩展首次加载时
                            -- WebKit 进程未就绪，立即导航报 didFailProvisionalNavigation(101)，
                            -- 延迟重载即可恢复；最多重试 3 次）
        -- 拖拽状态（标题区拖动面板；见 _ensure 中的 dragTap）
        _drag = { active = false, moved = false, startX = 0, startY = 0, frame = nil, tap = nil },
    }, View)
end

--- 目标屏幕：注入函数优先（pcall 防注入函数抛错），退化主屏
function View:_targetScreen()
    if self._screenFor then
        local ok, scr = pcall(self._screenFor)
        if ok and scr then return scr end
    end
    return hs.screen.mainScreen()
end

--- 计算面板 frame（目标屏幕 + 比例/绝对尺寸 + 越界钳制）。
--- 钳制保证任何屏幕尺寸下面板不越界（竖屏副屏/极小屏安全）。
function View:_frame()
    local scr = self:_targetScreen()
    local f = scr and scr:frame() or hs.screen.mainScreen():frame()
    local w = self._widthRatio and math.floor(f.w * self._widthRatio) or self._width
    local h = self._heightRatio and math.floor(f.h * self._heightRatio) or self._height
    w = math.min(w, math.floor(f.w))
    h = math.min(h, math.floor(f.h))
    local x = math.floor(f.x + (f.w - w) / 2)
    local y = math.floor(f.y + (f.h - h) * self._yRatio)
    return { x = x, y = y, w = w, h = h }
end

function View:_ensure()
    if self._wv then return self._wv end

    local fr = self:_frame()
    local wv = hs.webview.new(fr)
    wv:darkMode(true)
    wv:transparent(true)      -- 圆角玻璃露出桌面
    wv:allowTextEntry(true)
    wv:shadow(true)
    wv:level(self._level)

    wv:navigationCallback(function(action, _, _, err)
        if action == "didFinishNavigation" then
            self._pageReady = true
            self._navRetries = 0   -- 成功加载：重置重试计数
            if self._readyTimer then self._readyTimer:stop(); self._readyTimer = nil end
        elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
            self._pageReady = false
            -- 懒加载竞态自动重试：webview 扩展首次加载时 WebKit 进程未就绪，
            -- 立即导航会报 WebKit 101（URL can't be shown）；延迟 0.4s 重载通常即恢复。
            -- 重试成功则不再通知 onLoadFail；3 次仍失败才上报（真实错误）
            if self._navRetries < 3 and self._url then
                self._navRetries = self._navRetries + 1
                hs.timer.doAfter(0.4, function()
                    if self._wv then
                        pcall(function() self._wv:url(self._url) end)
                    end
                end)
                return
            end
            if self._onLoadFail then
                pcall(self._onLoadFail, action, err)
            else
                self._logger.ef("webview 页面加载失败: %s %s", action, tostring(err))
                hs.alert.show("面板加载失败，请重试")
            end
        end
    end)

    -- 失焦自动隐藏（focusChange 比 application.watcher 可靠；
    -- 延时防 show 过程中的瞬时失焦误关）
    wv:windowCallback(function(action, _, state)
        if action == "focusChange" and state == false and self:visible() then
            hs.timer.doAfter(0.1, function()
                if self:visible() then self:hide() end
            end)
        end
    end)

    -- 标题区拖拽：按住面板顶部（标题栏一带，高度 34px）拖动即移动面板。
    -- 策略：按下记录起点（不立即判定），移动超过 4px 才进入拖拽（区分点击 vs 拖动，
    -- 不干扰页面内按钮/输入框交互）；拖动中同步 setFrame（隐藏态先切后显）。
    local DRAG_BAR_H = 34     -- 顶部拖拽条高度（对齐 .page-head 视觉区）
    local DRAG_THRESHOLD = 4  -- 判定为拖拽的移动阈值（px）
    local function pointInPanel(mx, my)
        if not self._wv or not self:visible() then return false end
        local fr = self._wv:frame()
        if not fr then return false end
        return mx >= fr.x and mx <= fr.x + fr.w and my >= fr.y and my <= fr.y + fr.h
    end
    local function inDragBar(mx, my)
        if not self._wv or not self:visible() then return false end
        local fr = self._wv:frame()
        if not fr then return false end
        return mx >= fr.x and mx <= fr.x + fr.w and my >= fr.y and my <= fr.y + DRAG_BAR_H
    end
    self._drag.tap = eventtap.new({ event.types.leftMouseDown, event.types.leftMouseDragged, event.types.leftMouseUp }, function(e)
        local drag = self._drag
        local etype = e:getType()
        -- 鼠标位置统一走 hs.mouse.absolutePosition()（官方 API；
        -- event:absolutePosition 在部分版本不可用，避免踩坑）
        local ok, mx, my = pcall(function()
            local pt = hs.mouse.absolutePosition()
            return pt.x, pt.y
        end)
        if not ok or not mx then return false end
        if etype == event.types.leftMouseDown then
            -- 只在顶部拖拽条按下时预备拖拽（页面内容区照常交互）
            if inDragBar(mx, my) then
                drag.active = true
                drag.moved = false
                drag.startX, drag.startY = mx, my
                drag.frame = self._wv and self._wv:frame() or nil
            end
        elseif etype == event.types.leftMouseDragged then
            if drag.active and drag.frame then
                local dx, dy = mx - drag.startX, my - drag.startY
                if not drag.moved then
                    if math.abs(dx) < DRAG_THRESHOLD and math.abs(dy) < DRAG_THRESHOLD then
                        return false   -- 尚未超过阈值：继续观察
                    end
                    drag.moved = true
                end
                if drag.moved and self._wv then
                    pcall(function()
                        self._wv:setFrame({ x = drag.frame.x + dx, y = drag.frame.y + dy, w = drag.frame.w, h = drag.frame.h })
                    end)
                end
                return true   -- 拖拽中吞掉事件（页面不响应拖动）
            end
        elseif etype == event.types.leftMouseUp then
            if drag.active then
                drag.active = false
                drag.moved = false
                drag.frame = nil
            end
        end
        return false
    end)

    self._wv = wv
    return wv
end

--- 调前端 reset JS（需页面已就绪）
function View:_reset()
    if not self._resetJs then return end
    if not self._wv or not self._pageReady then return end
    local ok = pcall(function()
        self._wv:evaluateJavaScript(self._resetJs)
    end)
    if not ok then self._logger.w("webview reset JS 调用失败") end
end

function View:show()
    local wv = self:_ensure()
    if not wv then
        hs.alert.show("无法创建面板")
        return false
    end

    -- repositionOnShow：每次呼出按目标屏幕重算位置（面板跟随鼠标/焦点屏幕，
    -- 且拔外接屏/改分辨率后不悬空）。Launcher 模式不开此选项 → 位置保持首次创建值
    if self._repositionOnShow then
        pcall(function() wv:setFrame(self:_frame()) end)
    end

    -- 激活 Hammerspoon 进程：screenSaver level 下不激活进程，
    -- show 后键盘焦点进不了 webview
    local hsApp = hs.application.find("Hammerspoon")
    if hsApp then pcall(function() hsApp:activate(false) end) end

    wv:show()

    if not self._loadedOnce then
        -- 首次：加载 URL + 超时保护
        -- 扩展预热：webview 扩展是懒加载的（首次 require 才加载原生扩展），
        -- 直接 wv:url() 可能撞上扩展初始化未完成 → WebKit 101。
        -- 显式访问 hs.webview 模块函数触发扩展加载，再延迟导航，避开竞态
        pcall(function() return hs.webview.newBrowser end)
        self._pageReady = false
        wv:url(self._url)
        self._loadedOnce = true
        if self._readyTimer then self._readyTimer:stop() end
        self._readyTimer = hs.timer.doAfter(3, function()
            if not self._pageReady then
                if self._onTimeout then
                    pcall(self._onTimeout)
                else
                    self._logger.w("面板加载超时(3s)")
                end
            end
            self._readyTimer = nil
        end)
    elseif self._resetOnShow then
        -- 非首次：重开时清空上次状态
        self:_reset()
    end

    -- Esc 兜底（前端失焦时 Esc 不生效）
    if not self._escTap then
        self._escTap = eventtap.new({ event.types.keyDown }, function(e)
            if self:visible() and e:getKeyCode() == hs.keycodes.map.escape then
                self:hide()
                return true
            end
            return false
        end)
    end
    self._escTap:start()

    -- 拖拽 tap 启动（面板创建时注册，随 show/hide 生效判定）
    if self._drag and self._drag.tap then
        self._drag.tap:start()
    end
    return true
end

function View:hide()
    if self._wv then pcall(function() self._wv:hide() end) end
    if self._escTap then self._escTap:stop() end
    -- 拖拽复位（隐藏期间不响应拖动）
    if self._drag then
        self._drag.active = false
        self._drag.moved = false
        self._drag.frame = nil
        if self._drag.tap then self._drag.tap:stop() end
    end
    -- 隐藏时刷新（CH 模式）：下次展示即最新
    if not self._resetOnShow then self:_reset() end
end

function View:visible()
    return self._wv ~= nil and self._wv:isVisible() == true or false
end

function View:toggle()
    if self:visible() then self:hide() else self:show() end
end

--- 主动刷新前端（隐藏态静默刷新等场景）
function View:reset()
    self:_reset()
end

--- 动态调整面板尺寸/位置（设置保存后调用）。
--- 支持比例或绝对尺寸；已创建则立即 setFrame 生效（面板开着也能看到变化）
--- @param opts table {widthRatio=, heightRatio=, yRatio=, width=, height=}
function View:resize(opts)
    opts = opts or {}
    if opts.widthRatio ~= nil then self._widthRatio = opts.widthRatio end
    if opts.heightRatio ~= nil then self._heightRatio = opts.heightRatio end
    if opts.width ~= nil then self._width = opts.width; self._widthRatio = nil end
    if opts.height ~= nil then self._height = opts.height; self._heightRatio = nil end
    if opts.yRatio ~= nil then self._yRatio = opts.yRatio end
    if self._wv then
        pcall(function() self._wv:setFrame(self:_frame()) end)
    end
    return self
end

function View:teardown()
    if self._readyTimer then self._readyTimer:stop(); self._readyTimer = nil end
    if self._escTap then self._escTap:stop(); self._escTap = nil end
    if self._drag then
        if self._drag.tap then self._drag.tap:stop(); self._drag.tap = nil end
        self._drag.active = false
        self._drag.moved = false
        self._drag.frame = nil
    end
    if self._wv then pcall(function() self._wv:delete() end); self._wv = nil end
    self._pageReady = false
    self._loadedOnce = false
end

--- 底层 hs.webview（需要调未封装方法时用）
function View:raw()
    return self._wv
end

return webview

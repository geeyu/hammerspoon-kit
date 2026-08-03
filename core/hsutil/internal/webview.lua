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
---       yRatio = 0.22,              -- 可选，垂直位置（屏高比例），默认 0.22
---       level = ...,                -- 可选，默认 screenSaver
---       resetJs = "QW.reload && QW.reload()",  -- 前端刷新钩子（可选）
---       resetOnShow = true,         -- true=每次 show 刷新（Launcher 模式）；
---                                  -- false=隐藏时刷新（Clipboard 模式，下次展示即最新）
---       logger = <hs.logger>,       -- 可选，默认 HSUtil.webview
---       onLoadFail = fn(action, err),  -- 可选；默认 logger.e + hs.alert
---       onTimeout  = fn(),             -- 可选；默认 logger.w（首载 3s 未就绪）
---   })
---   view:show() / view:hide() / view:visible() / view:toggle()
---   view:reset()   -- 主动调前端 resetJs（隐藏态静默刷新等场景）
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
        _width = opts.width or math.floor(scr.w * 0.52),
        _height = opts.height or math.floor(scr.h * 0.62),
        _yRatio = opts.yRatio or 0.22,
        _level = opts.level or hs.drawing.windowLevels.screenSaver,
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
    }, View)
end

function View:_ensure()
    if self._wv then return self._wv end

    local scr = hs.screen.mainScreen():frame()
    local w, h = self._width, self._height
    local wv = hs.webview.new({
        x = math.floor(scr.x + (scr.w - w) / 2),
        y = math.floor(scr.y + (scr.h - h) * self._yRatio),
        w = w, h = h,
    })
    wv:darkMode(true)
    wv:transparent(true)      -- 圆角玻璃露出桌面
    wv:allowTextEntry(true)
    wv:shadow(true)
    wv:level(self._level)

    wv:navigationCallback(function(action, _, _, err)
        if action == "didFinishNavigation" then
            self._pageReady = true
            if self._readyTimer then self._readyTimer:stop(); self._readyTimer = nil end
        elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
            self._pageReady = false
            if self._onLoadFail then
                pcall(self._onLoadFail, action, err)
            else
                self._logger.e("webview 页面加载失败: %s %s", action, tostring(err))
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

    -- 激活 Hammerspoon 进程：screenSaver level 下不激活进程，
    -- show 后键盘焦点进不了 webview
    local hsApp = hs.application.find("Hammerspoon")
    if hsApp then pcall(function() hsApp:activate(false) end) end

    wv:show()

    if not self._loadedOnce then
        -- 首次：加载 URL + 超时保护
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
    return true
end

function View:hide()
    if self._wv then pcall(function() self._wv:hide() end) end
    if self._escTap then self._escTap:stop() end
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

function View:teardown()
    if self._readyTimer then self._readyTimer:stop(); self._readyTimer = nil end
    if self._escTap then self._escTap:stop(); self._escTap = nil end
    if self._wv then pcall(function() self._wv:delete() end); self._wv = nil end
    self._pageReady = false
    self._loadedOnce = false
end

--- 底层 hs.webview（需要调未封装方法时用）
function View:raw()
    return self._wv
end

return webview

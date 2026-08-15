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
    if self._wv then pcall(function() self._wv:delete() end); self._wv = nil end
    self._pageReady = false
    self._loadedOnce = false
end

--- 底层 hs.webview（需要调未封装方法时用）
function View:raw()
    return self._wv
end

return webview

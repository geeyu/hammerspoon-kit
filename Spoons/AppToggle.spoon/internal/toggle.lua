--- AppToggle.internal.toggle
--- 一键显隐引擎（移植自 core/app-toggle.lua，布局持久化改为注入式 storage，
--- 使布局可被管理页面查看/清除；并暴露按 bundleID 触发的 press 供「测试」按钮）。
---
--- 设计原则：极简。状态机不记忆任何东西，每次按键只看三个客观事实：
---   1. 应用是否隐藏     2. 窗口是否在鼠标所在屏的当前桌面     3. 窗口是否全屏
---
--- 布局锁定（无默认布局）：布局只来自你的手动设定——调整好窗口大小/位置后
---   按热键隐藏即记录为该屏布局并持久化（跨 reload 保留；隐藏后 0.4s 再补记
---   一次，确保拿到吸附落定后的准确尺寸）。呼出时强制应用锁定布局，显示后
---   0.5s 学习实际落定尺寸并更新布局。没有记录过的屏不做任何 frame 操作。
local toggle = {}

local storage   -- { loadLayouts(bundleID), saveLayouts(bundleID, layouts) } 注入
local hs_spaces = nil
pcall(function() hs_spaces = require("hs.spaces") end)

toggle._registry = {}   -- comboKey -> handle
toggle._byBundle = {}   -- bundleID -> handle（按应用定位，测试按钮用）

function toggle.setup(storage_)
    storage = storage_
end

local function comboKey(mods, key)
    return table.concat(mods or {}, "+") .. "+" .. key
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(v, hi))
end

local function screenID(screen)
    if not screen then return "?" end
    local ok, uuid = pcall(function() return screen:getUUID() end)
    if ok and uuid then return uuid end
    return tostring(screen:id())
end

local function loadLayouts(bundleID)
    if not storage or not storage.loadLayouts then return {} end
    return storage.loadLayouts(bundleID)
end

local function saveLayouts(handle)
    if not storage or not storage.saveLayouts then return end
    pcall(storage.saveLayouts, handle.bundleID, handle._layouts or {})
end

local function screenAtPoint(mouse)
    -- 命中检测用 fullFrame（含菜单栏/Dock 的完整区域）：鼠标可能在菜单栏上
    for _, s in ipairs(hs.screen.allScreens()) do
        local f = s:fullFrame()
        if mouse.x >= f.x and mouse.x <= f.x + f.w and mouse.y >= f.y and mouse.y <= f.y + f.h then
            return s
        end
    end
    return hs.screen.mainScreen()
end

--- 某屏当前激活的桌面（Space）id
local function activeSpaceOf(screen)
    if not hs_spaces or not screen then return nil end
    local ok, sp = pcall(hs_spaces.activeSpaceOnScreen, screen)
    return ok and sp or nil
end

--- 窗口所在的所有桌面 id
local function windowSpaces(win)
    if not hs_spaces or not win then return {} end
    local ok, ws = pcall(hs_spaces.windowSpaces, win)
    return ok and ws or {}
end

local function moveWindowToSpace(win, sp)
    if not hs_spaces or not sp or not win then return end
    pcall(hs_spaces.moveWindowToSpace, win, sp)
end

local function windowOnSpace(win, sp)
    if not sp then return false end
    for _, s in ipairs(windowSpaces(win)) do
        if s == sp then return true end
    end
    return false
end

local function onCurrentSpace(app, win, mouseScreen)
    if not app:isHidden() then
        local sp = activeSpaceOf(mouseScreen)
        if sp and windowOnSpace(win, sp) then return true end
        -- hs.spaces 不可用时的近似判断
        if win:isVisible() and win:screen() == mouseScreen then return true end
    end
    return false
end

--- 移除一个绑定（按组合键）
function toggle.unbind(mods, key)
    local ck = comboKey(mods, key)
    local h = toggle._registry[ck]
    if h then
        pcall(function() h.hotkey:delete() end)
        toggle._registry[ck] = nil
        if h.bundleID then toggle._byBundle[h.bundleID] = nil end
    end
end

--- 呼出：按鼠标所在屏的锁定布局显示（跨屏/尺寸变化时隐藏状态下预定位，等提交后显示）
local function summon(handle, app, win)
    handle._gen = (handle._gen or 0) + 1
    -- 记录呼出前的前台应用（供隐藏时还原焦点；不记自己）
    local front = hs.application.frontmostApplication()
    if front and front:bundleID() ~= handle.bundleID then
        handle.prevBundleID = front:bundleID()
    end

    -- moveToMouseScreen=false 时完全不做定位/尺寸调整
    if handle.opts.moveToMouseScreen == false then
        app:unhide()
        win:raise()
        win:focus()
        return
    end

    local mouse = hs.mouse.absolutePosition()
    local screen = screenAtPoint(mouse)
    if not screen then return end

    local sp = activeSpaceOf(screen)

    -- 目标空间是别的应用的全屏 Space → 全屏形态接管
    -- （macOS 不允许悬浮叠窗，全屏是唯一能"盖在页面上面"的路径）
    if sp and hs_spaces and handle.opts.fullscreenFallback ~= false then
        local ok, st = pcall(hs_spaces.spaceType, sp)
        if ok and st == "fullscreen" then
            if win:isFullScreen() then
                app:unhide()
                win:raise()
                win:focus()
            else
                local goFullscreen = function()
                    app:unhide()
                    pcall(function() win:setFullScreen(true) end)
                    win:raise()
                    win:focus()
                    -- 全屏动画异步：结束后补一次聚焦，确保立即可打字
                    hs.timer.doAfter(0.5, function()
                        if not app:isHidden() and win:isFullScreen() then
                            win:raise()
                            win:focus()
                            pcall(function() app:activate(true) end)
                        end
                    end)
                end
                if win:screen() ~= screen then
                    -- 窗口要全屏在目标屏：先把 frame 挪过去，等异步提交生效后再全屏
                    local tf = screen:frame()
                    win:setFrame({ x = tf.x, y = tf.y, w = tf.w, h = tf.h }, 0)
                    hs.timer.doAfter(0.1, goFullscreen)
                else
                    goFullscreen()
                end
            end
            return
        end
    end

    -- 锁定布局（仅来自用户手动设定：隐藏时记录并持久化；无默认布局）。
    -- 强制控制：只要有布局就应用，仅在当前 frame 已完全等于布局时跳过。
    local layout = handle._layouts[screenID(screen)]
    local needMove = sp ~= nil and not windowOnSpace(win, sp)
    local needFrame = false
    local frame = nil
    if layout then
        local cur = win:frame()
        needFrame = math.abs(cur.x - layout.x) >= 2 or math.abs(cur.y - layout.y) >= 2
            or math.abs(cur.w - layout.w) >= 2 or math.abs(cur.h - layout.h) >= 2
        if needFrame then
            local vf = screen:frame()
            frame = { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
            -- 超屏保护只防"布局超出当前屏可用区"，clamp 到 vf.w/vf.h 整值
            frame.w = math.min(frame.w, vf.w)
            frame.h = math.min(frame.h, vf.h)
            frame.x = clamp(frame.x, vf.x, vf.x + vf.w - frame.w)
            frame.y = clamp(frame.y, vf.y, vf.y + vf.h - frame.h)
            pcall(function() win:setFrameWithWorkarounds(frame, 0) end)
        end
    end
    if needMove then moveWindowToSpace(win, sp) end

    local show = function()
        app:unhide()
        -- 只前置关键窗口（activate(false)），避免多窗口一起闪出
        pcall(function() app:activate(false) end)
        win:raise()
        win:focus()
    end

    if not needFrame and not needMove then
        show() -- 全速路径：无需任何移动，纯显示
    else
        -- setFrame/移桌是异步提交（实测 ~80ms），等提交生效再显示
        hs.timer.doAfter(0.1, show)
    end

    -- 显示后"学习"实际落定值（Ghostty 只在可见时才吸附网格）：
    -- 顺从策略——显示后读取实际尺寸，把布局更新为真实网格尺寸（不动点）
    if needFrame then
        hs.timer.doAfter(0.5, function()
            if app:isHidden() or not frame then return end
            local f = win:frame()
            local diff = math.abs(f.x - frame.x) + math.abs(f.y - frame.y)
                + math.abs(f.w - frame.w) + math.abs(f.h - frame.h)
            if diff > 2 then
                local scr = win:screen()
                if scr then
                    handle._layouts[screenID(scr)] = { x = f.x, y = f.y, w = f.w, h = f.h }
                    saveLayouts(handle)
                end
            end
        end)
    end
end

--- 隐藏：记录当前形态到该屏布局，然后 hide（全屏形态先退出全屏）
local function dismiss(handle, app, win)
    handle._gen = (handle._gen or 0) + 1

    -- 记录当前形态为该屏锁定布局并持久化（全屏形态不记录）。
    -- 立即记一次 + 0.4s 后再记一次：网格吸附收尾时第二次能拿到准确尺寸
    local recordLayout = function()
        if win:isFullScreen() then return end
        local scr = win:screen()
        if scr then
            local f = win:frame()
            handle._layouts[screenID(scr)] = { x = f.x, y = f.y, w = f.w, h = f.h }
            saveLayouts(handle)
        end
    end
    recordLayout()
    hs.timer.doAfter(0.4, recordLayout)

    local restoreFocus = handle.opts.restoreFocus ~= false and handle.prevBundleID and app:isFrontmost()
    local prevBundleID = handle.prevBundleID
    handle.prevBundleID = nil
    local focusBack = function()
        if restoreFocus and prevBundleID then
            local prev = hs.application.get(prevBundleID)
            if prev and not prev:isFrontmost() then pcall(function() prev:activate() end) end
        end
    end

    -- 全屏形态：先退出全屏，等动画结束再隐藏，避免窗口卡在半全屏
    if win:isFullScreen() then
        pcall(function() win:setFullScreen(false) end)
        local gen = handle._gen
        hs.timer.doAfter(0.6, function()
            if handle._gen ~= gen then return end -- 期间有新操作，放弃本次隐藏
            if app:isHidden() then return end
            pcall(function() win:setFullScreen(false) end) -- 幂等保险
            app:hide()
            focusBack()
        end)
    else
        app:hide()
        focusBack()
    end
end

--- 应用未运行 / 运行中但无窗口
local function noWindow(handle, app)
    local fn = handle.opts.onNoWindow
    if type(fn) == "function" then
        fn(app)
    else
        -- 默认：启动应用（未运行会启动；已运行只是激活）
        hs.application.open(handle.bundleID)
    end
end

--- 绑定：任意应用 + 任意按键 一键显隐
--- @param app table {bundle_id, mods, key, enabled, on_no_window,
---   fullscreen_fallback, restore_focus, move_to_mouse_screen}
--- @return handle|nil, err|nil
function toggle.bind(app)
    local bundleID = app.bundle_id
    local mods = app.mods or {}
    local key = app.key
    if not bundleID or not key or key == "" then
        return nil, "缺 bundle_id 或 key"
    end
    -- 功能键（F1-F12）允许无修饰键；普通键必须带修饰键
    local isFnKey = key:match("^[Ff]1?[0-9]$") ~= nil or key:match("^[Ff]1[0-2]$") ~= nil
    if #mods == 0 and not isFnKey then
        return nil, "至少需要一个修饰键（或使用 F1-F12）"
    end

    -- 同一组合已存在则先替换
    toggle.unbind(mods, key)

    local opts = {
        onNoWindow = app.on_no_window == "activate"
            and function(a)
                -- 仅激活：已运行则激活，未运行不启动
                if a and not a:isRunning() then return end
                pcall(function() a:activate(true) end)
            end
            or nil,   -- 默认 launch：hs.application.open
        fullscreenFallback = app.fullscreen_fallback ~= false,
        restoreFocus = app.restore_focus ~= false,
        moveToMouseScreen = app.move_to_mouse_screen ~= false,
    }

    local handle = {
        bundleID = bundleID,
        mods = mods,
        key = key,
        opts = opts,
        prevBundleID = nil,
        _layouts = loadLayouts(bundleID),
        _gen = 0,
        _lastToggle = nil,
        _spawning = nil,
    }

    local function press()
        local now = hs.timer.secondsSinceEpoch()
        -- 120ms 防抖：show/hide 异步进行中，快速连按忽略
        if handle._lastToggle and (now - handle._lastToggle) < 0.12 then return end
        handle._lastToggle = now

        local app = hs.application.get(bundleID)
        if not app or #app:allWindows() == 0 then
            -- 应用启动中/建窗需要时间：3s 内不重复触发 onNoWindow
            if handle._spawning and (now - handle._spawning) < 3 then return end
            handle._spawning = now
            noWindow(handle, app)
            return
        end
        local win = app:mainWindow() or app:allWindows()[1]
        local mouseScreen = screenAtPoint(hs.mouse.absolutePosition())

        -- 光标所在屏的当前桌面是否全屏（决定"全屏接管"分支）
        local targetSpace = activeSpaceOf(mouseScreen)
        local fullscreenSpace = false
        if targetSpace and hs_spaces then
            local ok, st = pcall(hs_spaces.spaceType, targetSpace)
            fullscreenSpace = ok and st == "fullscreen"
        end

        if app:isHidden() then
            summon(handle, app, win)
        elseif win:isFullScreen() then
            dismiss(handle, app, win)
        elseif fullscreenSpace then
            summon(handle, app, win)
        elseif onCurrentSpace(app, win, mouseScreen) then
            dismiss(handle, app, win)
        elseif win:screen() == mouseScreen then
            summon(handle, app, win)
        else
            dismiss(handle, app, win)
        end
    end

    handle.hotkey = hs.hotkey.bind(mods, key, press)
    -- bind 失败（组合被系统/其他程序占用等）时 hs.hotkey.bind 返回 nil：
    -- 不注册进 registry，press 仍可用于管理页「测试」按钮
    if not handle.hotkey then
        return nil, "热键 " .. comboKey(mods, key) .. " 绑定失败（可能被系统或其他应用占用）"
    end
    handle.press = press
    toggle._registry[comboKey(mods, key)] = handle
    toggle._byBundle[bundleID] = handle
    return handle
end

--- 按 bundleID 触发（管理页「测试」按钮：与热键同一逻辑）
function toggle.pressByBundle(bundleID)
    local h = toggle._byBundle[bundleID]
    if h then h.press() end
end

--- 某应用当前绑定状态（布局/是否运行等，供管理页展示）
function toggle.appState(bundleID)
    local app = hs.application.get(bundleID)
    local layouts = loadLayouts(bundleID)
    local out = {
        running = app ~= nil and app:isRunning(),
        hidden = app ~= nil and app:isHidden(),
        layouts = {},
    }
    for sid, f in pairs(layouts) do
        out.layouts[sid] = { x = f.x, y = f.y, w = f.w, h = f.h }
    end
    return out
end

--- 清除某应用全部锁定布局
function toggle.clearLayouts(bundleID)
    local h = toggle._byBundle[bundleID]
    if h then
        h._layouts = {}
        saveLayouts(h)
    end
    return true
end

--- 释放全部注册（reload/stop 前调用）
function toggle.cleanup()
    for ck, h in pairs(toggle._registry) do
        if h.hotkey then pcall(function() h.hotkey:delete() end) end
        toggle._registry[ck] = nil
    end
    toggle._byBundle = {}
end

return toggle

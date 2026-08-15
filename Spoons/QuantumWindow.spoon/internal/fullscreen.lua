--- QuantumWindow.internal.fullscreen
--- 铺满/最大化（当前 Space 内铺满，非 macOS 全屏空间）
--- 首次铺满，再次按还原原尺寸（toggle）。
local fullscreen = {}

-- 记录每个窗口铺满前的 frame
local prevFrames = {}

--- 执行铺满/还原 toggle
function fullscreen.toggle(win)
    win = win or hs.window.focusedWindow()
    if not win then return false, "无聚焦窗口" end

    local wid = win:id()
    local screenFrame = win:screen() and win:screen():frame()
    if not screenFrame then
        return false, "无法获取屏幕"
    end

    local current = win:frame()
    -- 还原判定以 prevFrames 记录为准（权威），不再依赖尺寸近似比较：
    -- maximize 后的窗口尺寸 ≠ 全屏 frame（菜单栏/Dock 占位，差 >2px 很常见），
    -- 原 isMaxed 比较在 Dock 可见时恒为 false → 第二次按键重复铺满、永远无法还原
    local prev = prevFrames[wid]
    if prev then
        prevFrames[wid] = nil
        win:setFrame(prev)
        return true
    end

    local isMaxed = math.abs(current.w - screenFrame.w) < 2
        and math.abs(current.h - screenFrame.h) < 2
    if isMaxed then
        -- 外部铺满且无记录：无可还原，保持现状
        return true
    end

    -- 记录当前，再铺满
    prevFrames[wid] = current
    win:maximize(0)  -- 0 = 关闭动画
    return true
end

return fullscreen

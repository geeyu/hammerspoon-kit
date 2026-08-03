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
    local isMaxed = math.abs(current.w - screenFrame.w) < 2
        and math.abs(current.h - screenFrame.h) < 2

    if isMaxed then
        -- 已铺满 -> 还原
        local prev = prevFrames[wid]
        if prev then win:setFrame(prev) end
        prevFrames[wid] = nil
    else
        -- 记录当前，再铺满
        prevFrames[wid] = current
        win:maximize(0)  -- 0 = 关闭动画
    end
    return true
end

return fullscreen

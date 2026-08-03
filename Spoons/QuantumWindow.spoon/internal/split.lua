--- QuantumWindow.internal.split
--- 半屏分屏（纯原生 unitrect 实现，无外部依赖）
--- 返回模块：内部暴露 operate(win, action) 供 spoon 统一调用。
local split = {}

-- 动作 -> 相对屏幕的 unitrect
local RECTS = {
    left_half   = { x = 0.00, y = 0.00, w = 0.50, h = 1.00 },
    right_half  = { x = 0.50, y = 0.00, w = 0.50, h = 1.00 },
    top_half    = { x = 0.00, y = 0.00, w = 1.00, h = 0.50 },
    bottom_half = { x = 0.00, y = 0.50, w = 1.00, h = 0.50 },
}

--- 记录每个窗口分屏前的 frame（保留入口；暂不用于 restore）
-- local prevFrames = {}

--- 把窗口铺到指定单位区域
local function moveAction(win, action)
    local r = RECTS[action]
    if not r then
        return false, "未知分屏动作: " .. tostring(action)
    end

    local screen = win:screen()
    if not screen then
        return false, "无法获取屏幕"
    end

    local frame = screen:frame()
    win:setFrame({
        x = frame.x + frame.w * r.x,
        y = frame.y + frame.h * r.y,
        w = frame.w * r.w,
        h = frame.h * r.h,
    })
    win:raise()
    return true
end

--- 暴露：操作当前聚焦窗口
function split.operate(win, action)
    win = win or hs.window.focusedWindow()
    if not win then return false, "无聚焦窗口" end
    return moveAction(win, action)
end

--- 支持的合法动作名（供 bindHotkeys 校验）
split.actions = RECTS

return split

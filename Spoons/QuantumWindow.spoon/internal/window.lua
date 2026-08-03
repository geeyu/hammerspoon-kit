--- QuantumWindow.internal.window
--- 窗口纯工具函数（无副作用，不直接绑定快捷键）
local window = {}

--- 当前聚焦窗口（空则返回 nil）
function window.focused()
    return hs.window.focusedWindow()
end

--- 安全获取窗口所在屏幕 frame（全局坐标）
function window.screenFrame(win)
    if not win then return nil end
    local screen = win:screen()
    if not screen then return nil end
    return screen:frame()
end

--- 以"绝对坐标 + 绝对尺寸"设置窗口 frame
function window.setAbsolute(win, x, y, w, h)
    if not win then return false end
    win:setFrame({ x = x, y = y, w = w, h = h })
    return true
end

--- 在窗口所在屏幕上，按绝对尺寸居中
function window.centerAbsolute(win, w, h)
    local frame = window.screenFrame(win)
    if not frame then return false end
    local x = frame.x + (frame.w - w) / 2
    local y = frame.y + (frame.h - h) / 2
    return window.setAbsolute(win, x, y, w, h)
end

--- 把窗口移到指定方向的另一块显示器
function window.moveToScreen(win, direction)
    if not win then return end
    if direction == "north" then win:moveOneScreenNorth() end
    if direction == "south" then win:moveOneScreenSouth() end
    if direction == "east"  then win:moveOneScreenEast()  end
    if direction == "west"  then win:moveOneScreenWest()  end
end

return window

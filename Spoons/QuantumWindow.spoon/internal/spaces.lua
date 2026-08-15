--- QuantumWindow.internal.spaces
--- Space 相邻移动 + 多显示器上/下移动（基于内置 hs.spaces / hs.window）
local spaces = {}

-- 运行时通过 setup 注入 window 工具（内部用相对路径 dofile 加载，避免 require 依赖）
local windowTool

local function screenSpaces(win)
    local screenUUID = win and win:screen() and win:screen():getUUID()
    if not screenUUID then return nil end
    local list, err = hs.spaces.spacesForScreen(screenUUID)
    if not list then
        return nil, err
    end
    return list
end

--- 把窗口移动到相邻 space（dir=1 下一个，-1 上一个）
local function moveWindowToAdjacentSpace(win, dir)
    if not win then return false, "无聚焦窗口" end
    if not hs.spaces then return false, "hs.spaces 不可用" end

    local screen = win:screen()
    if not screen then return false, "无法获取窗口所在屏幕" end
    local screenUUID = screen:getUUID()

    local list = screenSpaces(win)
    if not list or #list == 0 then
        return false, "当前屏幕没有可用的 Space 列表（请先启用多个 Space）"
    end

    -- 若窗口横跨所有 space（辅助窗口/控制台等），移动无效，提前提示
    local winSp = hs.spaces.windowSpaces(win)
    if winSp and #winSp >= #list then
        return false, "该窗口显示在所有 Space（辅助窗口），无法移动"
    end
    -- 若窗口不在任何可判断的单一 space，静默返回

    local current = hs.spaces.activeSpaceOnScreen(screenUUID)
    if not current then
        return false, "未获取到当前 Space"
    end

    local idx
    for i, sid in ipairs(list) do
        if sid == current then idx = i break end
    end
    if not idx then
        return false, "当前 Space 不在列表"
    end

    local targetIdx = idx + dir
    if targetIdx < 1 or targetIdx > #list then
        return false, "已到 Space 边界，无法继续"
    end

    local targetSpace = list[targetIdx]
    local ok, err = hs.spaces.moveWindowToSpace(win, targetSpace)
    if not ok then
        return false, "移动失败: " .. tostring(err or "未知错误")
    end

    -- moveWindowToSpace 为异步切换；发起成功即视为已移动
    return true
end

--- 暴露：相邻 Space 移动
function spaces.moveAdjacent(win, dir)
    win = win or hs.window.focusedWindow()
    return moveWindowToAdjacentSpace(win, dir)
end

--- 暴露：移动到上方/下方显示器
function spaces.moveScreen(win, direction)
    win = win or hs.window.focusedWindow()
    if not win then return false, "无聚焦窗口" end
    local ok = windowTool.moveToScreen(win, direction)
    if not ok then
        return false, "该方向没有显示器"
    end
    return true
end

function spaces.setup(tool)
    windowTool = tool
end

return spaces

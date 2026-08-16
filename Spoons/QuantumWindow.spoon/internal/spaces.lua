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

--- 兜底移动：官方 moveWindowToSpace 在部分系统（macOS 14.5+ yabai workaround 受 SIP 限制）
--- 假成功（返回 true 但窗口不动）。改用可靠流程：
---   ① gotoSpace 切到目标 Space（Mission Control AX，已验证可用）
---   ② 对窗口 setFullScreen（不可见窗口也会在当前屏创建全屏 Space）
---   ③ 退全屏 → 窗口落到当前（目标）Space
--- 同步执行（热键回调内），期间有 MC 过渡 + 全屏闪烁的视觉反馈。
--- @return boolean, string|nil
local function fallbackMoveToSpace(win, targetSpace)
    if win:isFullScreen() then return false, "全屏窗口无法移动" end
    local uuid = win:screen() and win:screen():getUUID()
    -- ① 切到目标 Space
    local ok, err = hs.spaces.gotoSpace(targetSpace)
    if not ok then return false, "切换 Space 失败: " .. tostring(err or "未知错误") end
    -- 等切换完成（轮询激活 space）
    local t0 = hs.timer.secondsSinceEpoch()
    while uuid and hs.timer.secondsSinceEpoch() - t0 < 3 do
        if hs.spaces.activeSpaceOnScreen(uuid) == targetSpace then break end
        hs.timer.usleep(100000)
    end
    -- ② 全屏（窗口虽不可见，也会在当前屏创建全屏 Space）
    if not win:setFullScreen(true) then return false, "无法进入全屏" end
    local t1 = hs.timer.secondsSinceEpoch()
    while not win:isFullScreen() and hs.timer.secondsSinceEpoch() - t1 < 3 do
        hs.timer.usleep(100000)
    end
    if not win:isFullScreen() then return false, "全屏超时" end
    -- ③ 退全屏：窗口落到当前（目标）Space
    win:setFullScreen(false)
    local t2 = hs.timer.secondsSinceEpoch()
    while win:isFullScreen() and hs.timer.secondsSinceEpoch() - t2 < 3 do
        hs.timer.usleep(100000)
    end
    return true
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

    -- 官方 API 在部分系统假成功（返回 true 但窗口不动）：延迟验证，未移动则走兜底方案
    hs.timer.doAfter(0.5, function()
        local ws = hs.spaces.windowSpaces(win) or {}
        local moved = false
        for _, s in ipairs(ws) do
            if s == targetSpace then moved = true break end
        end
        if not moved then
            local fok, ferr = fallbackMoveToSpace(win, targetSpace)
            if not fok then
                hs.alert.show("移动 Space 失败: " .. tostring(ferr or "未知错误"))
            end
        end
    end)

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

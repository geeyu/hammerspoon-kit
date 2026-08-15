--- QuantumWindow.internal.center
--- 居中 + 绝对尺寸（默认 800 x 600）
local center = {}

-- 运行时注入 window 工具
local windowTool

local function doCenter(win, cfg)
    if not win then return false, "无聚焦窗口" end
    local w = cfg.width or 800
    local h = cfg.height or 600
    local ok = windowTool.centerAbsolute(win, w, h)
    if not ok then return false, "无法获取窗口所在屏幕" end
    if cfg.raise then win:raise() end
    return true
end

--- 执行居中
function center.operate(win, cfg)
    win = win or hs.window.focusedWindow()
    return doCenter(win, cfg)
end

function center.setup(tool)
    windowTool = tool
end

return center

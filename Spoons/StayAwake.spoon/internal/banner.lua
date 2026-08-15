--- StayAwake.internal.banner
--- 常驻右上角的半透明倒计时条（hs.drawing 实现）。
--- 会话激活时显示，会话结束自动隐藏。每秒刷新剩余时间。
--- 左侧红点 + 高斯光晕图（assets/glow.png，径向渐变）呼吸 + 浮动粒子表示运行中。
--- canJoinAllSpaces + fullScreenAuxiliary 行为：全屏应用（FullScreen Space）上也可见。
--- 拖动用 eventtap 全局跟踪（命中条内吞事件，不穿透底层窗口）。
--- 呼吸计时用 hs.timer.secondsSinceEpoch（墙上时间）——os.clock 是 CPU 时间，
--- HS 空闲时不走，会导致呼吸只在交互时动。
--- 依赖：timeutil（formatDuration）、settings（bannerPos 持久化）
local M = {}

-- 定位本模块目录（与 init.lua 相同的加载模式）
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local timeutil = dofile(script_path() .. "timeutil.lua")
local settings = dofile(script_path() .. "settings.lua")

local WIDTH, HEIGHT = 240, 36
local settingsFile = os.getenv("HOME") .. "/.hammerspoon/data/StayAwake/settings.json"
local GLOW_PNG = script_path() .. "../assets/glow.png"

local BREATH_PERIOD = 2.4     -- 呼吸周期（秒）
local GLOW_R = 16             -- 光晕最大半径（PNG 96px 显示 32×32 @ GLOW_R=16）
local GLOW_R_MIN = 12         -- 光晕最小半径
local DOT_CX = 20             -- 红点/光晕中心 x（距左边框）
local DOT_R = 3.5             -- 红点最小半径（呼吸到 DOT_R_MAX）
local DOT_R_MAX = 4.5         -- 红点最大半径（呼吸幅度小，避免与文本重叠）
local TEXT_GAP = 7            -- 红点与文字间隔（不重叠也不疏远）
local RIGHT_PAD = 4           -- 右侧留白（贴近内容，不留大片空白）
local TEXT_X = DOT_CX + DOT_R_MAX + TEXT_GAP   -- 文本起点 x
local MIN_WIDTH = 140         -- 条宽下限（短文本时不至于过窄）

--- 估算文本宽度（13pt：全角≈13px，半角≈7.2px；无测量 API，估算误差 ±5% 内）
local function estimateTextWidth(text)
    local w = 0
    local i = 1
    while i <= #text do
        local b = text:byte(i)
        if b >= 128 then
            w = w + 13
            if b >= 0xF0 then i = i + 4 elseif b >= 0xE0 then i = i + 3 elseif b >= 0xC0 then i = i + 2 else i = i + 1 end
        else
            w = w + 7.2
            i = i + 1
        end
    end
    return w
end

-- 绘图对象：1=背景 2=光晕 3=红点（均为高斯渐变图 assets/glow.png，无边缘）4=文本
local drawings = {}
local relOffsets = {}
local ticker = nil      -- 每秒刷新 timer
local breathTimer = nil -- 呼吸动画 timer（0.08s 刷新光晕/红点）
local sessionRef = nil  -- 当前会话对象（session.new 产物）
local dragTap = nil     -- 拖动 eventtap（全局跟踪）
local downTap = nil     -- 按下检测 eventtap（命中条内启动拖动）
local dragFrameOrigin = nil  -- 按下时背景的原点（屏幕坐标）
local dragStartPoint = nil   -- 按下时的鼠标屏幕位置

--- 倒计时条文本（纯函数，可单测）
--- @param sessionType string|nil "permanent"|"timer"|"until"
--- @param remaining number|nil 剩余秒数（permanent 为 nil）
--- @return string|nil 未知类型/缺参数返回 nil
function M.formatText(sessionType, remaining)
    if sessionType == "permanent" then
        return "保持清醒中（无限期）"
    elseif sessionType == "timer" or sessionType == "until" then
        if type(remaining) ~= "number" then return nil end
        return "保持清醒中（剩余 " .. timeutil.formatDuration(remaining) .. "）"
    end
    return nil
end

--- 默认位置：主屏右上角菜单栏下方（注入 filePath/settings 便于测试）
function M.defaultPos()
    local f = hs.screen.primaryScreen():frame()
    return { x = f.x + f.w - WIDTH - 14, y = f.y + 26 + 8 }
end

--- 读取持久化位置（非法/缺失 → 默认位置）
--- @param filePath string|nil 覆盖设置文件路径（测试用）
--- @param settingsMod table|nil 注入 settings 模块
function M.loadPos(filePath, settingsMod)
    filePath = filePath or settingsFile
    settingsMod = settingsMod or settings
    local s = settingsMod.load(filePath)
    local p = s and s.bannerPos
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
        return { x = p.x, y = p.y }
    end
    return M.defaultPos()
end

--- 保存位置（合并写入，保留 mode 字段）。成功返回 true
--- @param x number
--- @param y number
function M.savePos(x, y, filePath, settingsMod)
    filePath = filePath or settingsFile
    settingsMod = settingsMod or settings
    local s = settingsMod.load(filePath)
    s.bannerPos = { x = x, y = y }
    return settingsMod.save(filePath, s)
end

--- 创建全部绘图对象（调用方负责先 stop）
local function createDrawings()
    local level = hs.drawing.windowLevels.overlay
    -- 全屏应用（FullScreen Space）上也可见：加入所有空间 + 全屏辅助窗口
    local behavior = hs.drawing.windowBehaviors.canJoinAllSpaces
        + hs.drawing.windowBehaviors.fullScreenAuxiliary

    local bg = hs.drawing.rectangle({ x = 0, y = 0, w = WIDTH, h = HEIGHT })
    bg:setRoundedRectRadii(9, 9)
    bg:setFillColor({ red = 0.07, green = 0.07, blue = 0.07, alpha = 0.60 })
    bg:setStrokeColor({ white = 1, alpha = 0.10 })
    bg:setStrokeWidth(1)
    bg:setLevel(level)
    bg:setBehavior(behavior)

    -- 光晕：高斯径向渐变图（assets/glow.png），呼吸只改 frame 缩放
    local glow = hs.drawing.image({ x = DOT_CX - GLOW_R, y = 18 - GLOW_R, w = GLOW_R * 2, h = GLOW_R * 2 }, GLOW_PNG)
    glow:setLevel(level)
    glow:setBehavior(behavior)

    -- 红点：同一张高斯渐变图缩小显示（无边缘、无描边），呼吸从最小到最大
    local dot = hs.drawing.image({ x = DOT_CX - DOT_R, y = 18 - DOT_R, w = DOT_R * 2, h = DOT_R * 2 }, GLOW_PNG)
    dot:setLevel(level)
    dot:setBehavior(behavior)

    -- 文本（左对齐紧贴红点，TEXT_GAP 间隔；宽度由 updateText 自适应）
    local text = hs.drawing.text({ x = TEXT_X, y = 9, w = 120, h = 18 }, "")
    text:setTextSize(13)
    text:setTextColor({ white = 1, alpha = 0.95 })
    text:setTextStyle({ alignment = "left" })   -- 左对齐：红点+文本紧凑成簇
    text:setLevel(level)
    text:setBehavior(behavior)

    -- 同 level 窗口显式排序：背景最底 → 光晕 → 红点 → 文本最顶
    glow:orderAbove(bg)
    dot:orderAbove(glow)
    text:orderAbove(dot)

    drawings = { bg, glow, dot, text }
    relOffsets = {}
    for i, d in ipairs(drawings) do
        local f = d:frame()
        relOffsets[i] = { dx = f.x, dy = f.y, w = f.w, h = f.h }
    end
end

--- 当前条原点（背景左上角，屏幕坐标）
local function bannerOrigin()
    local f = drawings[1]:frame()
    return f.x, f.y
end

--- 整体移动到指定原点（屏幕坐标）
local function setBannerFrame(x, y)
    for i, d in ipairs(drawings) do
        local r = relOffsets[i]
        d:setFrame({ x = x + r.dx, y = y + r.dy, w = r.w, h = r.h })
    end
end

--- 刷新文本并自适应条宽（右侧留白与红点左边距对称）
--- 条宽 = 红点簇 + 间隔 + 文本宽 + RIGHT_PAD；文本宽按字符估算
local function updateText()
    if not sessionRef or not drawings[4] then return end
    local remaining
    if sessionRef.endsAt then
        remaining = sessionRef.endsAt - os.time()
    end
    local text = M.formatText(sessionRef.type, remaining)
    if not text then return end
    drawings[4]:setText(text)
    local ox, oy = bannerOrigin()
    local tw = estimateTextWidth(text)
    local bw = math.max(TEXT_X + tw + RIGHT_PAD, MIN_WIDTH)
    drawings[1]:setFrame({ x = ox, y = oy, w = bw, h = HEIGHT })
    drawings[4]:setFrame({ x = ox + TEXT_X, y = oy + 9, w = tw, h = 18 })
    -- 同步 relOffsets，拖动时按最新宽度平移
    relOffsets[1] = { dx = 0, dy = 0, w = bw, h = HEIGHT }
    relOffsets[4] = { dx = TEXT_X, dy = 9, w = tw, h = 18 }
end

--- 呼吸动画（0.08s）：光晕与红点同步脉动（红点幅度小，从最小到最大）
--- 用墙上时间（secondsSinceEpoch），HS 空闲时动画持续
local function breath()
    if not drawings[2] then return end
    local t = hs.timer.secondsSinceEpoch()
    local ox, oy = bannerOrigin()
    local k = 0.5 + 0.5 * math.sin(t * 2 * math.pi / BREATH_PERIOD)
    -- 光晕（12~16）
    local gr = GLOW_R_MIN + (GLOW_R - GLOW_R_MIN) * k
    drawings[2]:setFrame({ x = ox + DOT_CX - gr, y = oy + 18 - gr, w = gr * 2, h = gr * 2 })
    -- 红点（3.5~4.5，与光晕同相位）
    local dr = DOT_R + (DOT_R_MAX - DOT_R) * k
    drawings[3]:setFrame({ x = ox + DOT_CX - dr, y = oy + 18 - dr, w = dr * 2, h = dr * 2 })
end

--- 停止拖动跟踪
local function stopDragTap()
    if dragTap then dragTap:stop() dragTap = nil end
    dragFrameOrigin, dragStartPoint = nil, nil
end

--- 拖动：eventtap 全局跟踪 leftMouseDragged/Up（鼠标移出条也不断）
--- 拖动期间 return true 吞掉事件，防止点击/拖动穿透到底层窗口
--- 基准法：新位置 = 按下时背景原点 + 当前鼠标与按下时的屏幕位移，clamp 屏幕内
local function startDragTap()
    stopDragTap()
    local bg = drawings[1]
    if not bg then return end
    local f = bg:frame()
    dragFrameOrigin = { x = f.x, y = f.y }
    dragStartPoint = hs.geometry.point(hs.mouse.getAbsolutePosition())
    dragTap = hs.eventtap.new({
        hs.eventtap.event.types.leftMouseDragged,
        hs.eventtap.event.types.leftMouseUp,
    }, function(e)
        local p = hs.geometry.point(e:location())
        if e:getType() == hs.eventtap.event.types.leftMouseDragged then
            local sf = hs.screen.mainScreen():frame()
            local bw = drawings[1] and drawings[1]:frame().w or WIDTH
            local nx = dragFrameOrigin.x + (p.x - dragStartPoint.x)
            local ny = dragFrameOrigin.y + (p.y - dragStartPoint.y)
            nx = math.max(sf.x, math.min(nx, sf.x + sf.w - bw))
            ny = math.max(sf.y, math.min(ny, sf.y + sf.h - HEIGHT))
            setBannerFrame(nx, ny)
        else
            -- 与拖动时相同的 clamp：mouseUp 保存的是未约束坐标，
            -- 拖出屏幕后直接落盘 → 重启后 banner 在屏幕外找不到
            local sf = hs.screen.mainScreen():frame()
            local bw = drawings[1] and drawings[1]:frame().w or WIDTH
            local nx = dragFrameOrigin.x + (p.x - dragStartPoint.x)
            local ny = dragFrameOrigin.y + (p.y - dragStartPoint.y)
            nx = math.max(sf.x, math.min(nx, sf.x + sf.w - bw))
            ny = math.max(sf.y, math.min(ny, sf.y + sf.h - HEIGHT))
            M.savePos(nx, ny)
            stopDragTap()
        end
        return true   -- 吞掉拖动/抬起事件，不穿透到底层窗口
    end)
    dragTap:start()
end

--- 全局按下检测：命中条内 → 吞掉事件并启动拖动
local function onMouseDown(e)
    if not drawings[1] then return false end
    local p = hs.geometry.point(e:location())
    local f = drawings[1]:frame()
    if p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then
        startDragTap()
        return true    -- 吞掉按下事件，底层窗口不收到点击
    end
    return false
end

--- 显示常驻条（重复调用会先清理旧的）
--- @param s table session.new 产物
function M.start(s)
    M.stop()
    sessionRef = s
    createDrawings()
    local p = M.loadPos()
    setBannerFrame(p.x, p.y)
    for _, d in ipairs(drawings) do d:show() end
    updateText()
    -- 全局按下检测：命中条内启动拖动（drawing 无鼠标事件，全靠 eventtap）
    downTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(e)
        return onMouseDown(e)
    end)
    downTap:start()
    ticker = hs.timer.doEvery(1, updateText)
    breathTimer = hs.timer.doEvery(0.08, breath)
end

--- 隐藏并销毁常驻条
function M.stop()
    stopDragTap()
    if downTap then downTap:stop() downTap = nil end
    if ticker then ticker:stop() ticker = nil end
    if breathTimer then breathTimer:stop() breathTimer = nil end
    for _, d in ipairs(drawings) do d:delete() end
    drawings, relOffsets = {}, {}
    sessionRef = nil
end

return M

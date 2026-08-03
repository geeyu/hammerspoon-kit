--- === StayAwake ===
---
--- 防睡眠工具（对标 Amphetamine）：防止系统睡眠/显示器睡眠。
--- 入口：Launcher 命令提供者（launcher-commands.lua，自动发现）→ 公开 API；
---       面板内 iframe 子页面管理（状态/模式/永久/小时/分钟/直到/关闭，经 /stayawake/api 交互）。
--- 激活时右上角常驻半透明倒计时条（banner）。
--- 架构分层：
---   init.lua                装配层（命令提供者 / HTTP API / caffeinate 断言）
---   internal/timeutil.lua   时间解析/格式化（纯函数）
---   internal/session.lua    会话状态机（permanent/timer/until）
---   internal/settings.lua   配置持久化（mode 记忆）
---   internal/banner.lua     常驻右上角倒计时条（hs.canvas）
---   views/                  iframe 管理页面（views/pages/ 规范）
---
--- 用法：
---   local sw = hs.loadSpoon("StayAwake")
---   sw:start()
--- ============================================================

local obj = {}

obj.name = "StayAwake"
obj.version = "3.0.0"
obj.author = "geeyu"
obj.homepage = "https://github.com/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- 定位本 spoon 目录
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local spoonPath = script_path()
local loadMod = function(n) return dofile(spoonPath .. "internal/" .. n) end

local timeutil = loadMod("timeutil.lua")
local session  = loadMod("session.lua")
local settings = loadMod("settings.lua")
local banner   = loadMod("banner.lua")

obj.logger = hs.logger.new("StayAwake", "info")

-- 运行态
local current     = nil   -- 当前会话（session.new 产物）
local mode        = "system" -- "system"=允许息屏 | "all"=屏幕常亮
local settingsFile = os.getenv("HOME") .. "/.hammerspoon/data/StayAwake/settings.json"
local assertions  = {}    -- caffeinate 断言类型标记（system/display）
local apiMounted  = false -- HTTP 路由是否已挂载

-- ============ caffeinate 断言 ============

local function releaseAll()
    if assertions.system then
        hs.caffeinate.allowIdleSystemSleep()
        assertions.system = nil
    end
    if assertions.display then
        hs.caffeinate.allowIdleDisplaySleep()
        assertions.display = nil
    end
end

--- 按当前状态应用断言：有会话则断言，无会话则全释放
--- @return boolean 成功标志（system 失败=false；display 失败降级保留 system）
local function applyCaffeinate()
    releaseAll()
    if current == nil then return true end
    local ok = pcall(hs.caffeinate.preventIdleSystemSleep)
    if not ok then
        hs.alert.show("StayAwake：防睡眠断言失败")
        return false
    end
    assertions.system = true
    if mode == "all" then
        local ok2 = pcall(hs.caffeinate.preventIdleDisplaySleep)
        if not ok2 then
            -- 降级处理：保留系统断言，仅屏幕会息；不整体回滚会话
            hs.alert.show("StayAwake：屏幕常亮断言失败")
        else
            assertions.display = true
        end
    end
    return true
end

-- ============ 会话生命周期 ============

local function endSession(quiet)
    if current then
        session.cancel(current)
    end
    current = nil
    banner.stop()
    applyCaffeinate()
    if not quiet then hs.alert.show("防睡眠已恢复") end
end

--- 开启新会话（替换旧的）
--- @param sessionType string
--- @param params table
--- @param notice string|nil 提示文案
local function startSession(sessionType, params, notice)
    if current then session.cancel(current) end
    current = session.new(sessionType, params, os.time(), nil, function()
        -- 到期回调：自动结束
        endSession(false)
    end)
    if not current then
        hs.alert.show("StayAwake：会话创建失败")
        return false
    end
    if not applyCaffeinate() then
        -- 系统断言失败：回滚会话，避免状态不一致（alert 已由 applyCaffeinate 提示）
        session.cancel(current)
        current = nil
        banner.stop()
        return false
    end
    banner.start(current)
    if notice then hs.alert.show(notice) end
    return true
end

-- ============ 模式切换 ============

local function setMode(m)
    mode = (m == "all") and "all" or "system"
    settings.save(settingsFile, { mode = mode })
    applyCaffeinate()
end

-- ============ 动作分发（子页面 API 调用） ============

--- 处理子页面动作。返回 {ok, msg}
--- @param action string "permanent"|"timer"|"until"|"mode"|"close"
--- @param params table {minutes=, endsAt=, mode=}
local function doAction(action, params)
    params = params or {}
    if action == "permanent" then
        return startSession("permanent", {}, "保持清醒：永久"), nil
    elseif action == "timer" then
        local minutes = tonumber(params.minutes)
        if not minutes or minutes <= 0 then
            return false, "时长无效"
        end
        return startSession("timer", { minutes = minutes },
            string.format("保持清醒：%d 分钟", minutes)), nil
    elseif action == "until" then
        local endsAt = timeutil.parseDateTime(tostring(params.endsAt or ""))
        if not endsAt then
            return false, "时间格式无效，应为：yyyy-MM-dd HH:mm:ss"
        end
        if endsAt <= os.time() then
            return false, "时间已过"
        end
        return startSession("until", { endsAt = endsAt },
            "保持清醒：直到 " .. timeutil.formatTime(endsAt)), nil
    elseif action == "mode" then
        setMode(params.mode)
        return true, "模式已切换：" .. ((params.mode == "all") and "屏幕常亮" or "允许息屏")
    elseif action == "close" then
        endSession(false)
        return true, "防睡眠已恢复"
    end
    return false, "未知动作: " .. tostring(action)
end

-- ============ 公开 API（供 Launcher 命令提供者调用）============

--- 启动定时防睡眠（分钟）
function obj:startTimer(minutes)
    local ok, msg = doAction("timer", { minutes = tonumber(minutes) or 60 })
    return ok, msg
end

--- 永久防睡眠
function obj:startPermanent()
    local ok, msg = doAction("permanent", {})
    return ok, msg
end

--- 防睡眠直到指定时间（yyyy-MM-dd HH:mm:ss）
function obj:startUntil(timeStr)
    local ok, msg = doAction("until", { endsAt = timeStr })
    return ok, msg
end

--- 停止防睡眠
function obj:stopAwake()
    local ok, msg = doAction("close", {})
    return ok, msg
end

-- ============ HTTP API（HSUtil 共享 server） ============

local function mountAPI()
    if apiMounted then return end
    local ok, HSUtil = pcall(require, "core.hsutil")
    if not ok or not HSUtil or not HSUtil.http or not HSUtil.http.app then
        obj.logger.w("HSUtil 未加载，跳过 HTTP API")
        return
    end
    local app = HSUtil.http.app

    -- 子页面静态文件
    app:static("/stayawake/view", spoonPath .. "views")

    -- 状态查询
    app:get("/stayawake/api/state", function(req, res)
        local remaining
        if current and current.endsAt then
            remaining = session.remaining(current)
        end
        res:json({
            active = current ~= nil,
            type = current and current.type or nil,
            remaining = remaining,      -- 秒；permanent/未激活为 nil
            endsAt = current and current.endsAt and timeutil.formatTime(current.endsAt) or nil,
            mode = mode,
            version = obj.version,
        })
    end)

    -- 动作执行
    app:post("/stayawake/api/action", function(req, res)
        local body = req:json() or {}
        local action = tostring(body.action or "")
        local ok, msg = doAction(action, body)
        res:json({ ok = ok == true, msg = msg or "" })
    end)

    apiMounted = true
    obj.logger.i("StayAwake HTTP API 已挂载（/stayawake/api/*）")
end

-- ============ Spoon 生命周期 ============

--- 启动：恢复模式 + 挂 API
function obj:start()
    -- 恢复上次模式
    mode = settings.load(settingsFile).mode
    -- 挂 HTTP API（子页面数据通道）
    mountAPI()

    return obj
end

--- 停止：清理 banner 与断言
function obj:stop()
    endSession(true)
    obj.logger.i("StayAwake 已停止")
end

return obj

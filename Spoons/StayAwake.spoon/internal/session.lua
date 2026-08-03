--- StayAwake.internal.session
--- 会话状态机：permanent（无限期）/ timer（N 分钟）/ until（到时间点）。
--- 单一会话模型：新会话替换旧会话（调用方负责 cancel 旧会话 timer）。
--- timerApi 依赖注入（默认 hs.timer），便于测试。
local M = {}

--- 默认 timer 实现（Hammerspoon 环境）
local function defaultTimer()
    return {
        after = function(sec, fn) return hs.timer.doAfter(sec, fn) end,
        -- 本版本无 hs.timer.cancel 静态方法，用 timer 对象 :stop()
        cancel = function(id) if id then id:stop() end end,
    }
end

--- 创建会话。成功返回会话表；失败返回 nil, err。
--- @param sessionType string "permanent"|"timer"|"until"
--- @param params table {minutes=number} 或 {endsAt=number（os.time 秒）}
--- @param now number 当前时间戳（秒）
--- @param timerApi table|nil 注入 {after, cancel}
--- @param onExpire function|nil 到期回调 function(session)
function M.new(sessionType, params, now, timerApi, onExpire)
    params = params or {}
    now = now or os.time()
    timerApi = timerApi or defaultTimer()

    local endsAt
    if sessionType == "permanent" then
        endsAt = nil
    elseif sessionType == "timer" then
        local minutes = tonumber(params.minutes)
        if not minutes or minutes <= 0 then return nil, "invalid minutes" end
        endsAt = now + minutes * 60
    elseif sessionType == "until" then
        local ts = tonumber(params.endsAt)
        if not ts then return nil, "invalid endsAt" end
        if ts <= now then return nil, "past" end
        endsAt = ts
    else
        return nil, "unknown type"
    end

    local self = {
        type = sessionType,
        endsAt = endsAt,
        timerId = nil,
        expired = false,
        onExpire = onExpire, -- function(session)
    }
    if endsAt then
        self.timerId = timerApi.after(endsAt - now, function()
            self.expired = true
            if self.onExpire then self.onExpire(self) end
        end)
    end
    return self
end

--- 取消会话（透传 cancel 到 timerApi）
--- @param s table session.new 产物
--- @param timerApi table|nil 注入（需与创建时同一实例，或提供 cancel）
function M.cancel(s, timerApi)
    if not s then return end
    timerApi = timerApi or defaultTimer()
    if s.timerId then
        timerApi.cancel(s.timerId)
        s.timerId = nil
    end
end

--- 剩余秒数；permanent 返回 nil（无限）
function M.remaining(s, now)
    now = now or os.time()
    if not s.endsAt then return nil end
    return math.max(0, s.endsAt - now)
end

--- 是否已到期（timer/until 到时，或已被回调标记）
function M.isExpired(s, now)
    now = now or os.time()
    if s.expired then return true end
    if not s.endsAt then return false end
    return s.endsAt <= now
end

return M

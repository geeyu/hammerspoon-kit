--- StayAwake.internal.timeutil
--- 纯函数时间工具（无 hs 依赖，可单测）。
local M = {}

--- 解析 "yyyy-MM-dd HH:mm[:ss]" → os.time 秒数；非法返回 nil
function M.parseDateTime(str)
    if type(str) ~= "string" then return nil end
    -- 秒部分要么全缺、要么以冒号前导 1-2 位数字（拒绝 "18:30:" 这类畸形输入）。
    -- 注：Lua 模式不支持对捕获组加量词（(...)? 中 ? 会被当字面量），故拆成两个模式：
    -- 带秒 / 不带秒，语义与单个可选组完全等价。
    local y, mo, d, h, mi, s =
        str:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d?)$")
    if not y then
        y, mo, d, h, mi = str:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)$")
        if not y then return nil end
        s = 0
    else
        s = tonumber(s)
    end
    if s > 59 then return nil end
    -- Lua 5.4 的 os.time 会就地归一化表 t（2026-13 → 2027-1），
    -- 先复制原始值，回验时与被改写后的 t 无关
    local t = {
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = s,
    }
    local orig = { year = t.year, month = t.month, day = t.day,
        hour = t.hour, min = t.min, sec = t.sec }
    local ok, ts = pcall(os.time, t)
    if not ok then return nil end
    -- os.time 对非法日期会归一化（2月30日→3月2日），回验拦截
    local back = os.date("*t", ts)
    if back.year ~= orig.year or back.month ~= orig.month or back.day ~= orig.day
        or back.hour ~= orig.hour or back.min ~= orig.min or back.sec ~= orig.sec then
        return nil
    end
    return ts
end

--- 秒数 → "H:MM:SS"（不足 1 小时显示 "MM:SS"）
function M.formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

--- os.time 秒数 → "yyyy-MM-dd HH:mm:ss"
function M.formatTime(ts)
    return os.date("%Y-%m-%d %H:%M:%S", ts)
end

return M

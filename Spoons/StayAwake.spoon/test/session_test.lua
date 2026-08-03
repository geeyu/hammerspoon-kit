--- session 会话状态机测试（timer 依赖注入，不触真实定时器）
local session = dofile(spoonDir .. "/internal/session.lua")

print("[session]")

-- fake timer：捕获 after/cancel 调用
local function fakeTimer()
    local calls = {}
    return {
        calls = calls,
        after = function(sec, fn)
            table.insert(calls, { sec = sec, fn = fn })
            return #calls
        end,
        cancel = function(id)
            table.insert(calls, { cancel = id })
        end,
    }
end

local NOW = 1000000

-- timer 会话
local t1 = fakeTimer()
local s = session.new("timer", { minutes = 90 }, NOW, t1)
expectEqual("timer endsAt", s.endsAt, NOW + 5400)
expectEqual("timer 注册定时器秒数", t1.calls[1].sec, 5400)
expectEqual("remaining 计算", session.remaining(s, NOW + 100), 5300)
expectEqual("remaining 归零", session.remaining(s, NOW + 5400), 0)
check("未到期", not session.isExpired(s, NOW + 5399))
check("到点即到期", session.isExpired(s, NOW + 5400))

-- 非法参数
expectNil("timer minutes=0", session.new("timer", { minutes = 0 }, NOW, t1))
expectNil("timer 缺 minutes", session.new("timer", {}, NOW, t1))
expectNil("未知类型", session.new("foo", {}, NOW, t1))

-- until 会话
local s2 = session.new("until", { endsAt = NOW + 60 }, NOW, t1)
expectEqual("until endsAt", s2.endsAt, NOW + 60)
expectNil("until 时间已过", session.new("until", { endsAt = NOW }, NOW, t1))
expectNil("until 缺 endsAt", session.new("until", {}, NOW, t1))

-- permanent 会话
local s3 = session.new("permanent", {}, NOW, t1)
expectNil("permanent endsAt 为 nil", s3.endsAt)
expectNil("permanent remaining 为 nil", session.remaining(s3, NOW + 999))
check("permanent 永不到期", not session.isExpired(s3, NOW + 999999))

-- 到期回调：timer 触发时标记 expired 并调用 onExpire
local captured, fired
local s4 = session.new("timer", { minutes = 1 }, NOW, {
    after = function(sec, fn) captured = fn return 1 end,
    cancel = function() end,
})
s4.onExpire = function() fired = true end
captured()
check("到期回调触发", fired == true)
check("expired 标记", s4.expired == true)

-- cancel 透传：新会话替换旧会话时调用方需 cancel 旧 timer
local t5 = fakeTimer()
local s5 = session.new("timer", { minutes = 1 }, NOW, t5)
session.cancel(s5, t5)
expectEqual("cancel 透传 timerId", t5.calls[2].cancel, 1)

-- 真实 timer 集成（Hammerspoon 环境）：defaultTimer 的 cancel 必须能停掉真实 timer
local s6 = session.new("timer", { minutes = 1 }, os.time())
check("真实 timer 创建", s6.timerId ~= nil)
check("真实 timer 运行中", s6.timerId:running() == true)
session.cancel(s6)
check("真实 timer cancel 后停止", s6.timerId == nil)

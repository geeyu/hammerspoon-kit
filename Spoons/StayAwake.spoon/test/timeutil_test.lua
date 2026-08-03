--- timeutil 纯函数测试
local timeutil = dofile(spoonDir .. "/internal/timeutil.lua")

print("[timeutil]")

-- 解析合法输入
local ts = timeutil.parseDateTime("2026-08-01 18:30:00")
expectEqual("完整时间解析", ts, os.time({ year = 2026, month = 8, day = 1, hour = 18, min = 30, sec = 0 }))
local ts2 = timeutil.parseDateTime("2026-08-01 18:30")
expectEqual("省略秒解析", ts2, os.time({ year = 2026, month = 8, day = 1, hour = 18, min = 30, sec = 0 }))

-- 解析非法输入 → nil
expectNil("非字符串", timeutil.parseDateTime(123))
expectNil("垃圾输入", timeutil.parseDateTime("hello"))
expectNil("月份越界", timeutil.parseDateTime("2026-13-01 18:30:00"))
expectNil("日期越界", timeutil.parseDateTime("2026-02-30 18:30:00"))
expectNil("小时越界", timeutil.parseDateTime("2026-08-01 25:30:00"))
expectNil("秒越界", timeutil.parseDateTime("2026-08-01 18:30:61"))
expectNil("分钟越界", timeutil.parseDateTime("2026-08-01 18:65:00"))
expectNil("缺时间部分", timeutil.parseDateTime("2026-08-01"))
expectNil("空串", timeutil.parseDateTime(""))
expectNil("畸形尾随冒号", timeutil.parseDateTime("2026-08-01 18:30:"))

-- 时长格式化
expectEqual("时长 1h2m5s", timeutil.formatDuration(3725), "1:02:05")
expectEqual("时长 45m", timeutil.formatDuration(2700), "45:00")
expectEqual("时长 0", timeutil.formatDuration(0), "0:00")
expectEqual("时长负数归零", timeutil.formatDuration(-5), "0:00")

-- formatTime 与 parseDateTime 往返
local now = os.time()
expectEqual("formatTime 往返", timeutil.parseDateTime(timeutil.formatTime(now)), now)

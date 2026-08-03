--- banner 常驻倒计时条测试（纯函数 formatText + 位置持久化；canvas/timer 不触）
local banner = dofile(spoonDir .. "/internal/banner.lua")
local settings = dofile(spoonDir .. "/internal/settings.lua")

print("[banner]")

-- formatText 纯函数
expectEqual("permanent 文案", banner.formatText("permanent", nil), "保持清醒中（无限期）")
expectEqual("timer 倒计时", banner.formatText("timer", 3725), "保持清醒中（剩余 1:02:05）")
expectEqual("until 倒计时", banner.formatText("until", 65), "保持清醒中（剩余 1:05）")
expectEqual("timer 0 秒", banner.formatText("timer", 0), "保持清醒中（剩余 0:00）")
expectNil("未知类型", banner.formatText("foo", 100))
expectNil("缺剩余秒数", banner.formatText("timer", nil))

-- 位置持久化：savePos → loadPos 往返（真实 hs.json + /tmp 文件）
local dir = "/tmp/stayawake_banner_" .. tostring(os.time())
os.execute('mkdir -p "' .. dir .. '"')
local file = dir .. "/settings.json"

check("savePos 成功", banner.savePos(1234, 567, file, settings) ~= nil)
local p1 = banner.loadPos(file, settings)
check("位置往返", p1.x == 1234 and p1.y == 567, string.format("got %s,%s", tostring(p1.x), tostring(p1.y)))

-- 共存：bannerPos 不破坏 mode 字段
local s = settings.load(file)
expectEqual("mode 保留", s.mode, "system")
check("bannerPos 共存", s.bannerPos ~= nil and s.bannerPos.x == 1234)

-- 缺失文件 → 默认位置（primaryScreen 在 hs 环境可用）
local p2 = banner.loadPos(dir .. "/missing.json", settings)
check("缺失回退默认", type(p2.x) == "number" and type(p2.y) == "number")

-- 损坏 JSON → 默认位置
local f = io.open(file, "w")
f:write("{bad json")
f:close()
local p3 = banner.loadPos(file, settings)
check("损坏回退默认", type(p3.x) == "number" and type(p3.y) == "number")

-- 清理
os.execute("rm -rf " .. dir)

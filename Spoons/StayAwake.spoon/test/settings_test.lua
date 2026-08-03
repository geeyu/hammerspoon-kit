--- settings 配置持久化测试（json 依赖注入 + /tmp 临时目录）
local settings = dofile(spoonDir .. "/internal/settings.lua")

print("[settings]")

-- fake json（验证读写逻辑，不依赖 hs.json）
local fakeJson = {
    encode = function(v)
        return string.format('{"mode":"%s"}', v.mode or "")
    end,
    decode = function(s)
        local mode = s:match('"mode"%s*:%s*"([^"]+)"')
        if not mode then error("bad json: " .. tostring(s)) end
        return { mode = mode }
    end,
}

local dir = "/tmp/stayawake_test_" .. tostring(os.time())
local file = dir .. "/settings.json"

-- 文件不存在 → 默认值
local d1 = settings.load(file, fakeJson)
expectEqual("不存在返回默认 mode", d1.mode, "system")

-- 保存后读回一致
check("保存成功", settings.save(file, { mode = "all" }, fakeJson))
local d2 = settings.load(file, fakeJson)
expectEqual("读回 mode", d2.mode, "all")

-- 损坏 JSON → 回退默认
local f = io.open(file, "w")
f:write("{bad json")
f:close()
local d3 = settings.load(file, fakeJson)
expectEqual("损坏回退默认", d3.mode, "system")

-- 未知 mode 值 → 归一化回默认
settings.save(file, { mode = "weird" }, fakeJson)
local d4 = settings.load(file, fakeJson)
expectEqual("未知 mode 归一化", d4.mode, "system")

-- 清理
os.execute("rm -rf " .. dir)

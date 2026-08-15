--- QuantumWindow 测试入口（Hammerspoon 环境运行）
--- 运行：hs -c "dofile('/Users/geeyu/.hammerspoon/Spoons/QuantumWindow.spoon/test/run.lua')"
--- 注意：不用 os.exit（hs -c IPC 环境可能终止 Hammerspoon），失败只打印。
results = { pass = 0, fail = 0 }

function check(name, cond, detail)
    if cond then
        print("  \u{2713} " .. name)
        results.pass = results.pass + 1
    else
        print("  \u{2717} " .. name .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
        results.fail = results.fail + 1
    end
end

function expectEqual(name, actual, expected)
    check(name, actual == expected,
        string.format("got %s, want %s", tostring(actual), tostring(expected)))
end

function expectNil(name, v)
    check(name, v == nil, "got " .. tostring(v))
end

-- 定位 test/ 目录 → spoon 根目录（全局，供各 *_test.lua 使用）
local src = debug.getinfo(1, "S").source:sub(2)
local testDir = src:match("^(.*)/[^/]+$")
spoonDir = testDir .. "/.."

dofile(testDir .. "/config_test.lua")
dofile(testDir .. "/actions_test.lua")
dofile(testDir .. "/notify_test.lua")

print(string.format("\n结果：%d 通过，%d 失败", results.pass, results.fail))

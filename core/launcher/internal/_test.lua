--- Launcher.internal._test
--- 自测脚本（Hammerspoon console 用）。与纯 Lua unit_test.lua 互补：
--- 此文件在真实 HS 环境跑，可验证真 hs.* 下的 registry 聚合。
--- console:  require("core.launcher.internal._test").run()
local test = {}

local results = { pass = 0, fail = 0 }
local function check(name, cond, detail)
    if cond then
        print("  \u{2713} " .. name); results.pass = results.pass + 1
    else
        print("  \u{2717} " .. name .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
        results.fail = results.fail + 1
    end
end

function test.run(done)
    results = { pass = 0, fail = 0 }

    local HSUtil = require("core.hsutil")
    local dir = (function()
        local s = debug.getinfo(1, "S").source:sub(2)
        return s:match("(.*[/\\])") or ""
    end)()
    local config = dofile(dir .. "config.lua")
    config.views_dir = hs.configdir .. "/core/launcher/views"
    config.enabled_sources = { "calc", "urlformats", "screencapture", "useractions", "custom" }
    config.url_providers = { gh = { name = "GitHub", url = "https://github.com/search?q=%s" } }

    local registry = dofile(dir .. "registry.lua")
    local ok, err = pcall(function() registry.setup(config) end)
    check("registry.setup 无错误", ok, tostring(err))
    if not ok then
        print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
        if done then done() end
        return test
    end

    -- calc
    local q = registry.query("2+3")
    local cr
    for _, r in ipairs(q.rows) do if r.plugin == "calc" then cr = r end end
    check("calc 2+3 → 5", cr and tostring(cr.text) == "5", cr and tostring(cr.text))

    -- urlformat 关键词
    local q2 = registry.query("uf hs")
    check("'uf hs' 识别关键词 uf", q2.keyword == "uf", tostring(q2.keyword))
    check("'uf hs' 产出 provider", #q2.rows > 0)

    -- custom 命令
    local config2 = dofile(dir .. "config.lua")
    config2.enabled_sources = { "custom" }
    config2.custom_commands = { demo = { keyword = "demo", title = "Demo", kind = "shell", exec = { "/bin/echo", { "hi ${query}" } } } }
    local reg2 = dofile(dir .. "registry.lua").setup(config2)
    local q3 = reg2.query("demo x")
    check("custom 'demo x' 识别", q3.keyword == "demo", tostring(q3.keyword))

    -- registerProvider 冒烟：运行时注册一张卡片应立即可查
    local okReg = pcall(function()
        registry.registerProvider("_smoke", {
            cards = { ["冒烟卡片"] = { description = "smoke", kind = "shell", exec = { "/bin/echo", {} } } },
        })
    end)
    local smokeFound = false
    local qs = registry.query("")
    for _, r in ipairs(qs.rows) do
        if r.plugin == "cards" and r.text == "冒烟卡片" then smokeFound = true end
    end
    check("registerProvider 冒烟：实时刷新", okReg and smokeFound)

    print(string.format("\n结果: %d 通过, %d 失败", results.pass, results.fail))
    if done then done() end
    return test
end

return test

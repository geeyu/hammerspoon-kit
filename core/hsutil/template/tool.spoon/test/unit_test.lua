--- Tool.internal.test —— 模板骨架测试。
--- 仿 core/hsutil/internal/_test.lua 的 check 模式。
--- 注意：internal/example.lua 的 register() 依赖 hs.loadSpoon 环境，本测试
--- 不加载 hs，只测纯逻辑部分；复制本包后按需补充业务测试。
local test = {}

-- 独立运行（lua5.4 .../test/unit_test.lua）：直接 dofile 加载 example.lua，
-- 避免 require 路径与 spoon 目录名（tool.spoon）的映射问题，模板改名后依然有效
local spoonDir = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/test/unit_test%.lua$")

local results = { pass = 0, fail = 0 }

local function check(name, cond, detail)
    if cond then
        print("  \u{2713} " .. name)
        results.pass = results.pass + 1
    else
        print("  \u{2717} " .. name .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
        results.fail = results.fail + 1
    end
end

--- example.lua 纯逻辑测试：用 stub HSUtil 捕获路由注册
local function testExampleRegister()
    print("[internal/example]")
    local routes = {}
    local stub = {
        http = {
            app = {
                get = function(self, path, handler)
                    routes[path] = handler
                end,
            },
        },
    }
    local example = dofile(spoonDir .. "/internal/example.lua")
    example.register(stub)
    check("register 注册 /api/tool/hello", routes["/api/tool/hello"] ~= nil)
    check("register 注册 /api/tool/items", routes["/api/tool/items"] ~= nil)
    local n = 0
    for _ in pairs(routes) do n = n + 1 end
    check("register 仅注册 2 条路由", n == 2, n)
    check("register 路由总数", n == 2, n)
end

--- example.lua 响应逻辑测试：handler 返回 JSON 结构正确
local function testExampleResponses()
    print("[internal/example responses]")
    local routes = {}
    local stub = {
        http = {
            app = {
                get = function(self, path, handler)
                    routes[path] = handler
                end,
            },
        },
    }
    local example = dofile(spoonDir .. "/internal/example.lua")
    example.register(stub)

    -- 模拟 res 对象，捕获 json 负载
    local captured
    local fakeRes = {
        json = function(self, payload)
            captured = payload
        end,
    }
    routes["/api/tool/hello"](nil, fakeRes)
    check("hello 返回 message", captured and captured.message == "hello from Tool", captured and captured.message)
    check("hello 返回 time", captured and type(captured.time) == "number", captured and captured.time)

    captured = nil
    routes["/api/tool/items"](nil, fakeRes)
    check("items 返回数组", captured and type(captured.items) == "table", type(captured))
    check("items 3 条", captured and #captured.items == 3, captured and #captured.items)
    check("items 首条字段", captured and captured.items[1].name == "示例 A", captured and captured.items[1] and captured.items[1].name)
end

function test.run()
    results = { pass = 0, fail = 0 }
    print("=== Tool template 自测 ===")
    local ok, err = pcall(testExampleRegister)
    if not ok then check("example register suite", false, err) end
    ok, err = pcall(testExampleResponses)
    if not ok then check("example responses suite", false, err) end
    print(string.format("\n=== 结果: %d 通过, %d 失败 ===", results.pass, results.fail))
    return results.fail == 0
end

-- 直接运行（lua5.4 tool.spoon/test/unit_test.lua）
local ok = test.run()
if not ok then os.exit(1) end

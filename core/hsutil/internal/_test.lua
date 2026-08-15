--- HSUtil.internal._test
--- 自测脚本。console: require("HSUtil.internal._test").run()
--- HTTP/static 测试用 hs.task 异步 curl（不阻塞主线程，避免死锁）。
local test = {}

local results = { pass = 0, fail = 0 }
local pending = 0
local doneCb = nil

local function check(name, cond, detail)
    if cond then
        print("  \u{2713} " .. name)
        results.pass = results.pass + 1
    else
        print("  \u{2717} " .. name .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
        results.fail = results.fail + 1
    end
end

--- 异步 curl：完成后回调(stdout, exitCode)
local function curlAsync(port, path, method, body, cb)
    local args = { "-s", "--max-time", "3" }
    if method then
        table.insert(args, "-X")
        table.insert(args, method)
    end
    if body then
        table.insert(args, "-d")
        table.insert(args, body)
    end
    table.insert(args, "http://127.0.0.1:" .. port .. path)
    local t = require("hs.task").new("/usr/bin/curl", function(code, out)
        cb(out or "", code)
    end, args)
    t:start()
end

local function curlCodeAsync(port, path, method, cb)
    local args = { "-s", "-o", "/dev/null", "--max-time", "3", "-w", "%{http_code}" }
    if method then
        table.insert(args, "-X")
        table.insert(args, method)
    end
    table.insert(args, "http://127.0.0.1:" .. port .. path)
    local t = require("hs.task").new("/usr/bin/curl", function(code, out)
        cb(out or "", code)
    end, args)
    t:start()
end

--- ORM 测试（纯内存，同步安全）
local function testORM()
    print("[ORM]")
    os.remove("/tmp/hsutil_test_orm.db")
    local conn = require("HSUtil.internal.db.connection")
    local orm = require("HSUtil.internal.db.orm")
    local db = conn.open("/tmp/hsutil_test_orm.db")
    local T = orm.define({
        table = "items",
        columns = {
            { name = "id", type = "INTEGER PRIMARY KEY AUTOINCREMENT" },
            { name = "name", type = "TEXT NOT NULL" },
            { name = "created", type = "INTEGER NOT NULL" },
        },
        indexes = { "idx_items_created ON items (created DESC)" },
    })
    T:bind(db)
    local id = T:insert({ name = "a", created = 1 })
    check("insert returns id", id and id > 0, id)
    local row = T:findById(id)
    check("findById name", row and row.name == "a", row and row.name)
    T:updateById(id, { name = "b" })
    check("updateById", T:findById(id).name == "b")
    check("count", T:count({ where = "name=?", binds = { "b" } }) == 1)
    T:insert({ name = "c", created = 2 })
    local rows, total = T:query({ where = "name LIKE ?", binds = { "%" }, limit = 10 })
    check("query total", total == 2, total)
    check("query rows", #rows == 2, #rows)
    T:deleteById(id)
    check("deleteById", T:count() == 1)
    conn.close(db)
end

--- migrate 测试（纯内存，同步安全）
local function testMigrate()
    print("[migrate]")
    os.remove("/tmp/hsutil_test_migrate.db")
    local conn = require("HSUtil.internal.db.connection")
    local migrate = require("HSUtil.internal.db.migrate")
    migrate.register("testm", 1, function(db) db:exec("CREATE TABLE m(v)") end)
    migrate.register("testm", 2, function(db) db:exec("INSERT INTO m VALUES(1)") end)
    local db = conn.open("/tmp/hsutil_test_migrate.db")
    check("apply v1+v2", migrate.apply(db, "testm") == 2)
    check("idempotent", migrate.apply(db, "testm") == 2)
    local n = 0
    for r in db:nrows("SELECT COUNT(*) c FROM m") do n = r.c end
    check("migration ran once", n == 1, n)
    conn.close(db)
end

--- HTTP + static 测试（异步 curl）
local function testHTTPStatic()
    print("[HTTP + static]")
    local server = require("HSUtil.internal.http.server")
    local cors = require("HSUtil.internal.http.cors")
    local s = server.new({ port = 0, loopback = true })
    s:use(cors.new())
    s:get("/health", function(req, res) res:json({ ok = true }) end)
    s:get("/api/x/:id", function(req, res) res:json({ id = req.params.id }) end)
    s:post("/api/x", function(req, res) res:status(201):json({ got = req:json() }) end)
    s:static("/app", "/tmp/hsutil_test_static")
    s:start()
    local port = s:port()
    check("server started", port and port > 0, port)
    os.execute("mkdir -p /tmp/hsutil_test_static && echo '<h1>hi</h1>' > /tmp/hsutil_test_static/index.html")

    local step = 0
    local function next()
        step = step + 1
        if step == 1 then
            curlAsync(port, "/health", nil, nil, function(out)
                check("GET /health", out:find('"ok":true') ~= nil, out)
                next()
            end)
        elseif step == 2 then
            curlAsync(port, "/api/x/42", nil, nil, function(out)
                check("GET :param", out:find('"42"') ~= nil, out)
                next()
            end)
        elseif step == 3 then
            curlAsync(port, "/api/x", "POST", '{"a":1}', function(out)
                check("POST json", out:find('"got"') ~= nil, out)
                next()
            end)
        elseif step == 4 then
            curlCodeAsync(port, "/health", "OPTIONS", function(out)
                check("OPTIONS 204", out == "204", out)
                next()
            end)
        elseif step == 5 then
            curlCodeAsync(port, "/nope", nil, function(out)
                check("404", out == "404", out)
                next()
            end)
        elseif step == 6 then
            curlAsync(port, "/app/", nil, nil, function(out)
                check("static index", out:find("<h1>hi</h1>") ~= nil, out)
                next()
            end)
        elseif step == 7 then
            curlCodeAsync(port, "/app/../../../etc/passwd", nil, function(out)
                check("traversal blocked", out == "403" or out == "404", out)
                next()
            end)
        else
            s:stop()
            pending = pending - 1
            if pending == 0 and doneCb then doneCb() end
        end
    end
    next()
end

--- task 测试（spawn + stream + stdin + 超时）
local function testTask()
    print("[task]")
    local task = require("HSUtil.internal.task")

    -- 1. run() 便捷（用 waitUntilExit 同步等）
    local r1
    local tr = task.run("/bin/echo", {"hi"}, function(o, e, c)
        r1 = (o or ""):gsub("%s+$", "")
    end)
    tr:waitUntilExit()
    check("run() echo", r1 == "hi", r1)

    -- 2. spawn + onDone + pid + exitCode
    local j2_done, j2_code, j2_pid
    local j2 = task.spawn("/bin/echo", {"hello"})
        :cwd("/tmp")
        :onDone(function(c, o) j2_done = true; j2_code = c end)
        :start()
    j2_pid = j2:pid()
    j2:raw():waitUntilExit()
    check("spawn pid", j2_pid and j2_pid > 0, j2_pid)
    check("spawn exitCode", j2:exitCode() == 0, j2:exitCode())
    check("spawn exitReason", j2:exitReason() == "exit", j2:exitReason())

    -- 3. stream + stdin + closeInput（grep 匹配）
    local matched = {}
    local j3 = task.spawn("/usr/bin/grep", {"match"})
        :write("nope\nmatch me\nbye\n")
        :closeInput()
        :onStream(function(o)
            if o and o ~= "" then
                local s = (o:gsub("%s+$", ""))
                table.insert(matched, s)
            end
            return true
        end)
        :onDone(function(c) check("grep done", c == 0, c) end)
        :start()
    j3:raw():waitUntilExit()
    check("grep stdin+stream", table.concat(matched) == "match me", table.concat(matched))

    -- 4. 超时 kill
    local t4_code, t4_err
    local j4 = task.spawn("/bin/sleep", {"10"})
        :timeout(0.5)
        :onDone(function(c, o, e) t4_code = c; t4_err = e end)
        :start()
    j4:raw():waitUntilExit()
    check("timeout kill", t4_code == -1 and t4_err == "timeout", t4_code)
    check("timeout exitReason", j4:exitReason() == "interrupt", j4:exitReason())
end

function test.run()
    results = { pass = 0, fail = 0 }
    pending = 3  -- ORM+migrate 同步算2组，HTTP+static 异步算1组，task 同步算... 见下
    print("=== HSUtil 自测 ===")
    local ok, err
    ok, err = pcall(testORM)
    if not ok then check("ORM suite", false, err) end
    ok, err = pcall(testMigrate)
    if not ok then check("migrate suite", false, err) end
    ok, err = pcall(testTask)
    if not ok then check("task suite", false, err) end

    --- ui.lua：占位符展开（纯函数，同步）
    local ui = require("HSUtil.internal.ui")
    local hsRoot = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/core/hsutil/internal/_test%.lua$")
    -- 资产目录与 _test.lua 同级（…/core/hsutil/assets），不能取仓库根下的 assets
    ui.init(hsRoot .. "/core/hsutil/assets")

    local html = [[
<!DOCTYPE html><html><head><title>t</title></head><body>
<!-- hsutil:ui button,form -->
</body></html>
]]
    local out = ui.expand(html)
    check("ui.expand 注入 base.css", out:find("styles/base%.css") ~= nil)
    check("ui.expand 注入 page.css", out:find("styles/page%.css") ~= nil)
    check("ui.expand 展开顺序 theme→base→page", (function()
        local t = out:find("styles/theme%.css")
        local b = out:find("styles/base%.css")
        local p = out:find("styles/page%.css")
        return t ~= nil and b ~= nil and p ~= nil and t < b and b < p
    end)())
    check("ui.expand 注入 vue vendor", out:find("vendor/vue%.global%.prod%.js") ~= nil)
    check("ui.expand 注入 button js", out:find("ui%-button/index%.js") ~= nil)
    check("ui.expand 恒注入注册表 index.js", out:find("components/ui/index%.js") ~= nil)
    check("ui.expand index.js 在组件 js 之后", (function()
        local b = out:find("ui%-button/index%.js")
        local i = out:find("components/ui/index%.js")
        return b ~= nil and i ~= nil and i > b
    end)())
    check("ui.expand 依赖补齐 form->input", out:find("ui%-input/index%.js") ~= nil)
    check("ui.expand 依赖补齐 form->radio", out:find("ui%-radio/index%.js") ~= nil)
    check("ui.expand 依赖去重", (function()
        local _, n = out:gsub("ui%-input/index%.js", "")
        return n == 1
    end)())
    check("ui.expand tpl 内联", out:find('<template id="tpl%-ui%-button">') ~= nil)
    check("ui.expand 原 html 保留", out:find("<title>t</title>") ~= nil)

    local fxHtml = [[<!-- hsutil:fx glass -->]]
    local fxOut = ui.expand(fxHtml)
    check("ui.expand fx 注入 anime", fxOut:find("anime%.umd%.min%.js") ~= nil)
    check("ui.expand fx 注入 glass js", fxOut:find("glass%-fx/index%.js") ~= nil)
    check("ui.expand fx 注入 glass css", fxOut:find("glass%-fx/style%.css") ~= nil)

    local iconsHtml = [[<!-- hsutil:icons -->]]
    local iconsOut = ui.expand(iconsHtml)
    check("ui.expand icons 注入 iconpark", iconsOut:find("vendor/iconpark/iconpark%.umd%.min%.js") ~= nil)

    local iconCompHtml = [[<!-- hsutil:ui button -->]]
    local iconCompOut = ui.expand(iconCompHtml)
    check("ui.expand ui-icon 依赖带出 iconpark", iconCompOut:find("iconpark%.umd%.min%.js") ~= nil)
    check("ui.expand ui-icon 依赖带出组件", iconCompOut:find("ui%-icon/index%.js") ~= nil)

    local plain = ui.expand("<p>no placeholder</p>")
    check("ui.expand 无占位符原样返回", plain == "<p>no placeholder</p>")

    pending = pending - 2  -- ORM + migrate + task 同步完成
    -- HTTP/static 异步
    local ok2, err2 = pcall(testHTTPStatic)
    if not ok2 then
        check("HTTP suite", false, err2)
        pending = pending - 1
    end
    -- 用 timer 轮询 pending，完成后打印汇总
    doneCb = function()
        print(string.format("\n=== 结果: %d 通过, %d 失败 ===", results.pass, results.fail))
        -- 同时写文件，便于 ipc 取结果
        local f = io.open("/tmp/hsutil_test_result.txt", "w")
        if f then
            f:write(string.format("pass=%d\nfail=%d\n", results.pass, results.fail))
            f:close()
        end
    end
    return "running (HTTP async), 结果将稍后打印到 console"
end

return test

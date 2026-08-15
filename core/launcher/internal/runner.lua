--- Launcher.internal.runner
--- 候选选中后的动作执行统一分发。无状态 + 注入点（由 registry 注入）。
local runner = {}
local HSUtil = require("core.hsutil")
local taskUtil = HSUtil.task
local logger = HSUtil.log.new("Launcher.runner")

--- 执行一条候选（row 里含 type 及各动作所需字段）
--- @param row table 候选（来自 registry 聚合的各源 build 结果）
--- @return boolean|nil 成功与否
function runner.run(row)
    if not row or not row.type then
        logger.e("run: 缺 type"); return false
    end
    local t = row.type

    if t == "launchOrFocus" or t == "openApp" then
        -- apps：启动应用（若已在运行则聚焦到它）。path 必须存在。
        local p = row.path or ""
        if p ~= "" then
            if runner.bumpAppLaunch then runner.bumpAppLaunch(p) end
            taskUtil.run("/usr/bin/open", { p })
        elseif row.bundleID then
            hs.application.launchOrFocusByBundleID(row.bundleID)
        elseif row.name then
            hs.application.launchOrFocus(row.name)
        end

    elseif t == "launchChannel" then
        -- 频道：按应用名启动
        if row.appName then hs.application.launchOrFocus(row.appName) end

    elseif t == "focusApp" then
        local app = row.pid and hs.application.get(row.pid)
        if app then
            app:activate(true)
            app:setfrontmost(true)
        end

    elseif t == "newWindow" then
        -- 用 open -n 强制新实例/新窗口（比脚本点菜单更稳）：Finder 开新窗，浏览器开新实例等。
        if row.path then
            taskUtil.run("/usr/bin/open", { "-n", row.path })
        elseif row.bundleID then
            hs.application.launchOrFocusByBundleID(row.bundleID)
        end

    elseif t == "kill" then
        local app = hs.application.get(row.pid)
        if app then app:kill() end

    elseif t == "reveal" then
        hs.osascript.applescript(string.format(
            [[tell application "Finder" to reveal (POSIX file "%s")]], row.path))
        hs.application.launchOrFocus("Finder")

    elseif t == "openFile" then
        -- File 频道：用默认应用打开文件
        if row.path then
            taskUtil.run("/usr/bin/open", { row.path })
        end

    elseif t == "copyToClipboard" then
        hs.pasteboard.setContents(row.text)

    elseif t == "screenUI" or t == "screen" or t == "screen_clipboard"
        or t == "interactive" or t == "interactive_clipboard" then
        -- screencapture 参数拼接（showPostUI 追加 u）
        local map = {
            screen = "",           screen_clipboard = "-c",
            interactive = "-i",    screenUI = "-iU",
            interactive_clipboard = "-ci",
        }
        local args = map[t] or ""
        if runner.showPostUI then args = args .. "u" end
        local filename = hs.fs.pathToAbsolute("~")
            .. "/Desktop/Screen Capture at " .. os.date("!%Y-%m-%d-%T") .. ".png"
        taskUtil.run("/usr/sbin/screencapture", { args, filename })

    elseif t == "launch" then
        -- urlformats：按 scheme handler 打开
        local handler = row.handler or hs.urlevent.getDefaultHandler(row.scheme)
        if handler then hs.urlevent.openURLWithBundle(row.url, handler) end

    elseif t == "openURL" then
        taskUtil.run("/usr/bin/open", { row.url })

    elseif t == "runFunction" then
        if row.fn then
            row.fn(row.config or row.arg)
        end

    elseif t == "invokeKeyword" then
        if row.url then
            local q = (row.arg or "")
            q = hs.http.encodeForQuery(q):gsub("%%", "%%%%")
            taskUtil.run("/usr/bin/open", { row.url:gsub("${query}", q) })
        elseif row.fn then
            row.fn(row.arg)
        end

    elseif t == "addURL" then
        if runner.onAddURL then runner.onAddURL(row) end

    elseif t == "delURL" then
        if runner.onDelURL then runner.onDelURL(row) end

    elseif t == "custom" then
        local cmd = row.cmd
        if cmd and cmd.kind == "shell" and cmd.exec and cmd.exec[1] then
            local argv = {}
            for _, a in ipairs(cmd.exec[2] or {}) do
                -- tostring 对齐 cardShell 分支：非字符串 argv（数字等）不崩溃
                argv[#argv + 1] = tostring(a or ""):gsub("${query}", row.arg or "")
            end
            if runner.onCustom then
                runner.onCustom(cmd, argv, row.arg)
            else
                taskUtil.run(cmd.exec[1], argv)
            end
        end

    elseif t == "cardShell" then
        local exec = row.exec
        if exec and exec[1] then
            local argv = {}
            for _, a in ipairs(exec[2] or {}) do
                argv[#argv + 1] = tostring(a or ""):gsub("${query}", row.arg or "")
            end
            taskUtil.run(exec[1], argv)
        end

    elseif t == "cardPage" then
        -- 子页面卡片（kind="page"）：iframe 由前端打开，后端无动作

    elseif t == "cardOpenURL" then
        local url = (row.url or ""):gsub("${query}", row.arg or "")
        if url ~= "" then taskUtil.run("/usr/bin/open", { url }) end

    elseif t == "cardScreen" then
        local map = {
            fullscreen = "", clipboard = "-c",
            interactive = "-i", interactive_clipboard = "-ci", menu = "-iU",
        }
        local args = map[row.subKind] or "-i"
        if row.postUI then args = args .. "u" end
        local filename = hs.fs.pathToAbsolute("~")
            .. "/Desktop/Screen Capture at " .. os.date("!%Y-%m-%d-%T") .. ".png"
        taskUtil.run("/usr/sbin/screencapture", { args, filename })

    else
        logger.e("run: 未知 type=%s", t); return false
    end
    return true
end

-- 注入点（registry 提供）
runner.showPostUI = false
runner.onAddURL = nil
runner.onDelURL = nil
runner.onCustom = nil
runner.bumpAppLaunch = nil

return runner

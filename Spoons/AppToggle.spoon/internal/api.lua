--- AppToggle.internal.api
--- HTTP API：应用 CRUD / 状态 / 测试 / 布局管理 / 热键录制 guard + 静态 view。
local api = {}

local HSUtil = require("core.hsutil")
local app = HSUtil.http.app

local cfg, manager

-- ===== 热键录制 guard：录制期间 eventtap 吞掉 keyDown（系统快捷键不触发）=====
-- 对齐 QuantumWindow：前端 ui-hotkey remote 模式需要
--   POST <url> {action:'start'|'stop'} + GET <url>/poll → {result}
local guard = { tap = nil, result = nil, timer = nil }

-- 修饰键键码（左右 cmd/alt/ctrl/shift）
local MOD_CODES = {}
for _, code in ipairs({ 54, 55, 58, 61, 59, 62, 56, 60 }) do MOD_CODES[code] = true end

-- 键码 → hs.hotkey 主键名（left→Left、f5→F5、m→M）
local function keyNameForCode(code)
    local name = hs.keycodes.map[code]
    if not name then return nil end
    if name:match("^%l") then name = name:sub(1, 1):upper() .. name:sub(2) end
    return name
end

local function stopGuard()
    if guard.tap then guard.tap:stop() guard.tap = nil end
    if guard.timer then guard.timer:stop() guard.timer = nil end
end

local function startGuard()
    stopGuard()
    guard.result = nil
    guard.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
        local code = e:getKeyCode()
        -- Esc（53）：放行 + 停止录制（用户取消录制）
        if code == 53 then
            stopGuard()
            return false
        end
        -- Backspace/Delete 保持吞掉：放行会误删焦点所在其他应用的文本
        if not MOD_CODES[code] then
            local flags = e:getFlags()
            local mods = {}
            if flags.cmd then mods[#mods + 1] = "cmd" end
            if flags.alt then mods[#mods + 1] = "alt" end
            if flags.ctrl then mods[#mods + 1] = "ctrl" end
            if flags.shift then mods[#mods + 1] = "shift" end
            local key = keyNameForCode(code)
            if key and #mods > 0 then
                guard.result = table.concat(mods, "+") .. "+" .. key
                stopGuard()   -- 记录完成即停止吞键
            end
        end
        return true   -- 吞掉：系统快捷键（Spotlight 等）不触发
    end)
    guard.tap:start()
    guard.timer = hs.timer.doAfter(6, stopGuard)   -- 超时兜底
end

--- 注册路由
--- @param cfg_ table 配置单点
--- @param manager_ table manager 模块
--- @param viewsDir string 前端视图目录（views/ 根）
function api.setup(cfg_, manager_, viewsDir)
    cfg = cfg_
    manager = manager_

    -- 前端静态文件
    if viewsDir then
        app:static("/" .. cfg.pkg .. "/view", viewsDir)
    end

    -- 应用列表（含运行状态/布局）
    app:get("/" .. cfg.pkg .. "/api/apps", function(req, res)
        local apps = manager.list and manager.list() or nil
        if not apps then
            res:status(500):json({ err = "manager.list 未实现" })
            return
        end
        res:json({ apps = apps })
    end)

    -- 新增/更新应用（upsert by bundle_id）
    app:post("/" .. cfg.pkg .. "/api/apps", function(req, res)
        local body = req:json() or {}
        local ok, result, err = pcall(manager.upsert, body)
        if not ok or not result then
            return res:status(400):json({ err = err or tostring(result) })
        end
        res:json({ ok = true, id = result.id })
    end)

    -- 删除应用
    app:delete("/" .. cfg.pkg .. "/api/apps/:id", function(req, res)
        local id = tonumber(req.params.id)
        if not id then return res:status(400):json({ err = "缺 id" }) end
        pcall(manager.delete, id)
        res:json({ ok = true })
    end)

    -- 测试：触发该应用显隐（与热键同一逻辑）
    app:post("/" .. cfg.pkg .. "/api/apps/:id/press", function(req, res)
        local id = tonumber(req.params.id)
        local apps = manager.list and manager.list() or {}
        local target
        for _, a in ipairs(apps) do
            if a.id == id then target = a break end
        end
        if not target then return res:status(404):json({ err = "应用不存在" }) end
        manager.press(target.bundle_id)
        res:json({ ok = true })
    end)

    -- 应用状态（运行/隐藏/布局）
    app:get("/" .. cfg.pkg .. "/api/apps/:id/state", function(req, res)
        local id = tonumber(req.params.id)
        local apps = manager.list and manager.list() or {}
        local target
        for _, a in ipairs(apps) do
            if a.id == id then target = a break end
        end
        if not target then return res:status(404):json({ err = "应用不存在" }) end
        res:json(manager.state(target.bundle_id))
    end)

    -- 清除布局
    app:post("/" .. cfg.pkg .. "/api/apps/:id/clear-layouts", function(req, res)
        local id = tonumber(req.params.id)
        local apps = manager.list and manager.list() or {}
        local target
        for _, a in ipairs(apps) do
            if a.id == id then target = a break end
        end
        if not target then return res:status(404):json({ err = "应用不存在" }) end
        manager.clearLayouts(target.bundle_id)
        res:json({ ok = true })
    end)

    -- 热键录制 guard
    app:post("/" .. cfg.pkg .. "/api/hotkey-guard", function(req, res)
        local body = req:json() or {}
        if body.action == "start" then startGuard()
        elseif body.action == "stop" then stopGuard()
        else return res:status(400):json({ err = "bad action" }) end
        res:json({ ok = true })
    end)
    app:get("/" .. cfg.pkg .. "/api/hotkey-guard/poll", function(req, res)
        local r = guard.result
        guard.result = nil   -- 取走即清
        res:json({ result = r })
    end)
end

return api

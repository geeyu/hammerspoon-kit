--- QuantumWindow.internal.api
--- HTTP API：配置读取/保存（每动作 启用开关 + 热键，改动即保存）+ 热键录制 guard
--- （吞键屏蔽系统快捷键）+ 静态 view。
local api = {}

local HSUtil = require("core.hsutil")
local app = HSUtil.http.app

-- 定位 internal/ 目录（子模块用 dofile，spoon 内不可 require）
local function script_path()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local actionsMod = dofile(script_path() .. "actions.lua")

local cfg
local opts   -- { onSaveActions = function(actions) end }（init.lua 提供：清洗 + 持久化 + 重绑）

-- ===== 热键录制 guard：录制期间 eventtap 吞掉 keyDown（系统快捷键不触发）=====
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
--- @param cfg_ table 配置单点（QuantumWindow.internal.config）
--- @param viewsDir string 前端视图目录（views/ 根）
--- @param opts_ table|nil { onSaveActions = function(actions) end }
function api.setup(cfg_, viewsDir, opts_)
    cfg = cfg_
    opts = opts_

    -- 前端静态文件
    if viewsDir then
        app:static("/quantumwindow/view", viewsDir)
    end

    -- 配置读取（每动作 启用 + 热键，默认值合并）
    app:get("/quantumwindow/api/config", function(req, res)
        local overrides = opts and opts.getState and opts.getState().actions or nil
        res:json({ actions = actionsMod.flatten(cfg, overrides) })
    end)

    -- 保存（全量 actions：{key = {enabled, hotkey}}）→ 清洗 + 持久化 + 重绑
    app:post("/quantumwindow/api/config", function(req, res)
        local body = req:json() or {}
        local actions = body.actions
        if type(actions) ~= "table" then
            return res:status(400):json({ err = "缺 actions" })
        end
        if opts and opts.onSaveActions then
            local ok, err = pcall(opts.onSaveActions, actions)
            if not ok then
                return res:status(500):json({ err = tostring(err) })
            end
        end
        res:json({ ok = true })
    end)

    -- 热键录制 guard（吞键屏蔽系统快捷键；前端轮询取结果）
    app:post("/quantumwindow/api/hotkey-guard", function(req, res)
        local body = req:json() or {}
        if body.action == "start" then startGuard()
        elseif body.action == "stop" then stopGuard()
        else return res:status(400):json({ err = "bad action" }) end
        res:json({ ok = true })
    end)
    app:get("/quantumwindow/api/hotkey-guard/poll", function(req, res)
        local r = guard.result
        guard.result = nil   -- 取走即清
        res:json({ result = r })
    end)
end

return api

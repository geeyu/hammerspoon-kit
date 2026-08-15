--- AppToggle.internal.manager
--- 应用绑定管理：store 应用列表 → toggle 引擎绑定（增删改后全量重建）。
--- 冲突检测：同一组合键被多个启用应用使用 → 返回冲突信息。
local manager = {}

local HSUtil = require("core.hsutil")

local cfg, store, toggle

--- 注入依赖（init.lua 装配时调用）
--- @param cfg_ table 配置单点
--- @param store_ table store 模块
function manager.setup(cfg_, store_)
    cfg = cfg_
    store = store_
    local internal = (debug.getinfo(1, "S").source:match("(.*[/\\])") or "")
    toggle = dofile(internal .. "toggle.lua")
    toggle.setup({
        loadLayouts = function(bundleID)
            local raw = store.getSetting("layouts." .. bundleID)
            if type(raw) ~= "string" or raw == "" then return {} end
            local ok, t = pcall(HSUtil.json.decode, raw)
            if ok and type(t) == "table" then return t end
            return {}
        end,
        saveLayouts = function(bundleID, layouts)
            local ok, raw = pcall(HSUtil.json.encode, layouts or {})
            if ok then store.setSetting("layouts." .. bundleID, raw) end
        end,
    })
end

--- 全量重建绑定（start / 增删改后调用）
--- @return ok boolean
function manager.reloadAll()
    toggle.cleanup()
    local apps = store.listApps()
    local conflicts = {}
    for _, app in ipairs(apps) do
        if app.enabled then
            local _, err = toggle.bind(app)
            if err then
                conflicts[#conflicts + 1] = {
                    name = app.name,
                    bundle_id = app.bundle_id,
                    err = err,
                }
            end
        end
    end
    return #conflicts == 0, conflicts
end

--- 清空全部绑定（stop 时调用，不重新绑定）
function manager.clear()
    toggle.cleanup()
end

--- 组合键冲突检测：返回占用该组合的应用（启用中的）
--- @param mods table
--- @param key string
--- @param exceptBundleID string|nil 排除的应用（编辑自身时）
--- @return table|nil
function manager.findConflict(mods, key, exceptBundleID)
    if not key or key == "" then return nil end
    local apps = store.listApps()
    for _, app in ipairs(apps) do
        if app.enabled and app.key == key
            and app.bundle_id ~= exceptBundleID
            and #app.mods == #mods then
            -- mods 逐项比较（顺序无关）
            local same = true
            for _, m in ipairs(mods) do
                local found = false
                for _, om in ipairs(app.mods) do
                    if om == m then found = true break end
                end
                if not found then same = false break end
            end
            if same then return app end
        end
    end
    return nil
end

--- 校验一个应用配置（bundle_id/key/mods 合法性）
--- @param app table
--- @return table|nil, string|nil
function manager.sanitize(app)
    if type(app) ~= "table" then return nil, "缺应用配置" end
    local name = tostring(app.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, "名称不能为空" end
    local bundleID = tostring(app.bundle_id or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if bundleID == "" then return nil, "Bundle ID 不能为空" end
    local key = tostring(app.key or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil, "热键主键不能为空" end
    local mods = app.mods
    if type(mods) ~= "table" or #mods == 0 then
        return nil, "至少需要一个修饰键（Ctrl/Cmd/Alt/Shift）"
    end
    local whitelist = { ctrl = true, cmd = true, alt = true, shift = true }
    local modsOut = {}
    for _, m in ipairs(mods) do
        m = tostring(m)
        if not whitelist[m] then return nil, "非法修饰键: " .. m end
        local dup = false
        for _, om in ipairs(modsOut) do if om == m then dup = true break end end
        if not dup then modsOut[#modsOut + 1] = m end
    end
    if #modsOut == 0 then return nil, "至少需要一个修饰键" end
    -- 主键合法性（简单校验：非空且不含 '+')
    if key:find("+") then return nil, "主键不能包含 +" end

    local onNoWindow = tostring(app.on_no_window or "launch")
    if onNoWindow ~= "launch" and onNoWindow ~= "activate" then
        return nil, "on_no_window 需为 launch 或 activate"
    end

    return {
        name = name,
        bundle_id = bundleID,
        mods = modsOut,
        key = key,
        enabled = app.enabled ~= false,
        on_no_window = onNoWindow,
        fullscreen_fallback = app.fullscreen_fallback ~= false,
        restore_focus = app.restore_focus ~= false,
        move_to_mouse_screen = app.move_to_mouse_screen ~= false,
    }
end

--- 新增/更新 + 重绑
--- @param app table 原始输入（前端 POST body）
--- @return table|nil, string|nil
function manager.upsert(app)
    local clean, err = manager.sanitize(app)
    if not clean then return nil, err end
    -- 冲突检测（编辑自身时排除）
    local conflict = manager.findConflict(clean.mods, clean.key, clean.bundle_id)
    if conflict then
        return nil, string.format("热键 %s+%s 已被「%s」占用",
            table.concat(clean.mods, "+"), clean.key, conflict.name)
    end
    local id, perr = store.upsertApp(clean)
    if not id then return nil, perr or "写入失败" end
    manager.reloadAll()
    return { id = id, app = clean }
end

--- 删除 + 重绑
--- @param id number
function manager.delete(id)
    store.deleteApp(id)
    manager.reloadAll()
end

--- 应用列表（含运行状态/布局，管理页展示）
function manager.list()
    local apps = store.listApps()
    local out = {}
    for _, a in ipairs(apps) do
        local st = toggle.appState(a.bundle_id)
        out[#out + 1] = {
            id = a.id,
            name = a.name,
            bundle_id = a.bundle_id,
            mods = a.mods,
            key = a.key,
            enabled = a.enabled,
            on_no_window = a.on_no_window,
            fullscreen_fallback = a.fullscreen_fallback,
            restore_focus = a.restore_focus,
            move_to_mouse_screen = a.move_to_mouse_screen,
            running = st.running,
            hidden = st.hidden,
            layout_count = 0,
        }
        for _ in pairs(st.layouts or {}) do out[#out].layout_count = out[#out].layout_count + 1 end
    end
    return out
end

--- 测试：触发该应用的显隐逻辑（与热键相同）
function manager.press(bundleID)
    toggle.pressByBundle(bundleID)
end

--- 状态（管理页展示：运行/隐藏/布局）
function manager.state(bundleID)
    return toggle.appState(bundleID)
end

--- 清除某应用全部锁定布局
function manager.clearLayouts(bundleID)
    toggle.clearLayouts(bundleID)
end

--- 当前绑定数量（管理页展示）
function manager.boundCount()
    local n = 0
    for _ in pairs(toggle._registry) do n = n + 1 end
    return n
end

return manager

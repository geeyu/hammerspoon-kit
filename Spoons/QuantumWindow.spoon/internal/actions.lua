--- QuantumWindow.internal.actions
--- 动作配置纯逻辑：默认值合并 / 覆盖清洗 / 绑定映射构造 / settings.json 读写。
--- 不依赖 hs.*（hs.json 除外），可在测试中直接验证。
local actions = {}

--- 构造绑定映射：禁用的动作不绑；显式空热键不绑；覆盖热键优先，否则默认热键
--- @param config table 配置单点（QuantumWindow.internal.config）
--- @param overrides table|nil {key = {enabled=bool, hotkey=string}}
--- @return table {key = {mods, key}}，可传给 bindHotkeys
function actions.buildMapping(config, overrides)
    local mapping = {}
    for _, a in ipairs(config.action_order or {}) do
        local ov = overrides and overrides[a.key]
        if not (ov and ov.enabled == false) then
            if ov and type(ov.hotkey) == "string" then
                -- 有显式记录：非空才解析绑定，空串 = 用户清空 → 不绑
                if ov.hotkey ~= "" then
                    local hk = config.parseHotkeyString(ov.hotkey)
                    if hk then mapping[a.key] = hk end
                end
            else
                -- 无覆盖（初始默认）→ 用默认热键
                local hk = config.defaultHotkeyFor(a.key)
                if hk then mapping[a.key] = hk end
            end
        end
    end
    return mapping
end

--- 清洗前端提交的覆盖：只保留已知动作，字段规范化（enabled bool / hotkey string）
--- @param raw table|nil 前端 POST 的 {key = {enabled, hotkey}}
--- @return table 清洗后的覆盖表（始终可安全持久化）
function actions.sanitize(config, raw)
    local clean = {}
    if type(raw) ~= "table" then return clean end
    for _, a in ipairs(config.action_order or {}) do
        local ov = raw[a.key]
        if type(ov) == "table" then
            clean[a.key] = {
                enabled = (ov.enabled ~= false),   -- 注意：不能用 and/or 三元，false 分支会被吞
                hotkey  = (type(ov.hotkey) == "string") and ov.hotkey or "",
            }
        end
    end
    return clean
end

--- 配置页动作行（默认值 + 覆盖合并；hotkey 统一为字符串）
--- @param overrides table|nil
--- @return table [{key, group, label, desc, enabled, hotkey}]（按 action_order 顺序）
function actions.flatten(config, overrides)
    local out = {}
    for _, a in ipairs(config.action_order or {}) do
        local ov = overrides and overrides[a.key]
        local enabled = not (ov and ov.enabled == false)
        local hotkey = ""
        if ov and type(ov.hotkey) == "string" then
            -- 有显式记录：空串原样显示（用户清空）；非空解析（非法串同样显示空，与不绑一致）
            if ov.hotkey ~= "" then
                local hk = config.parseHotkeyString(ov.hotkey)
                hotkey = hk and config.hotkeyToString(hk) or ""
            end
        else
            -- 无覆盖（初始默认）→ 默认热键
            local hk = config.defaultHotkeyFor(a.key)
            hotkey = hk and config.hotkeyToString(hk) or ""
        end
        out[#out + 1] = {
            key = a.key, group = a.group, label = a.label, desc = a.desc,
            enabled = enabled,
            hotkey = hotkey,
        }
    end
    return out
end

--- 读 settings.json（无文件/损坏/非 actions 结构 → 空覆盖 {}）
--- @param file string 绝对路径
--- @return table {key = {enabled, hotkey}}
function actions.load(file)
    local f = io.open(file, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(hs.json.decode, content)
    if ok and type(data) == "table" and type(data.actions) == "table" then
        return data.actions
    end
    return {}
end

--- 写 settings.json（{actions = overrides}），目录不存在自动创建
--- @return boolean 是否成功
function actions.save(file, overrides)
    local dir = file:match("^(.*)/[^/]+$")
    if dir then os.execute('mkdir -p "' .. dir .. '"') end
    local ok, content = pcall(hs.json.encode, { actions = overrides })
    if not ok then return false end
    local f = io.open(file, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

return actions

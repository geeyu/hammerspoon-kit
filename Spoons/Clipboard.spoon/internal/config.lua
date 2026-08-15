--- Clipboard.internal.config
--- 配置单点。所有可调项集中，供 init/watcher/panel/api 使用。
--- 可编辑项（settings 页可改）持久化到 data_dir/settings.json，reload 后仍生效。
local HSUtil = require("core.hsutil")

local defaults = {
    -- 包名（HTTP 路由前缀：/<pkg>/api/*、/<pkg>/view/*；改包名只需改这里）
    pkg = "clipboard",
    -- 呼出快捷键（{mods 数组, key}，hs.hotkey.new(mods, key) 直用）
    -- 注意：避免 Ctrl+单字母（macOS Cocoa 内置 Emacs 键绑定会拦截）
    hotkey_show = { { "ctrl" }, "v" },
    -- 历史容量
    max_entries = 300,
    -- 定期清理：保留近多少天（7 天前自动删）
    retain_days = 7,
    -- 是否也记录图片（false=记录；true=仅文本）
    text_only = false,
    -- 是否启用面板内搜索
    enable_search = true,
    -- 面板可视行数
    visible_rows = 8,
    -- 面板尺寸（屏幕比例；设置页可改）：
    --   widthRatio/heightRatio 按「目标屏幕」（默认鼠标所在屏）计算
    --   yRatio 垂直位置：0=贴顶，0.5=居中
    panel = {
        widthRatio  = 0.52,
        heightRatio = 0.62,
        yRatio      = 0.22,
    },
    -- 数据库文件名
    db_file = "history.db",
}

-- 数据目录（走 HSUtil 数据目录：~/.hammerspoon/data/clipboard）
local data_dir = HSUtil.path.dataDir() .. "/" .. defaults.pkg
local settings_file = data_dir .. "/settings.json"

-- 可编辑白名单（settings 页暴露的项）
local editable_keys = { "hotkey_show", "max_entries", "retain_days", "text_only", "panel" }

local config = {}

-- =====================================================================
-- 校验（loadOverrides 与 update 共用同一套 sanitize）
-- =====================================================================

local MOD_WHITELIST = { ctrl = true, alt = true, cmd = true, shift = true }

--- 校验并归一化热键 {mods, key}
local function sanitizeHotkey(v)
    if type(v) ~= "table" or type(v[2]) ~= "string" or v[2] == "" then
        return nil, "hotkey_show 需为 {mods, key}"
    end
    if type(v[1]) ~= "table" or #v[1] == 0 then
        return nil, "hotkey_show 至少一个修饰键"
    end
    local mods = {}
    for _, m in ipairs(v[1]) do
        if not MOD_WHITELIST[m] then return nil, "不支持的修饰键: " .. tostring(m) end
        mods[#mods + 1] = m
    end
    return { mods, v[2] }
end

--- 校验并归一化正整数
local function sanitizeInt(v, name, min, max)
    local n = tonumber(v)
    if not n or n % 1 ~= 0 or n < min or n > max then
        return nil, name .. " 需为 " .. min .. "~" .. max .. " 的整数"
    end
    return n
end

--- 校验并归一化面板尺寸 {widthRatio, heightRatio, yRatio}
local function sanitizePanel(v)
    if type(v) ~= "table" then return nil, "panel 需为 table" end
    local function ratio(x, name, minv, maxv)
        local n = tonumber(x)
        if not n or n < minv or n > maxv then
            return nil, name .. " 需为 " .. minv .. "~" .. maxv .. " 的数值"
        end
        return n
    end
    local w, e1 = ratio(v.widthRatio, "widthRatio", 0.3, 0.95)
    if not w then return nil, e1 end
    local h, e2 = ratio(v.heightRatio, "heightRatio", 0.3, 0.95)
    if not h then return nil, e2 end
    local y, e3 = ratio(v.yRatio, "yRatio", 0, 0.95)
    if not y then return nil, e3 end
    return { widthRatio = w, heightRatio = h, yRatio = y }
end

--- 校验并归一化一个可编辑项；非法返回 nil + err
local function sanitize(key, v)
    if key == "hotkey_show" then return sanitizeHotkey(v) end
    if key == "max_entries" then return sanitizeInt(v, "max_entries", 50, 5000) end
    if key == "retain_days" then return sanitizeInt(v, "retain_days", 1, 365) end
    if key == "text_only" then return v and true or false end
    if key == "panel" then return sanitizePanel(v) end
    return nil, "未知配置项: " .. tostring(key)
end

-- =====================================================================
-- 加载/合并
-- =====================================================================

for k, v in pairs(defaults) do config[k] = v end
config.data_dir = data_dir

--- 从 settings.json 合并覆盖（不存在则跳过）
--- 注意：与 update 一样过 sanitize——手改坏 settings.json（如 hotkey_show 结构非法）
--- 会导致 rebindHotkey 里 hs.hotkey.new 抛错、启动崩溃；非法项丢弃回退默认
--- @param file string|nil 覆盖文件路径（测试用）
function config.loadOverrides(file)
    file = file or settings_file
    local f = io.open(file, "rb")
    local raw = f and HSUtil.json.tryDecode(f:read("*a"), nil) or nil
    if f then f:close() end
    if type(raw) ~= "table" then return end
    for _, k in ipairs(editable_keys) do
        local val, err = sanitize(k, raw[k])
        if val ~= nil then config[k] = val end
    end
end
config.loadOverrides()

-- =====================================================================
-- 对外 API
-- =====================================================================

--- 可编辑项（settings 页 GET /api/settings 返回）
function config.editable()
    return {
        hotkey_show = config.hotkey_show,
        max_entries = config.max_entries,
        retain_days = config.retain_days,
        text_only = config.text_only,
        panel = config.panel,
    }
end

--- 应用配置补丁：校验 → 合并 → 持久化
--- @param patch table 部分字段即可
--- @return newSettings table, err
function config.update(patch)
    if type(patch) ~= "table" then return nil, "patch 需为 table" end
    for k, v in pairs(patch) do
        -- 注意：text_only=false 是合法值，必须用 == nil 判断失败（不能 not ok）
        local val, err = sanitize(k, v)
        if val == nil then return nil, err end
        config[k] = val
    end
    -- 持久化（原子写：先写临时文件再 rename）
    local body = HSUtil.json.encode(config.editable(), true)
    HSUtil.path.ensureDir(data_dir)
    local tmp = settings_file .. ".tmp"
    local f = io.open(tmp, "wb")
    if f then
        f:write(body)
        f:close()
        os.rename(tmp, settings_file)
    end
    return config.editable()
end

return config

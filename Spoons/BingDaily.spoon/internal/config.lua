--- BingDaily.internal.config
--- 配置单点：默认值 + SQLite 覆盖（持久化在 store.lua，本模块只做默认值与校验合并）。
local HSUtil = require("core.hsutil")

local defaults = {
    -- 包名（HTTP 路由前缀：/bingdaily/api/*、/bingdaily/view/*）
    pkg = "bingdaily",
    -- 轮询间隔（小时）：每 N 小时检查一次今日壁纸
    interval_hours = 3,
    -- 保存目录（壁纸下载位置，支持 ~ 缩写；自动创建）
    save_dir = "~/Pictures/BingDaily",
    -- 自动应用：下载后自动设为桌面壁纸
    auto_apply = true,
    -- 归档天数：搜索页展示最近 N 天壁纸
    archive_days = 7,
    -- 应用壁纸后系统通知
    notify_enabled = true,
    -- 应用范围：main=仅主屏 / all=全部屏幕
    apply_to_screens = "main",
}

local config = {}
for k, v in pairs(defaults) do config[k] = v end
-- 数据目录（SQLite 库位置：~/.hammerspoon/data/bingdaily/bingdaily.db）
config.data_dir = HSUtil.path.dataDir() .. "/" .. defaults.pkg

-- =====================================================================
-- 校验 + 合并（持久化由 store.lua 负责，本模块不做 IO）
-- =====================================================================

--- 应用存储的设置（start 时从 SQLite 读回，校验后覆盖默认值）
--- @param t table|nil { interval_hours=?, save_dir=?, auto_apply=?, archive_days=?,
---   notify_enabled=?, apply_to_screens=? }
function config.applyFromStore(t)
    if type(t) ~= "table" then return end
    if tonumber(t.interval_hours) then
        config.interval_hours = math.max(1, math.min(24, math.floor(tonumber(t.interval_hours))))
    end
    if type(t.save_dir) == "string" and t.save_dir ~= "" then
        config.save_dir = t.save_dir
    end
    if t.auto_apply ~= nil then
        config.auto_apply = t.auto_apply == true
    end
    if tonumber(t.archive_days) then
        config.archive_days = math.max(1, math.min(30, math.floor(tonumber(t.archive_days))))
    end
    if t.notify_enabled ~= nil then
        config.notify_enabled = t.notify_enabled == true
    end
    if t.apply_to_screens == "all" then
        config.apply_to_screens = "all"
    else
        config.apply_to_screens = "main"
    end
end

--- settings 页可编辑项
function config.editable()
    return {
        interval_hours = config.interval_hours,
        save_dir = config.save_dir,
        auto_apply = config.auto_apply,
        archive_days = config.archive_days,
        notify_enabled = config.notify_enabled,
        apply_to_screens = config.apply_to_screens,
    }
end

--- 校验补丁并应用到内存；返回实际变更的子集（供持久化）。
--- 非法返回 nil + 原因。
--- @param patch table { interval_hours=?, save_dir=?, auto_apply=?, archive_days=?,
---   notify_enabled=?, apply_to_screens=? }
--- @return table|nil, string|nil
function config.applyPatch(patch)
    if type(patch) ~= "table" then return nil, "patch 需为 table" end
    local out = {}
    if patch.interval_hours ~= nil then
        local n = tonumber(patch.interval_hours)
        if not n then return nil, "间隔需为数字" end
        config.interval_hours = math.max(1, math.min(24, math.floor(n)))
        out.interval_hours = config.interval_hours
    end
    if patch.save_dir ~= nil then
        local v = tostring(patch.save_dir):gsub("^%s+", ""):gsub("%s+$", "")
        if v == "" or v:find("\n") then return nil, "目录不能为空" end
        config.save_dir = v
        out.save_dir = v
    end
    if patch.auto_apply ~= nil then
        config.auto_apply = patch.auto_apply == true
        out.auto_apply = config.auto_apply
    end
    if patch.archive_days ~= nil then
        local n = tonumber(patch.archive_days)
        if not n then return nil, "天数需为数字" end
        config.archive_days = math.max(1, math.min(30, math.floor(n)))
        out.archive_days = config.archive_days
    end
    if patch.notify_enabled ~= nil then
        config.notify_enabled = patch.notify_enabled == true
        out.notify_enabled = config.notify_enabled
    end
    if patch.apply_to_screens ~= nil then
        if patch.apply_to_screens ~= "main" and patch.apply_to_screens ~= "all" then
            return nil, "应用范围需为 main 或 all"
        end
        config.apply_to_screens = patch.apply_to_screens
        out.apply_to_screens = config.apply_to_screens
    end
    return out
end

--- 展开 ~ 后的实际保存目录（状态展示用）
function config.expandedSaveDir()
    local p = tostring(config.save_dir or "")
    if p:sub(1, 1) == "~" then
        local home = os.getenv("HOME") or ""
        return home .. p:sub(2)
    end
    return p
end

return config

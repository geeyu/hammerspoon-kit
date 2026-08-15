--- === BingDaily ===
---
--- Bing 每日壁纸（分层架构，对齐 Clipboard）：
---   internal/config.lua  配置单点（SQLite 持久化）
---   internal/store.lua   数据访问层（settings + 下载历史）
---   internal/bing.lua    核心逻辑（Bing 信息拉取 / 下载 / 应用壁纸 / 通知）
---   internal/api.lua     HTTP API（状态 / 设置 / 归档搜索 / 一键执行）
---
--- 能力：
---   * 每 N 小时自动轮询今日壁纸（下载后可选自动应用）
---   * 一键执行：立即刷新 / 立即应用今日 / 随机应用归档 / 打开保存目录
---   * 归档搜索页浏览最近 N 天壁纸，点击直接切换
---   * 默认图片保存位置可配置（支持 ~ 缩写，自动创建）
---   * 应用壁纸后系统通知（可开关）；应用范围主屏/全部屏幕可选
---   * 下载历史记录（SQLite）
--- ============================================================

local obj = {}

obj.name = "BingDaily"
obj.version = "3.0.0"
obj.author = "geeyu"
obj.homepage = "https://github.com/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- 定位本 spoon 目录
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local spoonPath = script_path()
local loadMod = function(n) return dofile(spoonPath .. "internal/" .. n) end

-- 加载各层
local config = loadMod("config.lua")
local store  = loadMod("store.lua")
local bing   = loadMod("bing.lua")
local api    = loadMod("api.lua")

obj.config = config
obj.logger = hs.logger.new("BingDaily", "info")

local timer = nil

--- 重排轮询定时器（配置间隔变更后调用）
local function rescheduleTimer()
    if timer then
        timer:stop()
        timer = nil
    end
    timer = hs.timer.doEvery(config.interval_hours * 60 * 60, function()
        bing.fetchToday(config.auto_apply)
    end)
    timer:setNextTrigger(5)   -- 启动后 5 秒首次拉取
end

--- BingDaily:start()
--- Method
--- 挂 API + 启动轮询。幂等。
function obj:start()
    if self._started then return self end
    -- SQLite 配置库：打开 + 读回设置覆盖默认值（旧 settings.json 自动迁移）
    pcall(store.open, config.data_dir)
    config.applyFromStore(store.loadSettings())
    bing.setup(config, store)
    api.setup(config, bing, store, spoonPath .. "views")
    api.onIntervalChanged(function()
        rescheduleTimer()
    end)
    rescheduleTimer()
    self._started = true
    obj.logger.f("BingDaily 已启动（间隔 %d 小时，保存到 %s）", config.interval_hours, config.save_dir)
    return self
end

--- BingDaily:stop()
--- Method
--- 停止轮询并关闭数据库。
function obj:stop()
    if timer then timer:stop(); timer = nil end
    pcall(store.close)
    self._started = false
    return self
end

--- BingDaily:getStatus()
--- Method：当前状态（供配置页/调试）
function obj:getStatus()
    return bing.getStatus()
end

--- BingDaily:refreshNow()
--- Method：立即拉取今日壁纸（是否应用按 auto_apply 配置）
function obj:refreshNow()
    bing.fetchToday(config.auto_apply)
    return self
end

--- BingDaily:applyToday()
--- Method：一键应用今日壁纸（下载 + 设壁纸 + 通知，无视 auto_apply）
--- @param cb function|nil function(localPath|nil, err|nil)
function obj:applyToday(cb)
    bing.applyToday(cb or function() end)
    return self
end

--- BingDaily:applyRandom()
--- Method：一键随机应用归档中的一张壁纸
--- @param cb function|nil function(localPath|nil, err|nil)
function obj:applyRandom(cb)
    bing.applyRandom(cb or function() end)
    return self
end

--- BingDaily:openSaveDir()
--- Method：打开保存目录（Finder）
--- @return string 展开后的目录
function obj:openSaveDir()
    return bing.openSaveDir()
end

--- BingDaily:recentDownloads()
--- Method：最近下载历史
--- @return table
function obj:recentDownloads()
    return bing.recentDownloads()
end

return obj

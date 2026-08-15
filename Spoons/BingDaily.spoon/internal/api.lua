--- BingDaily.internal.api
--- HTTP API：状态 / 配置（SQLite 持久化）/ 归档搜索 / 一键执行（今日·随机·打开目录）/
--- 下载历史 + 静态 view。
local api = {}

local HSUtil = require("core.hsutil")
local app = HSUtil.http.app

local cfg
local bing
local store

--- 间隔变更回调（init 注入：重排轮询定时器）
local onIntervalChanged = function() end
api.onIntervalChanged = function(fn) onIntervalChanged = fn end

--- 注册路由
--- @param cfg_ table 配置单点（editable/applyPatch）
--- @param bing_ table bing 模块
--- @param store_ table store 模块（SQLite 持久化）
--- @param viewsDir string 前端视图目录（views/ 根）
function api.setup(cfg_, bing_, store_, viewsDir)
    cfg = cfg_
    bing = bing_
    store = store_

    -- 前端静态文件
    if viewsDir then
        app:static("/" .. cfg.pkg .. "/view", viewsDir)
    end

    -- 状态（配置页状态卡）
    app:get("/" .. cfg.pkg .. "/api/status", function(req, res)
        res:json(bing.getStatus())
    end)

    -- 今日壁纸立即轮询（下载；是否应用按 auto_apply）
    app:post("/" .. cfg.pkg .. "/api/refresh", function(req, res)
        bing.fetchToday(cfg.auto_apply)
        res:json({ ok = true })
    end)

    -- 一键应用今日壁纸（下载 + 设壁纸 + 通知；已下载过则直接用本地文件）
    app:post("/" .. cfg.pkg .. "/api/apply-today", function(req, res)
        bing.applyToday(function(localPath, err)
            if not localPath then
                return res:status(500):json({ err = err or "应用失败" })
            end
            res:json({ ok = true, path = localPath })
        end)
    end)

    -- 一键随机应用归档壁纸
    app:post("/" .. cfg.pkg .. "/api/random", function(req, res)
        bing.applyRandom(function(localPath, err)
            if not localPath then
                return res:status(500):json({ err = err or "随机应用失败" })
            end
            res:json({ ok = true, path = localPath })
        end)
    end)

    -- 打开保存目录（Finder）
    app:post("/" .. cfg.pkg .. "/api/open-dir", function(req, res)
        local dir = bing.openSaveDir()
        res:json({ ok = true, dir = dir })
    end)

    -- 下载历史（最近 N 条）
    app:get("/" .. cfg.pkg .. "/api/downloads", function(req, res)
        res:json({ rows = bing.recentDownloads(8) })
    end)

    -- 归档列表（搜索页）：最近 N 天壁纸
    app:get("/" .. cfg.pkg .. "/api/archive", function(req, res)
        bing.fetchArchive(function(rows, err)
            if not rows then return res:status(500):json({ err = err or "拉取失败" }) end
            res:json({ rows = rows, save_dir = cfg.save_dir })
        end)
    end)

    -- 应用归档中的一张壁纸（下载 + 设壁纸）
    -- 注意：HSUtil dispatch 为同步分发，下载是异步的——立即返回 ok，下载在后台完成；
    -- 失败会反映在 /status 的 status=error（前端可轮询）。
    app:post("/" .. cfg.pkg .. "/api/apply", function(req, res)
        local body = req:json() or {}
        local name = body.name
        local url = body.url
        local date = body.date or ""
        local copyright = body.copyright or ""
        if not name or not url then
            return res:status(400):json({ err = "缺 name/url" })
        end
        bing.applyArchive({ name = name, url = url, date = date, copyright = copyright }, function() end)
        res:json({ ok = true, applying = name })
    end)

    -- ===== 设置（SQLite 持久化，对齐 FileSearch）=====
    if cfg and cfg.editable then
        app:get("/" .. cfg.pkg .. "/api/settings", function(req, res)
            res:json(cfg.editable())
        end)
        app:post("/" .. cfg.pkg .. "/api/settings", function(req, res)
            local patch = req:json() or {}
            local ok, result, err = pcall(cfg.applyPatch, patch)
            if not ok or result == nil then
                return res:status(400):json({ err = err or "配置无效" })
            end
            -- 写 SQLite
            if store and store.saveSettings then
                pcall(store.saveSettings, result)
            end
            -- 间隔变更：重排定时器（由 init 注入的回调处理）
            if onIntervalChanged then pcall(onIntervalChanged, result.interval_hours) end
            res:json({ ok = true, settings = cfg.editable() })
        end)
    end
end

return api

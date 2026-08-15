--- BingDaily.internal.bing
--- 核心逻辑：Bing 图片信息拉取（今日/归档）+ 下载 + 应用壁纸 + 下载历史记录。
local bing = {}

local HSUtil = require("core.hsutil")
local cfg
local store

--- 注入配置与存储
function bing.setup(config, store_)
    cfg = config
    store = store_
end

local USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_5) AppleWebKit/603.2.4 (KHTML, like Gecko) Version/10.1.1 Safari/603.2.4"
local INFO_API = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=%d&n=%d"

-- 状态
local last_pic = ""        -- 当前壁纸文件名
local updated_at = nil     -- 最近成功时间
local status = "idle"      -- idle/fetching/ok/error
local downloadTask = nil
local archiveCache = nil   -- { at=os.time(), rows={...} }

--- 从 Bing 图片 URL 提取真实文件名
--- 例：/th?id=OHR.HelsinkiBlue_JA-JP6468131752_1920x1080.jpg&rf=...&pid=hp
---   → OHR.HelsinkiBlue_JA-JP6468131752_1920x1080.jpg
local function extractPicName(url)
    -- urlParts 对空串/特殊 URL 可能抛 "string did not match the expected pattern"，
    -- pcall 保护：失败时退回 lastPathComponent 或空串
    if not url or url == "" then return "" end
    local ok, parts = pcall(hs.http.urlParts, url)
    if not ok or type(parts) ~= "table" then
        -- 兜底：从 url 尾部截取文件名
        local last = url:match("([^/]+)$") or ""
        local id = last:match("id=([^&]+)")
        return id or last
    end
    if parts.query then
        local id = parts.query:match("id=([^&]+)")
        if id then return id end
    end
    return parts.lastPathComponent or ""
end

--- 展开 ~ 前缀
local function expandHome(p)
    p = tostring(p or "")
    if p:sub(1, 1) == "~" then
        local home = os.getenv("HOME") or ""
        return home .. p:sub(2)
    end
    return p
end

--- 请求 Bing 图片信息（idx=0 为今日，最多 n 张）
--- @param n number 张数
--- @param cb function(rows|nil, err|nil) rows: {date,name,url,copyright,title}
function bing.fetchInfo(n, cb)
    n = math.min(n or 1, 30)
    local url = string.format(INFO_API, 0, n)
    hs.http.asyncGet(url, { ["User-Agent"] = USER_AGENT }, function(stat, body)
        if stat ~= 200 then
            return cb(nil, "Bing 请求失败 HTTP " .. tostring(stat))
        end
        local ok, data = pcall(hs.json.decode, body)
        if not ok or not data or not data.images then
            return cb(nil, "Bing 响应解析失败")
        end
        local rows = {}
        for _, img in ipairs(data.images) do
            rows[#rows + 1] = {
                date = img.startdate or "",
                name = extractPicName(img.url or ""),
                url = "https://www.bing.com" .. (img.url or ""),
                copyright = img.copyright or "",
                title = img.title or "",
            }
        end
        cb(rows)
    end)
end

--- 归档列表（搜索页用）：缓存 10 分钟
--- @param cb function(rows|nil, err|nil)
function bing.fetchArchive(cb)
    local n = cfg.archive_days or 7
    if archiveCache and archiveCache.at and (os.time() - archiveCache.at) < 600 then
        return cb(archiveCache.rows)
    end
    bing.fetchInfo(n, function(rows, err)
        if rows then
            archiveCache = { at = os.time(), rows = rows }
        end
        cb(rows, err)
    end)
end

--- 设为桌面壁纸（按 cfg.apply_to_screens：主屏或全部屏幕）
function bing.applyWallpaper(localPath)
    local ok = false
    local function applyTo(screen)
        pcall(function()
            screen:desktopImageURL("file://" .. localPath)
        end)
    end
    if cfg.apply_to_screens == "all" then
        for _, s in ipairs(hs.screen.allScreens()) do
            applyTo(s)
            ok = true
        end
    else
        applyTo(hs.screen.mainScreen())
        ok = true
    end
    return ok
end

--- 应用成功后的系统通知（cfg.notify_enabled 开关）
local function notifyApplied(name, copyright)
    if not (cfg and cfg.notify_enabled) then return end
    local msg = name
    if copyright and copyright ~= "" then msg = msg .. "\n" .. copyright end
    hs.notify.new({
        title = "Bing 壁纸已更新",
        informativeText = msg,
    }):send()
end

--- 下载图片到保存目录并（可选）设为壁纸；记录下载历史
--- @param pic table {name=, url=, date=, copyright=}
--- @param apply boolean 是否设为壁纸
--- @param cb function(localPath|nil, err|nil)
function bing.download(pic, apply, cb)
    local name = pic.name
    local url = pic.url
    local dir = expandHome(cfg.save_dir)
    HSUtil.path.ensureDir(dir)
    local localPath = dir .. "/" .. name
    if downloadTask then
        pcall(function() downloadTask:terminate() end)
        downloadTask = nil
    end
    downloadTask = hs.task.new("/usr/bin/curl", function(exitCode)
        downloadTask = nil
        if exitCode ~= 0 then
            return cb(nil, "下载失败 exit=" .. tostring(exitCode))
        end
        last_pic = name
        updated_at = os.time()
        status = "ok"
        -- 记录下载历史（重复下载不重复记）
        if not store.findDownload(name) then
            store.addDownload({ name = name, url = url, date = pic.date, copyright = pic.copyright })
        end
        if apply then
            bing.applyWallpaper(localPath)
            store.markApplied(name)
            notifyApplied(name, pic.copyright)
        end
        cb(localPath)
    end, { "-A", USER_AGENT, url, "-o", localPath })
    downloadTask:start()
end

--- 应用归档中的一张（下载 + 设壁纸 + 通知）
--- @param pic table {name=, url=, date=, copyright=}
--- @param cb function(localPath|nil, err|nil)
function bing.applyArchive(pic, cb)
    status = "fetching"
    bing.download(pic, true, cb)
end

--- 今日壁纸自动轮询
--- @param autoApply boolean 是否自动应用
function bing.fetchToday(autoApply)
    status = "fetching"
    bing.fetchInfo(1, function(rows, err)
        if not rows or not rows[1] then
            status = "error"
            return
        end
        local pic = rows[1]
        -- 与当前壁纸相同则跳过（避免重复下载）
        if pic.name == last_pic then
            status = "ok"
            return
        end
        bing.download(pic, autoApply ~= false, function(localPath, derr)
            if not localPath then
                status = "error"
                return
            end
            -- 成功后清缓存（列表里的"已下载"标记可刷新）
            archiveCache = nil
        end)
    end)
end

--- 一键：立即拉取并应用今日壁纸（无论 auto_apply 配置）
--- @param cb function(ok|nil, err|nil)
function bing.applyToday(cb)
    status = "fetching"
    bing.fetchInfo(1, function(rows, err)
        if not rows or not rows[1] then
            status = "error"
            return cb(nil, err or "拉取失败")
        end
        local pic = rows[1]
        -- 已是最新且已下载过 → 直接应用本地文件（无需重新下载）
        local existed = store.findDownload(pic.name)
        if existed then
            local dir = expandHome(cfg.save_dir)
            local localPath = dir .. "/" .. pic.name
            local ok, mode = pcall(hs.fs.attributes, localPath, "mode")
            if ok and mode then
                bing.applyWallpaper(localPath)
                store.markApplied(pic.name)
                notifyApplied(pic.name, pic.copyright)
                last_pic = pic.name
                status = "ok"
                return cb(localPath)
            end
        end
        bing.download(pic, true, cb)
    end)
end

--- 一键：随机应用归档中的一张（下载 + 设壁纸）
--- @param cb function(localPath|nil, err|nil)
function bing.applyRandom(cb)
    bing.fetchArchive(function(rows, err)
        if not rows or #rows == 0 then
            return cb(nil, err or "无归档壁纸")
        end
        -- 随机一张；若随机到当前壁纸且候选多，换一张
        local idx = math.random(#rows)
        local pic = rows[idx]
        if pic.name == last_pic and #rows > 1 then
            pic = rows[(idx % #rows) + 1]
        end
        bing.applyArchive(pic, cb)
    end)
end

--- 打开保存目录（Finder）
--- @return string|nil 展开后的目录
function bing.openSaveDir()
    local dir = expandHome(cfg.save_dir)
    HSUtil.path.ensureDir(dir)
    pcall(function()
        hs.openURL("file://" .. dir)
    end)
    return dir
end

--- 最近下载历史（设置页展示）
function bing.recentDownloads(limit)
    return store.listDownloads(limit or 8)
end

--- 状态（配置页展示）
function bing.getStatus()
    local dir = expandHome(cfg.save_dir)
    local exists = false
    if last_pic ~= "" then
        local ok, mode = pcall(hs.fs.attributes, dir .. "/" .. last_pic, "mode")
        exists = ok and mode ~= nil
    end
    return {
        last_pic = last_pic,
        exists = exists,
        updated_at = updated_at,
        status = status,
        interval_hours = cfg.interval_hours,
        save_dir = cfg.save_dir,
        expanded_dir = dir,
        apply_to_screens = cfg.apply_to_screens,
    }
end

return bing

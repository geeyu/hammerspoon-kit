--- Clipboard.internal.watcher
--- 唯一业务入口：剪贴板监听 + 内存缓存 + 持久化协调。
--- 对外统一 API（panel/init 用）：all/search/get/remove/promote
--- 内部持有 store（持久层，不对外暴露）。
local watcher = {}

local dir = (function()
    local s = debug.getinfo(1, "S").source:sub(2)
    return s:match("(.*[/\\])") or ""
end)()
local store = dofile(dir .. "store.lua")

-- 内存缓存（最新在前）
local entries = {}
local cfg
local pbWatcher = nil
local purgeTimer = nil

local logger = hs.logger.new("Clipboard.watcher", "info")

-- 抑制捕获：自身写回剪贴板时避免误当作新复制再次入库（带超时复位防卡死）
local suppressCapture = false
local suppressTimer = nil

-- 外部订阅"历史变化"
watcher.onChange = nil
local function fireChange()
    if watcher.onChange then watcher.onChange() end
end

--- 初始化
function watcher.setup(config)
    cfg = config
    purgeTimer = nil
end

--- 启动：开库 + 清理 + 加载 + 监听
function watcher.start()
    store.open(cfg.data_dir, cfg.db_file)
    -- 启动清理过期数据
    local retain = (cfg and cfg.retain_days) or 7
    local purged = store.purgeOlderThan(retain)
    if purged and purged > 0 then
        logger.f("已清理 %d 条过期记录(>%d天)", purged, retain)
    end
    -- 从 DB 加载内存
    watcher.reload()
    -- 容量兑底：与 max_entries 对齐（正常时 _push 内存裁剪已同步删 DB，
    -- 此处防历史遗留/配置调小后首次启动的存量超标）
    store.trim(cfg.max_entries or 300)
    -- trim 删库后内存缓存 entries 仍含已删行（僵尸条目：面板显示、confirm/star 404），
    -- 必须重载。原实现 reload 在 trim 之前，顺序颠倒
    watcher.reload()
    -- 每日清理
    if not purgeTimer then
        purgeTimer = hs.timer.doEvery(24 * 60 * 60, function()
            store.purgeOlderThan(cfg.retain_days or 7)
        end)
    end
    -- 监听剪贴板（pcall 防回调报错冒泡杀死 event tap）
    if not (pbWatcher and pbWatcher:running()) then
        pbWatcher = hs.pasteboard.watcher.new(function()
            local ok, err = pcall(watcher.captureCurrent)
            if not ok then logger.ef("剪贴板捕获异常: %s", tostring(err)) end
        end)
        pbWatcher:start()
    end
end

--- 停止
function watcher.stop()
    if pbWatcher then pcall(function() pbWatcher:stop() end); pbWatcher = nil end
    if purgeTimer then pcall(function() purgeTimer:stop() end); purgeTimer = nil end
    if suppressTimer then suppressTimer:stop(); suppressTimer = nil end
    suppressCapture = false
    store.close()
    fireChange()
end

-- =====================================================================
-- 对外查询 API
-- =====================================================================

--- 全部历史（只读引用，最新在前）
--- @return array of {id, text, created}
function watcher.all()
    return entries
end

--- 分页搜索（LIKE 模糊，走 DB）
--- 数据源是 SQLite：内存缓存 entries 仅作展示用，不作为搜索源，
--- 保证重启/异步清理后搜索与库严格一致（不会丢数据）。
--- 性能：依赖 store 的 idx_clips_kind 索引先按 kind='text' 过滤，
---      LIKE 只作用于文本行，不会扫过 image 的 MB 级 data URI。
--- @return rows array of {id, text, created}, total
function watcher.search(term, offset, limit)
    return store.search(term, offset, limit)
end

--- 取单条（先查内存缓存，未命中再查 DB）
--- @return {id, text, created} | nil
function watcher.get(id)
    if not id then return nil end
    for _, e in ipairs(entries) do
        if e.id == id then return e end
    end
    return store.get(id)
end

-- =====================================================================
-- 对外写操作（内存 + DB 协调）
-- =====================================================================

--- 删除一条（同步删内存 + 同步删 DB）
function watcher.remove(id)
    if not id then return false end
    -- 先从内存移除
    for i, e in ipairs(entries) do
        if e.id == id then
            table.remove(entries, i)
            break
        end
    end
    store.remove(id)
    fireChange()
    return true
end

--- 置顶一条（同步内存 + 异步 DB）
--- @param id number
function watcher.promote(id)
    if not id then return false end
    -- 内存：挪到最前
    for i, e in ipairs(entries) do
        if e.id == id then
            if i == 1 then return true end  -- 已在顶
            table.remove(entries, i)
            table.insert(entries, 1, e)
            break
        end
    end
    -- DB：异步更新时间戳
    store.touch(id)
    return true
end

--- 切换星标置顶（DB 落盘 + 同步内存标记），返回新 starred 值；未找到返回 nil
function watcher.toggleStar(id)
    local nv = store.toggleStar(id)
    if nv == nil then return nil end
    for _, e in ipairs(entries) do
        if e.id == id then e.starred = nv; break end
    end
    return nv
end

--- 复制次数 +1（DB 落盘 + 同步内存）
function watcher.bumpCount(id)
    if not id then return end
    store.bumpCount(id)
    for _, e in ipairs(entries) do
        if e.id == id then e.count = (e.count or 0) + 1; break end
    end
end

-- =====================================================================
-- 内部：捕获 + 入库
-- =====================================================================

--- 抑制下一次捕获（写回剪贴板前调，避免误当作新复制入库）
function watcher.suspendNextCapture()
    suppressCapture = true
    if suppressTimer then suppressTimer:stop() end
    suppressTimer = hs.timer.doAfter(0.5, function()
        suppressCapture = false
        suppressTimer = nil
    end)
end

--- 判断 UTI 是否图片类型
local function isImageUti(uti)
    if not uti or type(uti) ~= "string" then return false end
    if uti:match("^public%.image") then return true end
    if uti:match("^public%.png") then return true end
    if uti:match("^public%.tiff") then return true end
    if uti:match("^public%.jpeg") or uti:match("^public%.-jpeg") then return true end
    if uti:match("^public%.gif") then return true end
    if uti:match("^public%.heic") or uti:match("^public%.heif") then return true end
    if uti:match("^public%.svg") then return true end
    if uti:find("image") then return true end
    return false
end

--- 采集当前剪贴板并入历史
function watcher.captureCurrent()
    if suppressCapture then
        suppressCapture = false
        return
    end

    -- 检测图片类型
    local isImage = false
    local contents = hs.pasteboard.contentTypes()
    if contents then
        for _, uti in ipairs(contents) do
            if isImageUti(uti) then isImage = true; break end
        end
    end

    -- 图片：存 data URI + kind="image"（除非纯文本模式）
    if isImage and not (cfg and cfg.text_only) then
        local img = hs.pasteboard.readImage()
        if img then
            -- 签名 encodeAsURLString([scale], [type])：显式 (false, "png")，
            -- 传 "png" 会被当 truthy scale（Retina 图片被降采样）
            local ok, b64 = pcall(function() return img:encodeAsURLString(false, "png") end)
            if ok and b64 and b64 ~= "" then
                watcher._push(b64, "image")
                return
            end
        end
    end

    local text = hs.pasteboard.getContents()
    if text and text ~= "" then
        watcher._push(text, "text")
    end
end

--- 压入一条（写库 + 更新内存 + 去重 + 裁剪）
--- @param text string
--- @param kind string "text"|"image"
function watcher._push(text, kind)
    kind = kind or "text"
    -- hash 去重：库中已有相同内容 → 提升置顶 + 计数（不新增，彻底避免重复）
    -- 覆盖场景：写回历史条目触发捕获、连续复制同一内容、suppress 竞态漏拦
    local existing = store.findByText(text)
    if existing then
        watcher.promote(existing.id)
        watcher.bumpCount(existing.id)
        fireChange()
        return existing.id
    end
    -- 与最近一条相同则跳过（内存快速路径）
    if entries[1] and entries[1].text == text then return end
    local id = store.insert(text, kind)
    if not id then return end
    table.insert(entries, 1, { id = id, text = text, kind = kind, created = os.time(), count = 0, starred = 0 })
    -- 容量裁剪
    local max = (cfg and cfg.max_entries) or 300
    while #entries > max do
        local rem = table.remove(entries)
        if rem and rem.id then store.remove(rem.id) end
    end
    -- 容量裁剪：内存已同步删超出部分（store.remove 落库），
    -- 不再每次起进程 trim——早期异步 CLI 方案跨进程写 WAL 搞坏过库
    fireChange()
end

--- 从 DB 重载内存缓存
function watcher.reload()
    entries = {}
    for _, e in ipairs(store.all()) do
        table.insert(entries, e)
    end
    return #entries
end

--- 是否监听中
function watcher.running()
    return pbWatcher ~= nil and pbWatcher:running() == true
end

return watcher

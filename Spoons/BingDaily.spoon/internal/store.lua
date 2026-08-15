--- BingDaily.internal.store
--- SQLite 薄层存储：设置（settings 表 key-value）+ 下载历史（downloads 表）。
--- 对齐 Launcher/FileSearch store 模式：ORM 定义 + migrate 版本化建表 + 绑定参数 SQL。
--- 旧 settings.json 首次启动时自动迁移进 SQLite 后删除。
local store = {}

local HSUtil   = require("core.hsutil")
local conn     = HSUtil.db
local orm      = HSUtil.db.orm
local migrate  = HSUtil.db.migrate
local pathUtil = HSUtil.path

-- settings: 设置 key-value
local Settings = orm.define({
    table = "settings",
    columns = {
        { name = "key",   type = "TEXT PRIMARY KEY" },
        { name = "value", type = "TEXT" },
    },
})

-- downloads: 下载历史（每次下载/应用壁纸记录一条）
local Downloads = orm.define({
    table = "downloads",
    columns = {
        { name = "id",         type = "INTEGER PRIMARY KEY AUTOINCREMENT" },
        { name = "name",       type = "TEXT NOT NULL" },   -- 文件名（含扩展名）
        { name = "url",        type = "TEXT NOT NULL" },
        { name = "date",       type = "TEXT" },            -- Bing 归档日期 YYYYMMDD
        { name = "copyright",  type = "TEXT" },
        { name = "applied",    type = "INTEGER NOT NULL DEFAULT 0" },  -- 是否已设为壁纸
        { name = "created_at", type = "INTEGER NOT NULL" },
    },
})

-- v1：settings 建表
-- v2：downloads 建表
migrate.register("bingdaily", 1, function(db)
    db:exec([[CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT
    );]])
end)
migrate.register("bingdaily", 2, function(db)
    db:exec([[CREATE TABLE IF NOT EXISTS downloads (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL,
        url        TEXT NOT NULL,
        date       TEXT,
        copyright  TEXT,
        applied    INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
    );]])
    db:exec([[CREATE INDEX IF NOT EXISTS idx_downloads_created ON downloads(created_at DESC);]])
end)

local db = nil

--- 打开数据库（缺省 dataDir/bingdaily/bingdaily.db）
function store.open(dataDir)
    if db then store.close() end
    dataDir = dataDir or HSUtil.path.dataDir() .. "/bingdaily"
    pathUtil.ensureDir(dataDir)
    db = conn.open(pathUtil.join(dataDir, "bingdaily.db"))
    if not db then error("无法打开 SQLite 数据库: " .. dataDir) end
    migrate.apply(db, "bingdaily")
    Settings:bind(db)
    Downloads:bind(db)
    store.migrateLegacyJson(dataDir)
    return db
end

function store.close()
    if db then conn.close(db); db = nil end
end

--- 旧 settings.json 迁移：SQLite 无记录且 json 存在时读入，成功后删除 json
function store.migrateLegacyJson(dataDir)
    local legacy = pathUtil.join(dataDir, "settings.json")
    local f = io.open(legacy, "rb")
    if not f then return end
    local raw = HSUtil.json.tryDecode(f:read("*a"), nil)
    f:close()
    if type(raw) ~= "table" then
        os.remove(legacy)
        return
    end
    local has = store.loadSettings()
    if not next(has) then
        store.saveSettings(raw)
    end
    os.remove(legacy)
end

--- 读全部设置
--- @return table
function store.loadSettings()
    local out = {}
    if not db then return out end
    local rows = Settings:query({ select = "key, value" })
    for _, r in ipairs(rows) do
        if r.key == "interval_hours" then
            out.interval_hours = tonumber(r.value)
        elseif r.key == "save_dir" then
            out.save_dir = r.value
        elseif r.key == "auto_apply" then
            out.auto_apply = r.value == "true"
        elseif r.key == "archive_days" then
            out.archive_days = tonumber(r.value)
        elseif r.key == "notify_enabled" then
            out.notify_enabled = r.value == "true"
        elseif r.key == "apply_to_screens" then
            out.apply_to_screens = r.value
        end
    end
    return out
end

--- 保存设置（逐项 upsert）
--- @param t table 可编辑项子集
function store.saveSettings(t)
    if not db or type(t) ~= "table" then return end
    local function upsert(key, value)
        local stmt = db:prepare([[
            INSERT INTO settings(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        ]])
        if not stmt then return end
        stmt:bind_values(key, value)
        stmt:step()
        stmt:finalize()
    end
    if t.interval_hours ~= nil then upsert("interval_hours", tostring(t.interval_hours)) end
    if t.save_dir ~= nil then upsert("save_dir", tostring(t.save_dir)) end
    if t.auto_apply ~= nil then upsert("auto_apply", t.auto_apply and "true" or "false") end
    if t.archive_days ~= nil then upsert("archive_days", tostring(t.archive_days)) end
    if t.notify_enabled ~= nil then upsert("notify_enabled", t.notify_enabled and "true" or "false") end
    if t.apply_to_screens ~= nil then upsert("apply_to_screens", tostring(t.apply_to_screens)) end
end

--- 记录一次下载
--- @param rec table {name=, url=, date=, copyright=, applied=}
function store.addDownload(rec)
    if not db then return nil end
    return Downloads:insert({
        name = rec.name,
        url = rec.url,
        date = rec.date or "",
        copyright = rec.copyright or "",
        applied = rec.applied and 1 or 0,
        created_at = os.time(),
    })
end

--- 最近下载记录（设置页展示）
--- @param limit number 条数（默认 10）
function store.listDownloads(limit)
    if not db then return {} end
    local rows = Downloads:query({
        order = "id DESC",
        limit = math.max(1, math.min(50, limit or 10)),
    })
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id,
            name = r.name,
            url = r.url,
            date = r.date,
            copyright = r.copyright,
            applied = (tonumber(r.applied) or 0) == 1,
            created_at = r.created_at,
        }
    end
    return out
end

--- 按文件名查是否已下载过（避免重复下载）
function store.findDownload(name)
    if not db then return nil end
    local rows = Downloads:query({
        where = "name=?", binds = { name }, order = "id DESC",
    })
    return rows[1]
end

--- 将某条下载标记为已应用
function store.markApplied(name)
    if not db or not name then return end
    local rows = Downloads:query({ where = "name=?", binds = { name } })
    for _, r in ipairs(rows) do
        Downloads:updateById(r.id, { applied = 1 })
    end
end

return store

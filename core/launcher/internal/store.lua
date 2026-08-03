--- Launcher.internal.store
--- SQLite 薄层存储：应用启动频次 + 动态书签（useractions）。
--- 对齐 Clipboard.store 模式：ORM 定义 + migrate 版本化建表；counter/upsert 保留绑定参数 SQL。
local store = {}

local HSUtil   = require("core.hsutil")
local conn     = HSUtil.db
local orm      = HSUtil.db.orm
local migrate  = HSUtil.db.migrate
local pathUtil = HSUtil.path

-- 对齐 Clipboard.store 的 _log 钩子模式：模块内统一日志出口，
-- 供未来异步路径（如 sqlite3 CLI 批量操作）回调记录用；当前无异步调用点。
do
    local logger = HSUtil.log.new("Launcher.store")
    store._log = function(fmt, ...) logger.f(fmt, ...) end
end

-- app_stats: path 主键，count 累计启动次数，lastused 最近启动时间戳
local AppStats = orm.define({
    table = "app_stats",
    columns = {
        { name = "path",     type = "TEXT PRIMARY KEY" },
        { name = "count",    type = "INTEGER NOT NULL DEFAULT 0" },
        { name = "lastused", type = "INTEGER NOT NULL DEFAULT 0" },
    },
})

-- user_actions: 动态书签（add/del 关键词维护），name 主键 upsert
local UserActions = orm.define({
    table = "user_actions",
    columns = {
        { name = "name",    type = "TEXT PRIMARY KEY" },
        { name = "url",     type = "TEXT" },
        { name = "icon",    type = "TEXT" },          -- 编码后的图标 data URI
        { name = "created", type = "INTEGER NOT NULL DEFAULT 0" },
    },
})

-- v1：user_actions 建表（幂等；app_stats 由 ORM ensureTable 兜底）
migrate.register("launcher", 1, function(db)
    db:exec([[CREATE TABLE IF NOT EXISTS user_actions (
        name    TEXT PRIMARY KEY,
        url     TEXT,
        icon    TEXT,
        created INTEGER NOT NULL DEFAULT 0
    );]])
end)

local db = nil
local dbPath = nil

--- 打开数据库（缺省 dataDir/launcher/launcher.db）
--- @param dataDir string|nil 数据目录根（默认 HSUtil.path.dataDir()）
function store.open(dataDir)
    if db then store.close() end
    dataDir = dataDir or HSUtil.path.dataDir()
    pathUtil.ensureDir(dataDir)
    dbPath = pathUtil.join(dataDir, "launcher.db")
    db = conn.open(dbPath)
    if not db then error("无法打开 SQLite 数据库: " .. dbPath) end
    migrate.apply(db, "launcher")
    AppStats:bind(db)
    UserActions:bind(db)
    return db
end

function store.close()
    if db then conn.close(db); db = nil end
end

--- 是否已打开
function store.isOpen()
    return db ~= nil and db:isopen()
end

-- =====================================================================
-- app_stats（应用启动频次）
-- =====================================================================

--- 启动一次：count+1、更新 lastused（upsert；ORM 无 upsert，走绑定参数 SQL，
--- 与 Clipboard.store.bumpCount 同哲学）
--- @param path string 应用 .app 绝对路径
function store.bump(path)
    if not db or not path or path == "" then return end
    local stmt = db:prepare([[
        INSERT INTO app_stats(path, count, lastused) VALUES(?, 1, ?)
        ON CONFLICT(path) DO UPDATE SET count = count + 1, lastused = excluded.lastused
    ]])
    if not stmt then return end
    stmt:bind_values(path, os.time())
    stmt:step()
    stmt:finalize()
end

--- 取全部启动计数：path -> {count=, lastused=}
--- @return table
function store.all()
    local out = {}
    if not db then return out end
    local rows = AppStats:query({ select = "path, count, lastused" })
    for _, r in ipairs(rows) do
        if r.path then
            out[r.path] = { count = tonumber(r.count) or 0, lastused = tonumber(r.lastused) or 0 }
        end
    end
    return out
end

-- =====================================================================
-- user_actions（动态书签）
-- =====================================================================

--- 保存/更新一条书签（upsert，name 主键）
--- @param name string 书签名
--- @param v table { url=string|nil, icon=string|nil }
function store.upsertAction(name, v)
    if not db or not name or name == "" then return end
    v = v or {}
    local stmt = db:prepare([[
        INSERT INTO user_actions(name, url, icon, created) VALUES(?, ?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET url = excluded.url, icon = excluded.icon
    ]])
    if not stmt then return end
    stmt:bind_values(name, v.url or "", v.icon or "", os.time())
    stmt:step()
    stmt:finalize()
end

--- 删除一条书签
--- @param name string
function store.deleteAction(name)
    if not db or not name or name == "" then return end
    local stmt = db:prepare("DELETE FROM user_actions WHERE name = ?")
    if not stmt then return end
    stmt:bind_values(name)
    stmt:step()
    stmt:finalize()
end

--- 取全部书签：name -> {url=, encoded_icon=, created=}
--- （DB 列 icon 映射回 encoded_icon，sources.activate 的解码循环零改动复用）
--- @return table
function store.allActions()
    local out = {}
    if not db then return out end
    local rows = UserActions:query({ select = "name, url, icon, created" })
    for _, r in ipairs(rows) do
        if r.name then
            out[r.name] = { url = r.url or "", encoded_icon = r.icon or "", created = r.created or 0 }
        end
    end
    return out
end

return store

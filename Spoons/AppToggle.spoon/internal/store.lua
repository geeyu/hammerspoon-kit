--- AppToggle.internal.store
--- SQLite 存储：apps 表（应用绑定列表）+ settings 表（键值）。
--- 对齐 Clipboard/BingDaily store 模式：ORM 定义 + migrate 版本化建表。
local store = {}

local HSUtil   = require("core.hsutil")
local conn     = HSUtil.db
local orm      = HSUtil.db.orm
local migrate  = HSUtil.db.migrate
local pathUtil = HSUtil.path

-- 应用绑定表
local Apps = orm.define({
    table = "apps",
    columns = {
        { name = "id",   type = "INTEGER PRIMARY KEY AUTOINCREMENT" },
        { name = "name", type = "TEXT NOT NULL" },
        { name = "bundle_id", type = "TEXT NOT NULL UNIQUE" },
        -- mods 存 JSON 数组字符串：["ctrl","alt"]
        { name = "mods", type = "TEXT NOT NULL DEFAULT '[]'" },
        { name = "key",  type = "TEXT NOT NULL" },
        { name = "enabled", type = "INTEGER NOT NULL DEFAULT 1" },
        -- 应用未运行时：launch=启动 / activate=仅激活（已运行则激活，未运行不做）
        { name = "on_no_window", type = "TEXT NOT NULL DEFAULT 'launch'" },
        { name = "fullscreen_fallback", type = "INTEGER NOT NULL DEFAULT 1" },
        { name = "restore_focus", type = "INTEGER NOT NULL DEFAULT 1" },
        { name = "move_to_mouse_screen", type = "INTEGER NOT NULL DEFAULT 1" },
        { name = "created_at", type = "INTEGER" },
    },
})

-- settings: 键值（面板尺寸等全局项）
local Settings = orm.define({
    table = "settings",
    columns = {
        { name = "key",   type = "TEXT PRIMARY KEY" },
        { name = "value", type = "TEXT" },
    },
})

-- v1：建表（幂等）
migrate.register("apptoggle", 1, function(db)
    db:exec([[CREATE TABLE IF NOT EXISTS apps (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        bundle_id TEXT NOT NULL UNIQUE,
        mods TEXT NOT NULL DEFAULT '[]',
        key  TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        on_no_window TEXT NOT NULL DEFAULT 'launch',
        fullscreen_fallback INTEGER NOT NULL DEFAULT 1,
        restore_focus INTEGER NOT NULL DEFAULT 1,
        move_to_mouse_screen INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER
    );]])
    db:exec([[CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT
    );]])
end)

local db = nil

--- 打开数据库（缺省 dataDir/apptoggle/apptoggle.db）
--- @return db|nil
function store.open(dataDir)
    if db then store.close() end
    dataDir = dataDir or pathUtil.dataDir() .. "/apptoggle"
    pathUtil.ensureDir(dataDir)
    db = conn.open(pathUtil.join(dataDir, "apptoggle.db"))
    if not db then return nil end
    migrate.apply(db, "apptoggle")
    Apps:bind(db)
    Settings:bind(db)
    return db
end

function store.close()
    if db then pcall(conn.close, db) db = nil end
end

--- 行 → 应用配置（布尔/JSON 归一化）
local function rowToApp(r)
    if not r then return nil end
    local ok, mods = pcall(HSUtil.json.decode, r.mods)
    if not ok or type(mods) ~= "table" then mods = {} end
    return {
        id = r.id,
        name = r.name,
        bundle_id = r.bundle_id,
        mods = mods,
        key = r.key,
        enabled = (tonumber(r.enabled) or 0) == 1,
        on_no_window = r.on_no_window or "launch",
        fullscreen_fallback = (tonumber(r.fullscreen_fallback) or 1) == 1,
        restore_focus = (tonumber(r.restore_focus) or 1) == 1,
        move_to_mouse_screen = (tonumber(r.move_to_mouse_screen) or 1) == 1,
        created_at = r.created_at,
    }
end

--- 全部应用（按创建序）
function store.listApps()
    if not db then return {} end
    local rows = Apps:query({ order = "id ASC" })
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = rowToApp(r) end
    return out
end

--- 按 bundle_id 查
function store.findApp(bundleID)
    if not db then return nil end
    local rows = Apps:query({ where = "bundle_id=?", binds = { bundleID } })
    return rowToApp(rows[1])
end

--- 新增应用；bundle_id 已存在则更新（upsert 语义）
--- @param app table {name,bundle_id,mods,key,...}
--- @return id|nil, err|nil
function store.upsertApp(app)
    if not db then return nil, "数据库未打开" end
    local ok, modsJson = pcall(HSUtil.json.encode, app.mods or {})
    if not ok then modsJson = "[]" end
    local row = {
        name = app.name,
        bundle_id = app.bundle_id,
        mods = modsJson,
        key = app.key,
        enabled = app.enabled and 1 or 0,
        on_no_window = app.on_no_window or "launch",
        fullscreen_fallback = app.fullscreen_fallback and 1 or 0,
        restore_focus = app.restore_focus and 1 or 0,
        move_to_mouse_screen = app.move_to_mouse_screen and 1 or 0,
    }
    local existing = store.findApp(app.bundle_id)
    if existing then
        row.id = existing.id
        Apps:updateById(existing.id, row)
        return existing.id
    end
    row.created_at = os.time()
    return Apps:insert(row)
end

--- 删除应用
function store.deleteApp(id)
    if not db then return 0 end
    return Apps:deleteById(id)
end

--- 设置读写（全局键值）
function store.getSetting(key)
    if not db then return nil end
    local rows = Settings:query({ where = "key=?", binds = { key } })
    return rows[1] and rows[1].value or nil
end

function store.setSetting(key, value)
    if not db then return end
    local stmt = db:prepare([[
        INSERT INTO settings(key, value) VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
    ]])
    if not stmt then return end
    stmt:bind_values(key, tostring(value))
    stmt:step()
    stmt:finalize()
end

return store

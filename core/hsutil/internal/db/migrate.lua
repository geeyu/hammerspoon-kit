--- HSUtil.internal.db.migrate
--- schema 版本迁移。每张业务表一个迁移注册，按版本号顺序应用。
local migrate = {}

local registry = {}  -- name -> { {version=, fn=} }

--- 注册迁移
--- @param name string 业务名（如 "clips"）
--- @param version number 版本号（递增）
--- @param fn function(db) 执行迁移
function migrate.register(name, version, fn)
    registry[name] = registry[name] or {}
    table.insert(registry[name], { version = version, fn = fn })
end

local function ensureSchemaTable(db)
    db:exec([[CREATE TABLE IF NOT EXISTS schema_version (
        name    TEXT PRIMARY KEY,
        version INTEGER NOT NULL DEFAULT 0
    );]])
end

local function currentVersion(db, name)
    local v = 0
    local stmt = db:prepare("SELECT version FROM schema_version WHERE name=?")
    if not stmt then return 0 end
    stmt:bind_values(name)
    local row
    for r in stmt:nrows() do row = r; break end
    if row and row.version then v = tonumber(row.version) end
    stmt:finalize()
    return v
end

--- 应用某 name 的所有未应用迁移
--- @param db userdata
--- @param name string
--- @return number 应用后的版本号
function migrate.apply(db, name)
    ensureSchemaTable(db)
    local cur = currentVersion(db, name)
    local list = registry[name]
    if not list then return cur end
    table.sort(list, function(a, b) return a.version < b.version end)
    for _, m in ipairs(list) do
        if m.version > cur then
            db:exec("BEGIN;")
            local ok, err = pcall(m.fn, db)
            if not ok then
                db:exec("ROLLBACK;")
                error("migrate " .. name .. " v" .. m.version .. " failed: " .. tostring(err))
            end
            local stmt = db:prepare("INSERT OR REPLACE INTO schema_version(name,version) VALUES(?,?)")
            if stmt then
                stmt:bind_values(name, m.version)
                stmt:step()
                stmt:finalize()
            end
            db:exec("COMMIT;")
        end
    end
    return currentVersion(db, name)
end

return migrate

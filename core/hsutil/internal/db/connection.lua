--- HSUtil.internal.db.connection
--- SQLite 连接管理。基于 hs.sqlite3（LSQLite 0.9.5）。
local connection = {}

local sqlite3 = require("hs.sqlite3")
local path = require("HSUtil.internal.path")

--- 打开数据库（目录不存在则建）
--- @param dbPath string 完整 .db 路径
--- @return db userdata + err
function connection.open(dbPath)
    local dir = dbPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then path.ensureDir(dir) end
    local db, err = sqlite3.open(dbPath)
    if not db then return nil, err end
    db:exec("PRAGMA foreign_keys = ON;")
    db:exec("PRAGMA journal_mode = WAL;")
    return db
end

--- 关闭
function connection.close(db)
    if db and db:isopen() then
        pcall(function() db:close() end)
    end
end

--- 包裹执行：自动用连接跑 fn
--- @param db userdata
--- @param fn function(db) -> result
function connection.withDB(db, fn)
    if not db or not db:isopen() then return nil, "db not open" end
    local ok, r = pcall(fn, db)
    if not ok then return nil, r end
    return r
end

return connection

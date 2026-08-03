--- Clipboard.internal.store
--- 纯持久层（基于 HSUtil 薄层 ORM）。只对 watcher 可见，不暴露给 panel。
--- 职责单一：表的 CRUD + 异步批量删除。内存缓存由 watcher 管。
--- 约定：无类型，所有记录都是文本（普通文本或图片 data URI）。
local store = {}

local HSUtil   = require("core.hsutil")
local orm      = HSUtil.db.orm
local conn     = HSUtil.db
local migrate  = HSUtil.db.migrate
local pathUtil = HSUtil.path

-- clips 表定义
-- kind: "text" | "image"（未来可扩 link/file 等）
-- hash: 内容 SHA256 指纹（v4 迁移补列，去重/快速对比用）
-- 表结构演进走 migrate（见下方 register），ORM 的 ensureTable 只兜底幂等建表
local Clips = orm.define({
    table = "clips",
    columns = {
        { name = "id",      type = "INTEGER PRIMARY KEY AUTOINCREMENT" },
        { name = "text",    type = "TEXT" },
        { name = "kind",    type = "TEXT NOT NULL DEFAULT 'text'" },
        { name = "created", type = "INTEGER NOT NULL" },
        { name = "count",   type = "INTEGER NOT NULL DEFAULT 0" },
        { name = "starred", type = "INTEGER NOT NULL DEFAULT 0" },
        { name = "hash",    type = "TEXT" },
    },
    indexes = {
        "idx_clips_created ON clips (created DESC)",
        -- kind 索引：搜索时先按 kind='text' 过滤出文本行，
        -- 避免 LIKE '%term%' 全表扫过 image 的 MB 级 data URI
        "idx_clips_kind ON clips (kind)",
        -- 默认排序索引：ORDER BY starred DESC, created DESC, id DESC 直接沿索引有序扫描，
        -- 配合 LIMIT 提前终止，避免把 image 的 MB 级 text 全量灘进临时 B-tree 排序（呼出卡顿元凶）
        "idx_clips_starred_created ON clips (starred DESC, created DESC, id DESC)",
    },
})

-- ===== 内容指纹（去重用）=====
-- FNV-1a 64 位（纯 Lua；本机 Hammerspoon 无 hs.crypto 扩展）
-- 64 位空间对剪贴板去重足够（碰撞概率 ~2^-64），配合唯一索引兑底
local FNV_OFFSET = 0xcbf29ce484222325
local FNV_PRIME = 0x100000001b3

--- 内容 → 16 位 hex 指纹；空内容/失败返回 nil
local function textHash(text)
    if not text or text == "" then return nil end
    local h = FNV_OFFSET
    for i = 1, #text do
        h = (h ~ string.byte(text, i)) * FNV_PRIME
    end
    return string.format("%016x", h)
end

-- ===== schema 迁移（migrate.apply 在 store.open 时执行，事务保护）=====
-- 顺序注意：老库缺列时建索引会报 "no such column"，故建表 → 补列 → 建索引 分版本。

-- v1：建表（幂等；老库表已存在则不动）
migrate.register("clips", 1, function(db)
    db:exec([[CREATE TABLE IF NOT EXISTS clips (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        text    TEXT,
        kind    TEXT NOT NULL DEFAULT 'text',
        created INTEGER NOT NULL,
        count   INTEGER NOT NULL DEFAULT 0,
        starred INTEGER NOT NULL DEFAULT 0
    );]])
end)

-- v2：老库（v5 之前）无 kind/count/starred 列，幂等补列，否则 SELECT 直接报错
migrate.register("clips", 2, function(db)
    local cols = {}
    for row in db:nrows("PRAGMA table_info(clips)") do cols[row.name] = true end
    if not cols["kind"] then
        db:exec([[ALTER TABLE clips ADD COLUMN kind TEXT NOT NULL DEFAULT 'text';]])
    end
    if not cols["count"] then
        db:exec([[ALTER TABLE clips ADD COLUMN count INTEGER NOT NULL DEFAULT 0;]])
    end
    if not cols["starred"] then
        db:exec([[ALTER TABLE clips ADD COLUMN starred INTEGER NOT NULL DEFAULT 0;]])
    end
end)

-- v3：索引（列齐后才建，新库/老库都安全）
migrate.register("clips", 3, function(db)
    db:exec("CREATE INDEX IF NOT EXISTS idx_clips_created ON clips (created DESC);")
    db:exec("CREATE INDEX IF NOT EXISTS idx_clips_kind ON clips (kind);")
    db:exec("CREATE INDEX IF NOT EXISTS idx_clips_starred_created ON clips (starred DESC, created DESC, id DESC);")
end)

-- v4：hash 列（内容指纹，去重/快速对比）——补列 → 存量回填 → 清重复 → 唯一索引
migrate.register("clips", 4, function(db)
    local cols = {}
    for row in db:nrows("PRAGMA table_info(clips)") do cols[row.name] = true end
    if not cols["hash"] then
        db:exec("ALTER TABLE clips ADD COLUMN hash TEXT;")
    end
    -- 存量回填（老数据 hash 为空）
    local sel = db:prepare("SELECT id, text FROM clips WHERE hash IS NULL OR hash = ''")
    local upd = db:prepare("UPDATE clips SET hash = ? WHERE id = ?")
    if sel and upd then
        for row in sel:nrows() do
            local h = textHash(row.text or "")
            if h then
                upd:bind_values(h, row.id)
                upd:step()
                upd:reset()
            end
        end
        sel:finalize()
        upd:finalize()
    end
    -- 清理历史重复（保留每组 hash 最新一条；AUTOINCREMENT id 越大越新）
    db:exec([[DELETE FROM clips WHERE hash IS NOT NULL AND hash <> '' AND id NOT IN (
        SELECT MAX(id) FROM clips WHERE hash IS NOT NULL AND hash <> '' GROUP BY hash);]])
    -- 唯一索引兜底（并发/竞态下防重复）
    db:exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_clips_hash ON clips(hash);")
end)

local db = nil
local dbPath

do
    local logger = hs.logger.new("Clipboard.store", "info")
    store._log = function(fmt, ...) logger.f(fmt, ...) end
end

-- =====================================================================
-- 生命周期
-- =====================================================================

--- 打开数据库（自动建目录 + ORM 建表）
--- @param dataDir string 数据目录
--- @param dbFile string|nil 数据库文件名（默认 history.db）
function store.open(dataDir, dbFile)
    if db then store.close() end
    pathUtil.ensureDir(dataDir)
    dbPath = dataDir .. "/" .. (dbFile or "history.db")
    db = conn.open(dbPath)
    if not db then
        error("无法打开 SQLite 数据库: " .. dbPath)
    end
    -- schema 版本迁移（建表/补列，事务保护）
    migrate.apply(db, "clips")
    Clips:bind(db)
    return db
end

--- 关闭
function store.close()
    if db then
        conn.close(db)
        db = nil
    end
end

--- 是否已打开
function store.isOpen()
    return db ~= nil and db:isopen()
end

-- =====================================================================
-- 单条 CRUD（同步）
-- =====================================================================

--- 插入一条（返回 dbid 或 nil）
--- @param text string 文本（普通文本或图片 data URI）
--- @param kind string|nil "text"|"image"，默认 "text"
--- @param created number|nil 时间戳，省略取当前
function store.insert(text, kind, created)
    if not db or not text or text == "" then return nil end
    return Clips:insert({
        text    = text,
        kind    = kind or "text",
        created = created or os.time(),
        hash    = textHash(text),
    })
end

--- 按内容查找（内部算 hash；去重用：库中已有相同内容 → 提升而非新增）
--- @return {id, text, kind, created, count, starred} | nil
function store.findByText(text)
    local h = textHash(text)
    if not db or not h then return nil end
    local stmt = db:prepare("SELECT id, text, kind, created, count, starred FROM clips WHERE hash = ? LIMIT 1")
    if not stmt then return nil end
    stmt:bind_values(h)
    local row
    for r in stmt:nrows() do row = r; break end
    stmt:finalize()
    if not row then return nil end
    return {
        id = row.id, text = row.text or "", kind = row.kind or "text",
        created = row.created, count = row.count or 0, starred = row.starred or 0,
    }
end

--- 取单条
--- @return {id, text, kind, created} | nil
function store.get(id)
    if not db or not id then return nil end
    return Clips:findById(id)
end

--- 按 id 删除（同步）
function store.remove(id)
    if not db or not id then return 0 end
    return Clips:deleteById(id)
end

--- 复制次数 +1（条目被选中写回剪贴板时调用，同步单行 UPDATE）
function store.bumpCount(id)
    if not db or not id then return end
    local stmt = db:prepare("UPDATE clips SET count = count + 1 WHERE id = ?")
    if not stmt then return end
    stmt:bind_values(id)
    stmt:step()
    stmt:finalize()
end

--- 切换星标置顶，返回新的 starred（0/1）；未找到返回 nil
function store.toggleStar(id)
    if not db or not id then return nil end
    local row = Clips:findById(id)
    if not row then return nil end
    local nv = (tonumber(row.starred) or 0) == 1 and 0 or 1
    local n = Clips:updateById(id, { starred = nv })
    if (n or 0) == 0 then return nil end
    return nv
end

--- 更新 created 时间戳（同步落库，单行 UPDATE 毫秒级，不再起 CLI 子进程）
--- 同步查 MAX(created) 保证严格递增，避免同秒撞时间戳。
--- @return number 新时间戳
function store.touch(id)
    if not db or not id then return nil end
    local maxC = 0
    -- ORDER BY created DESC LIMIT 1 走 idx_clips_created，避免全表扫
    local sel = db:prepare("SELECT created AS m FROM clips ORDER BY created DESC LIMIT 1")
    if sel then
        for row in sel:nrows() do
            if row and row.m then maxC = row.m end
        end
        sel:finalize()
    end
    local newCreated = math.max(os.time(), (maxC or 0) + 1)
    local up = db:prepare("UPDATE clips SET created = ? WHERE id = ?")
    if up then
        up:bind_values(newCreated, id)
        up:step()
        up:finalize()
    end
    return newCreated
end

-- =====================================================================
-- 查询（同步）
-- =====================================================================

--- 加载全部（按时间倒序，供 watcher 启动时填充内存缓存）
--- @return array of {id, text, kind, created}
function store.all()
    local out = {}
    if not db then return out end
    local rows = Clips:query({ select = "id, text, kind, created, count, starred", order = "starred DESC, created DESC, id DESC" })
    for _, row in ipairs(rows) do
        out[#out + 1] = { id = row.id, text = row.text or "", kind = row.kind or "text", created = row.created, count = row.count or 0, starred = row.starred or 0 }
    end
    return out
end

--- 分页搜索（LIKE 模糊匹配）
--- @param term string|nil 搜索词，nil/空串表示不过滤
--- @param offset number 默认 0
--- @param limit  number 默认 20
--- @return rows array of {id, text, created}, total number
--- 注意：image 行的 text 恒返回空串（真·延迟加载）——
---   列表接口不下发 MB 级 data URI，前端凭 id 走 GET /:id/image 按需拉取。
---   用 CASE 在 SQL 层剥离，SQLite 根本不读 image 的 text 列（避开 overflow 页），
---   呼出 payload 从 ~20MB 降到 ~50KB。搜索词场景本就 kind='text' 过滤掉图片，不受影响。
function store.search(term, offset, limit)
    local out = {}
    if not db then return out, 0 end
    offset = offset or 0
    limit  = limit  or 20

    local function escapeLike(s)
        return (s:gsub("\\", "\\\\"):gsub("%%", "\\%%"):gsub("_", "\\_"))
    end

    local where, binds
    if term and term ~= "" then
        -- kind 放前面：配合 idx_clips_kind 索引先过滤出文本行，LIKE 不作用于图片
        where = "kind = 'text' AND text LIKE ? ESCAPE '\\'"
        binds = { "%" .. escapeLike(term) .. "%" }
    end

    local rows, total = Clips:query({
        select = "id, CASE WHEN kind='image' THEN '' ELSE text END AS text, kind, created, count, starred",
        where = where, binds = binds,
        order = "starred DESC, created DESC, id DESC",
        limit = limit, offset = offset,
    })
    for _, row in ipairs(rows) do
        out[#out + 1] = { id = row.id, text = row.text or "", kind = row.kind or "text", created = row.created, count = row.count or 0, starred = row.starred or 0 }
    end
    return out, total
end

--- 总条数
function store.count()
    if not db then return 0 end
    return Clips:count()
end

-- =====================================================================
-- 批量删除（异步，不阻塞主线程）
-- =====================================================================
-- 批量删除（同步，走 Lua 连接单进程访问）
-- =====================================================================
-- 历史教训：早期用 hs.task 起 sqlite3 CLI 子进程异步执行 DELETE，
--   与 Lua 连接并发操作同一 WAL 库——子进程写 WAL 中途被杀/系统睡眠时
--   会搞坏 wal/shm 状态，导致运行中连接所有查询报 disk I/O error 挂死。
-- 现统一走 Lua 连接（单进程访问），低频调用（启动兑底/每日清理）毫秒级，
--   即使图片多时偶发卡顿也远好于跨进程损坏库。

--- 删除 N 天前的记录（同步）
--- @param days number 保留天数
--- @return number 实际删除条数
function store.purgeOlderThan(days)
    if not db then return 0 end
    days = days or 7
    local cutoff = os.time() - days * 86400
    local n = Clips:count({ where = "created < ?", binds = { cutoff } })
    if n > 0 then
        local stmt = db:prepare("DELETE FROM clips WHERE created < ?")
        if stmt then
            stmt:bind_values(cutoff)
            stmt:step()
            stmt:finalize()
            store._log("清理完成：%d 条（>%d天）", n, days)
        end
    end
    return n
end

--- 容量裁剪：保留最近 keep 条（同步；仅启动时兑底，平时内存裁剪已同步删）
--- @param keep number
--- @return number 删除条数
function store.trim(keep)
    if not db then return 0 end
    keep = keep or 300
    local total = Clips:count()
    local toDel = total - keep
    if toDel <= 0 then return 0 end
    local stmt = db:prepare([[DELETE FROM clips WHERE id NOT IN (
        SELECT id FROM clips ORDER BY created DESC, id DESC LIMIT ?);]])
    if stmt then
        stmt:bind_values(keep)
        stmt:step()
        stmt:finalize()
        store._log("容量裁剪：删 %d 条（保留 %d）", toDel, keep)
    end
    return toDel
end

return store

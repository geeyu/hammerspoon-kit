--- HSUtil.internal.db.orm
--- 薄层 ORM。保持 prepare/bind 风格，不藏 SQL，不做关联/钩子/链式。
local orm = {}

local function ensureTable(db, def)
    local cols = {}
    for _, c in ipairs(def.columns) do
        table.insert(cols, c.name .. " " .. c.type)
    end
    db:exec(string.format("CREATE TABLE IF NOT EXISTS %s (%s);",
        def.table, table.concat(cols, ", ")))
    for _, idx in ipairs(def.indexes or {}) do
        db:exec(string.format("CREATE INDEX IF NOT EXISTS %s;", idx))
    end
end

--- 定义一张表
--- @param def table { table=, columns={{name=,type=}}, indexes={...} }
--- @return model table
function orm.define(def)
    assert(def and def.table, "orm.define: table 必填")
    assert(def and def.columns, "orm.define: columns 必填")

    local model = { _def = def, _db = nil, table = def.table }

    function model:bind(db)
        self._db = db
        ensureTable(db, def)
        return self
    end

    local function dbOf(self)
        assert(self._db, "orm: model 未 bind，请先 :bind(db)")
        return self._db
    end

    --- 插入
    --- @param row table {col=val,...}
    --- @return rowid|nil
    function model:insert(row)
        local db = dbOf(self)
        local cols, ph, vals = {}, {}, {}
        for _, c in ipairs(def.columns) do
            if row[c.name] ~= nil then
                table.insert(cols, c.name)
                table.insert(ph, "?")
                table.insert(vals, row[c.name])
            end
        end
        local sql = string.format("INSERT INTO %s (%s) VALUES (%s);",
            def.table, table.concat(cols, ","), table.concat(ph, ","))
        local stmt = db:prepare(sql)
        if not stmt then return nil, "prepare failed" end
        if #vals > 0 then stmt:bind_values(table.unpack(vals)) end
        stmt:step()
        local id = db:last_insert_rowid()
        stmt:finalize()
        return id
    end

    --- 按 id 查单条
    function model:findById(id)
        local db = dbOf(self)
        local stmt = db:prepare(string.format("SELECT * FROM %s WHERE id=?", def.table))
        if not stmt then return nil end
        stmt:bind_values(id)
        local row
        for r in stmt:nrows() do row = r; break end
        stmt:finalize()
        return row
    end

    --- 局部更新
    --- @param id number
    --- @param patch table {col=val,...}
    function model:updateById(id, patch)
        local db = dbOf(self)
        local sets, vals = {}, {}
        for _, c in ipairs(def.columns) do
            if patch[c.name] ~= nil and c.name ~= "id" then
                table.insert(sets, c.name .. "=?")
                table.insert(vals, patch[c.name])
            end
        end
        if #sets == 0 then return 0 end
        table.insert(vals, id)
        local sql = string.format("UPDATE %s SET %s WHERE id=?",
            def.table, table.concat(sets, ","))
        local stmt = db:prepare(sql)
        if not stmt then return 0 end
        stmt:bind_values(table.unpack(vals))
        stmt:step()
        local n = db:changes()
        stmt:finalize()
        return n
    end

    --- 按 id 删除
    function model:deleteById(id)
        local db = dbOf(self)
        local stmt = db:prepare(string.format("DELETE FROM %s WHERE id=?", def.table))
        if not stmt then return 0 end
        stmt:bind_values(id)
        stmt:step()
        local n = db:changes()
        stmt:finalize()
        return n
    end

    --- count
    --- @param opt table|nil {where=, binds=}
    function model:count(opt)
        local db = dbOf(self)
        opt = opt or {}
        local sql = "SELECT COUNT(*) AS c FROM " .. def.table
        if opt.where then sql = sql .. " WHERE " .. opt.where end
        local stmt = db:prepare(sql)
        if not stmt then return 0 end
        if opt.binds and #opt.binds > 0 then stmt:bind_values(table.unpack(opt.binds)) end
        local row
        for r in stmt:nrows() do row = r; break end
        stmt:finalize()
        return (row and tonumber(row.c)) or 0
    end

    --- 查询构造器
    --- @param opt table {select=,where=,binds=,order=,limit=,offset=}
    --- @return rows array, total number
    function model:query(opt)
        local db = dbOf(self)
        opt = opt or {}
        local sel = opt.select or "*"
        local where = opt.where and (" WHERE " .. opt.where) or ""
        local order = opt.order and (" ORDER BY " .. opt.order) or ""

        local total = 0
        local csql = "SELECT COUNT(*) AS c FROM " .. def.table .. where
        local cstmt = db:prepare(csql)
        if cstmt then
            if opt.binds and #opt.binds > 0 then
                cstmt:bind_values(table.unpack(opt.binds))
            end
            local row
            for r in cstmt:nrows() do row = r; break end
            if row then total = tonumber(row.c) or 0 end
            cstmt:finalize()
        end

        local rows = {}
        local sql = string.format("SELECT %s FROM %s%s%s", sel, def.table, where, order)
        if opt.limit then sql = sql .. " LIMIT " .. tonumber(opt.limit) end
        if opt.offset then sql = sql .. " OFFSET " .. tonumber(opt.offset) end
        local stmt = db:prepare(sql)
        if not stmt then return rows, total end
        if opt.binds and #opt.binds > 0 then
            stmt:bind_values(table.unpack(opt.binds))
        end
        for row in stmt:nrows() do
            table.insert(rows, row)
        end
        pcall(function() stmt:finalize() end)
        return rows, total
    end

    return model
end

return orm

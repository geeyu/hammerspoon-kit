--- Launcher.internal.api
--- HTTP API 层。把 registry 暴露成 RESTful 路由挂到 HSUtil 共享 server。
--- 路由:
---   GET  /launcher/api/query?text=     聚合候选
---   POST /launcher/api/run             执行候选
---   GET  /launcher/api/sources         启用源/关键词列表
---   静态 /launcher/view/*             Vue3 前端
local api = {}

local HSUtil = require("core.hsutil")
local app = HSUtil.http.app

local registry
local pkg = "launcher"
local viewsDir
local onCloseFn = function() end   -- 关闭面板回调（init 注入）

--- 序列化候选 row 为 JSON（剔除非可序列化字段：fn/cmd，保留 id 供 run 重浄）
local function rowToJSON(r)
    local out = {}
    for k, v in pairs(r) do
        if k == "image" then
            local ok, uri = pcall(function() return v:encodeAsURLString("png") end)
            if ok and uri and uri ~= "" then out.image = uri end
        elseif type(v) ~= "function" and k ~= "cmd" then
            out[k] = v
        end
    end
    return out
end

--- 注册路由
--- @param reg registry 实例
--- @param pkgName string 包名前缀
--- @param viewsDir string|nil 前端视图目录（views/ 根，页面规范 views/pages/<page>/index.html）
--- @param onClose function|nil 关闭面板回调（init 注入 panel.hide）
function api.setup(reg, pkgName, viewsDir, onClose)
    registry = reg
    pkg = pkgName or "launcher"
    if onClose then onCloseFn = onClose end

    -- 前端静态文件（views/ 根，挂 /<pkg>/view/*）
    if viewsDir then
        app:static("/" .. pkg .. "/view", viewsDir)
    end

    -- 聚合候选
    app:get("/" .. pkg .. "/api/query", function(req, res)
        local text = req.query.text or ""
        local ok, result = pcall(registry.query, text)
        if not ok then
            return res:status(500):json({ err = tostring(result) })
        end
        local rows = {}
        for _, r in ipairs(result.rows or {}) do
            rows[#rows + 1] = rowToJSON(r)
        end
        res:json({ rows = rows, keyword = result.keyword, source = result.source, home = result.home or nil, kind = result.kind })
    end)

    -- 执行候选
    app:post("/" .. pkg .. "/api/run", function(req, res)
        local body = req:json()
        local row = body and body.row
        if not row then return res:status(400):json({ err = "missing row" }) end
        local ok, err = pcall(registry.runRow, row)
        if not ok then
            return res:status(400):json({ err = tostring(err) })
        end
        res:json({ ok = true, done = err })
    end)

    -- 启用源/关键词元信息
    app:get("/" .. pkg .. "/api/sources", function(req, res)
        local ok, list = pcall(registry.getSourcesMeta)
        if not ok then return res:status(500):json({ err = tostring(list) }) end
        res:json({ sources = list })
    end)

    -- 关闭面板（前端 QW.hide → 调这里）
    app:post("/" .. pkg .. "/api/close", function(req, res)
        res:json({ ok = true })
        onCloseFn()
    end)
end

return api

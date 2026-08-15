--- Clipboard.internal.api
--- HTTP API 层。把 watcher 暴露成 RESTful 路由挂到 HSUtil 共享 server。
--- 路由规则：/<pkg>/api/*（数据接口）+ /<pkg>/view/*（前端静态文件）
---   GET    /clipboard/api/history           ?term=&offset=&limit=  搜索/分页
---   GET    /clipboard/api/history/:id       取单条
---   GET    /clipboard/api/history/:id/image 图片内容（延迟加载，返回二进制）
---   DELETE /clipboard/api/history/:id       删除
---   POST   /clipboard/api/history/:id/confirm  确认粘贴
---   POST   /clipboard/api/history/:id/star      星标置顶
---   GET    /clipboard/api/settings             读取可编辑配置
---   POST   /clipboard/api/settings             保存配置（校验+持久化+应用回调）
---   POST   /clipboard/api/close                关闭面板
---   静态   /clipboard/view/*             前端文件（views/ 下，页面在 pages/<page>/）
local api = {}

local HSUtil = require("core.hsutil")
local app = HSUtil.http.app
local PKG      -- 包名前缀（config.pkg 注入，路由隔离）
local RES = "history"     -- 资源名（剪贴板历史记录）

local watcher
local config        -- 配置单点（提供 editable/update）
local onConfirmFn   -- 确认回调（init 注入：写回+提升+粘贴）
local onCloseFn     -- 关闭面板回调（init 注入：panel.hide）
local onSettingsApplied  -- 配置保存后回调（init 注入：热键重绑等）

--- 注册路由
--- @param w watcher 业务入口
--- @param onConfirm function(entry) 确认动作（由 init 提供）
--- @param onClose function() 关闭面板（由 init 提供 panel.hide）
--- @param assetsDir string|nil 前端静态文件目录，挂到 /<pkg>/view
--- @param pkg string 包名前缀（路由隔离，config.pkg）
--- @param cfg table|nil 配置单点（提供 editable/update；nil 则 settings 路由不注册）
--- @param onSettingsApplied function(settings)|nil 配置保存后回调（init 注入：热键重绑）
function api.setup(w, onConfirm, onClose, assetsDir, pkg, cfg, onSettingsApplied)
    watcher = w
    onConfirmFn = onConfirm
    onCloseFn = onClose
    PKG = pkg or "clipboard"
    config = cfg
    onSettingsApplied = onSettingsApplied

    -- 前端静态文件（views/ 根，页面规范 views/pages/<page>/index.html）
    if assetsDir then
        app:static("/" .. PKG .. "/view", assetsDir)
    end

    -- 搜索/分页
    app:get("/" .. PKG .. "/api/" .. RES, function(req, res)
        local term = req.query.term or ""
        local offset = tonumber(req.query.offset) or 0
        local limit = tonumber(req.query.limit) or 20
        local ok, rows, total = pcall(watcher.search, term, offset, limit)
        if not ok then
            return res:status(500):json({ err = tostring(rows) })
        end
        res:json({ rows = rows, total = total })
    end)

    -- 取单条
    app:get("/" .. PKG .. "/api/" .. RES .. "/:id", function(req, res)
        local id = tonumber(req.params.id)
        if not id then return res:status(400):json({ err = "bad id" }) end
        local entry = watcher.get(id)
        if not entry then return res:status(404):json({ err = "not found" }) end
        res:json(entry)
    end)

    -- 图片内容（真·延迟加载）：列表只返空 text，浏览器凭此端点按需拉图，
    -- 配合 <img loading="lazy"> 只请求视口内图片。id 由 AUTOINCREMENT 生成永不复用，
    -- 图片内容不可变 → 可放心长缓存。
    app:get("/" .. PKG .. "/api/" .. RES .. "/:id/image", function(req, res)
        local id = tonumber(req.params.id)
        if not id then return res:status(400):json({ err = "bad id" }) end
        local entry = watcher.get(id)
        if not entry or entry.kind ~= "image" then
            return res:status(404):json({ err = "not found" })
        end
        -- data URI 形如 data:image/png;base64,XXXX
        local mime, b64 = (entry.text or ""):match("^data:([^;]+);base64,(.*)$")
        if not mime or not b64 then return res:status(500):json({ err = "bad data uri" }) end
        local ok, bin = pcall(hs.base64.decode, b64)
        if not ok or not bin or bin == "" then
            return res:status(500):json({ err = "decode failed" })
        end
        res:status(200)
            :header("Content-Type", mime)
            :header("Cache-Control", "private, max-age=31536000, immutable")
            :body(bin)
    end)

    -- 删除
    app:delete("/" .. PKG .. "/api/" .. RES .. "/:id", function(req, res)
        local id = tonumber(req.params.id)
        if not id then return res:status(400):json({ err = "bad id" }) end
        watcher.remove(id)
        res:json({ ok = true })
    end)

    -- 确认粘贴
    app:post("/" .. PKG .. "/api/" .. RES .. "/:id/confirm", function(req, res)
        local id = tonumber(req.params.id)
        if not id then return res:status(400):json({ err = "bad id" }) end
        local entry = watcher.get(id)
        if not entry then return res:status(404):json({ err = "not found" }) end
        -- 立即回 200，粘贴动作链异步执行（不阻塞 HTTP 响应）
        res:json({ ok = true })
        hs.timer.doAfter(0, function()
            if onConfirmFn then onConfirmFn(entry) end
        end)
    end)

    -- 切换星标置顶
    app:post("/" .. PKG .. "/api/" .. RES .. "/:id/star", function(req, res)
        local id = tonumber(req.params.id)
        if not id then return res:status(400):json({ err = "bad id" }) end
        local nv = watcher.toggleStar(id)
        if nv == nil then return res:status(404):json({ err = "not found" }) end
        res:json({ ok = true, starred = nv })
    end)

    -- 关闭面板（Esc / 前端调用）
    app:post("/" .. PKG .. "/api/close", function(req, res)
        res:json({ ok = true })
        hs.timer.doAfter(0, function()
            if onCloseFn then onCloseFn() end
        end)
    end)

    -- ===== 设置（settings 页）=====
    if config then
        -- 读取可编辑配置
        app:get("/" .. PKG .. "/api/settings", function(req, res)
            res:json(config.editable())
        end)

        -- 保存配置：校验 → 持久化 → 应用回调（热键重绑等）
        app:post("/" .. PKG .. "/api/settings", function(req, res)
            local patch = req:json() or {}
            local ok, result, err = pcall(config.update, patch)
            if not ok or result == nil then
                return res:status(400):json({ err = err or "配置无效" })
            end
            if onSettingsApplied then
                pcall(onSettingsApplied, result)
            end
            res:json({ ok = true, settings = result })
        end)
    end
end

return api

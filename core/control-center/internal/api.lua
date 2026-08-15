--- ControlCenter.internal.api
--- HTTP API 层。把 sources 数据源与配置面板单例暴露成 RESTful 路由，
--- 挂到 HSUtil 共享 server（HSUtil.http.app，端口 8821，与 launcher/stayawake 等共用）。
--- 路由:
---   GET  /control-center/api/providers   提供者列表（name/icon/cards/pages，含 configUrl/searchUrl）
---   POST /control-center/api/open        打开配置面板（body { url } → panel.open(url)）
---   POST /control-center/api/close       隐藏配置面板（panel.hide）
---   静态 /control-center/view/*          聚合配置页前端（views/ 根）
---
--- 零侵入：不写 launcher 的 cfg/registry、不碰 HSUtil 内部；只追加路由与静态挂载。
local api = {}

local HSUtil = require("core.hsutil")
local app = HSUtil.http.app

local sources   -- sources 模块（scan/get）
local panel     -- panel 模块（open/hide/...）

--- 序列化提供者为 JSON 安全表：剔除非可序列化字段（function/table），
--- 保留 name/icon/cards（key/description/icon/kind/url）与 pages（name/icon/configUrl/searchUrl）。
--- @param p table sources 扫描出的提供者
--- @return table 纯 JSON 字段的提供者表
local function providerToJSON(p)
    local out = { name = p.name, cards = {}, pages = {} }
    if type(p.icon) == "string" and p.icon ~= "" then out.icon = p.icon end
    for _, c in ipairs(p.cards or {}) do
        local card = {}
        for k, v in pairs(c) do
            if type(v) ~= "function" and type(v) ~= "table" then card[k] = v end
        end
        out.cards[#out.cards + 1] = card
    end
    for _, pg in ipairs(p.pages or {}) do
        local page = {}
        for k, v in pairs(pg) do
            if type(v) ~= "function" and type(v) ~= "table" then page[k] = v end
        end
        out.pages[#out.pages + 1] = page
    end
    return out
end

--- 注册路由
--- @param sourcesMod table sources 模块（get() 返回提供者列表）
--- @param panelMod table panel 模块（open(url)/hide()）
--- @param viewsDir string|nil 前端视图目录（views/ 根，页面规范 views/pages/<page>/index.html）
function api.setup(sourcesMod, panelMod, viewsDir)
    sources = sourcesMod
    panel = panelMod

    -- 前端静态文件（views/ 根，挂 /control-center/view/*）
    if viewsDir then
        app:static("/control-center/view", viewsDir)
    end

    -- 提供者列表（聚合配置页卡片网格数据源）
    app:get("/control-center/api/providers", function(req, res)
        local ok, list = pcall(function() return sources.get() end)
        if not ok then
            return res:status(500):json({ err = tostring(list) })
        end
        local providers = {}
        for _, p in ipairs(list or {}) do
            providers[#providers + 1] = providerToJSON(p)
        end
        res:json({ providers = providers })
    end)

    -- 打开配置面板（url 缺失/非字符串 → 400；pcall 防 500）
    app:post("/control-center/api/open", function(req, res)
        local body = req:json()
        local url = body and body.url
        if type(url) ~= "string" or url == "" then
            return res:status(400):json({ err = "missing url" })
        end
        local ok, err = pcall(panel.open, url)
        if not ok then
            return res:status(500):json({ err = tostring(err) })
        end
        res:json({ ok = true })
    end)

    -- 关闭配置面板
    app:post("/control-center/api/close", function(req, res)
        local ok, err = pcall(panel.hide)
        if not ok then
            return res:status(500):json({ err = tostring(err) })
        end
        res:json({ ok = true })
    end)
end

return api

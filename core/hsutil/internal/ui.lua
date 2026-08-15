--- HSUtil.internal.ui
--- UI 资产注册表 + HTML 占位符展开 + 响应 transform。
--- 占位符语法（页面 index.html 中声明，可多行）：
---   <!-- hsutil:ui button,form,table use-crud -->
---   <!-- hsutil:fx glass -->
---   <!-- hsutil:icons -->
--- 服务端对 text/html 响应展开：vendor → base.css → 组件 css → tpl 内联 → 组件 js(defer, 拓扑序)。
local ui = {}

local assetsDir = nil
local BASE = "/hsutil/assets"

-- ===== 注册表 =====
-- 组件: name -> { js, css?, tpl?, deps = {组件名}, vendor = {"icons"} }
-- 路径相对 assets/ 根
local registry = {}

local function reg(name, entry)
    registry[name] = entry
end

reg("ui-button",       { js = "components/ui/ui-button/index.js",       css = "components/ui/ui-button/style.css",       tpl = "components/ui/ui-button/ui-button.tpl.html", deps = { "ui-icon" } })
reg("ui-icon",          { js = "components/ui/ui-icon/index.js",          css = "components/ui/ui-icon/style.css",          vendor = { "icons" } })
reg("ui-badge",        { js = "components/ui/ui-badge/index.js",        css = "components/ui/ui-badge/style.css" })
reg("ui-status-badge", { js = "components/ui/ui-status-badge/index.js", css = "components/ui/ui-status-badge/style.css" })
reg("ui-divider",      { js = "components/ui/ui-divider/index.js",      css = "components/ui/ui-divider/style.css" })
reg("ui-avatar",       { js = "components/ui/ui-avatar/index.js",       css = "components/ui/ui-avatar/style.css" })
reg("ui-empty",        { js = "components/ui/ui-empty/index.js",        css = "components/ui/ui-empty/style.css",        deps = { "ui-icon" } })
reg("ui-loading",      { js = "components/ui/ui-loading/index.js",      css = "components/ui/ui-loading/style.css" })
reg("ui-input",        { js = "components/ui/ui-input/index.js",        css = "components/ui/ui-input/style.css" })
reg("ui-hotkey",       { js = "components/ui/ui-hotkey/index.js",       css = "components/ui/ui-hotkey/style.css",       tpl = "components/ui/ui-hotkey/ui-hotkey.tpl.html" })
reg("ui-datetime",     { js = "components/ui/ui-datetime/index.js",     css = "components/ui/ui-datetime/style.css",     deps = { "ui-icon" }, vendor = { "flatpickr" } })
reg("ui-select",       { js = "components/ui/ui-select/index.js",       css = "components/ui/ui-select/style.css",       tpl = "components/ui/ui-select/ui-select.tpl.html", deps = { "ui-icon" } })
reg("ui-switch",       { js = "components/ui/ui-switch/index.js",       css = "components/ui/ui-switch/style.css" })
reg("ui-radio",        { js = "components/ui/ui-radio/index.js",        css = "components/ui/ui-radio/style.css" })
reg("ui-form-field",   { js = "components/ui/ui-form-field/index.js",   css = "components/ui/ui-form-field/style.css" })
reg("ui-form",         { js = "components/ui/ui-form/index.js",         css = "components/ui/ui-form/style.css",         tpl = "components/ui/ui-form/ui-form.tpl.html",
                         deps = { "ui-form-field", "ui-input", "ui-select", "ui-switch", "ui-radio" } })
reg("ui-modal",        { js = "components/ui/ui-modal/index.js",        css = "components/ui/ui-modal/style.css",        tpl = "components/ui/ui-modal/ui-modal.tpl.html", deps = { "ui-icon" }, js_pre = "utils/overlay.js" })
reg("ui-confirm",      { js = "components/ui/ui-confirm/index.js",      css = "components/ui/ui-confirm/style.css",      tpl = "components/ui/ui-confirm/ui-confirm.tpl.html",
                         deps = { "ui-modal", "ui-button" } })
reg("ui-toast",        { js = "components/ui/ui-toast/index.js",        css = "components/ui/ui-toast/style.css" })
reg("ui-drawer",       { js = "components/ui/ui-drawer/index.js",       css = "components/ui/ui-drawer/style.css",       tpl = "components/ui/ui-drawer/ui-drawer.tpl.html", deps = { "ui-icon" }, js_pre = "utils/overlay.js" })
reg("ui-tabs",         { js = "components/ui/ui-tabs/index.js",         css = "components/ui/ui-tabs/style.css",         tpl = "components/ui/ui-tabs/ui-tabs.tpl.html", deps = { "ui-icon" } })
reg("ui-table",        { js = "components/ui/ui-table/index.js",        css = "components/ui/ui-table/style.css",        tpl = "components/ui/ui-table/ui-table.tpl.html",
                         deps = { "ui-empty" } })
reg("ui-pagination",   { js = "components/ui/ui-pagination/index.js",   css = "components/ui/ui-pagination/style.css" })
reg("use-crud",        { js = "components/ui/use-crud/index.js",        deps = { "ui-confirm" } })

-- 特效: name -> { js, css?, vendor = {"anime"} }
local fx = {
    glass = { js = "effects/glass-fx/index.js", css = "effects/glass-fx/style.css", vendor = { "anime" } },
}

-- vendor 资产: name -> { css?, js? }
local vendor = {
    vue   = { js = "vendor/vue.global.prod.js" },
    anime = { js = { "vendor/anime.umd.min.js", "vendor/anime.compat.js" } },   -- compat 垫片：v4 命名空间 → v3 可调用函数
    icons = { js = "vendor/iconpark/iconpark.umd.min.js" },
    flatpickr = { js = { "vendor/flatpickr/flatpickr.min.js", "vendor/flatpickr/zh.js" }, css = "vendor/flatpickr/dark.css" },
}

local BASE_CSS = "styles/base.css"

-- ===== 工具 =====

local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

--- 初始化（由 init.lua 调用，传入 assets 目录绝对路径）
function ui.init(dir)
    assetsDir = dir
end

--- 拓扑排序（依赖在前）
--- 占位符用短名（button/form），注册表用全名（ui-button/ui-form）：
--- 先按原名查，查不到再试 "ui-" 前缀（use-crud 本身即全名，原名命中）。
local function topoOrder(names)
    local ordered, visited = {}, {}
    local function visit(n)
        -- 按解析后的键记账（短名 button → ui-button），避免同一组件经
        -- 别名 + 依赖两条路径重复入列（如 "ui icon,button" 中 icon 被声明和依赖各带一次）
        local key = registry[n] and n or ("ui-" .. n)
        if visited[key] then return end
        visited[key] = true
        local c = registry[key]
        if c then
            for _, d in ipairs(c.deps or {}) do visit(d) end
            table.insert(ordered, key)
        end
    end
    for _, n in ipairs(names) do visit(n) end
    return ordered
end

local function splitArgs(args)
    local names = {}
    for token in args:gmatch("[%w%-]+") do names[#names + 1] = token end
    return names
end

local function link(css)
    return '<link rel="stylesheet" href="' .. BASE .. "/" .. css .. '">'
end

local function script(js)
    return '<script src="' .. BASE .. "/" .. js .. '" defer></script>'
end

-- ===== 渲染 =====

local function renderComponents(names, seen)
    local parts = {}

    -- 1. vendor（按注册表顺序，去重）
    local function addVendor(name)
        local v = vendor[name]
        if not v or seen["v:" .. name] then return end
        seen["v:" .. name] = true
        if v.css then parts[#parts + 1] = link(v.css) end
        if v.js then
            if type(v.js) == "string" then v.js = { v.js } end
            for _, p in ipairs(v.js) do parts[#parts + 1] = script(p) end
        end
    end
    addVendor("vue")
    local ordered = topoOrder(names)
    for _, n in ipairs(ordered) do
        for _, vn in ipairs(registry[n].vendor or {}) do addVendor(vn) end
    end

    -- 2. theme.css（恒有：组件变量源）→ base.css（恒有）
    parts[#parts + 1] = link("styles/theme.css")
    parts[#parts + 1] = link(BASE_CSS)

    -- 3. 组件 css（拓扑序，去重）
    for _, n in ipairs(ordered) do
        local c = registry[n]
        if c.css and not seen["css:" .. c.css] then
            seen["css:" .. c.css] = true
            parts[#parts + 1] = link(c.css)
        end
    end

    -- 4. tpl 内联（读文件，内容为 <template id="tpl-ui-xxx">…</template>）
    for _, n in ipairs(ordered) do
        local c = registry[n]
        if c.tpl and assetsDir then
            local tpl = readFile(assetsDir .. "/" .. c.tpl)
            if tpl then parts[#parts + 1] = tpl end
        end
    end

    -- 5. js_pre（组件 js 的前置工具脚本，通用机制；去重）
    for _, n in ipairs(ordered) do
        local c = registry[n]
        if c.js_pre and not seen["pre:" .. c.js_pre] then
            seen["pre:" .. c.js_pre] = true
            parts[#parts + 1] = script(c.js_pre)
        end
    end

    -- 6. 组件 js（拓扑序，defer 保证执行顺序）
    for _, n in ipairs(ordered) do
        local c = registry[n]
        if c.js then parts[#parts + 1] = script(c.js) end
    end

    -- 7. 组件注册表（恒有：registerUiComponents + 全局变量暴露；去重）
    local REG_JS = "components/ui/index.js"
    if not seen["reg:" .. REG_JS] then
        seen["reg:" .. REG_JS] = true
        parts[#parts + 1] = script(REG_JS)
    end

    return table.concat(parts, "\n")
end

local function renderFx(names, seen)
    local parts = {}
    for _, n in ipairs(names) do
        local f = fx[n]
        if f then
            for _, vn in ipairs(f.vendor or {}) do
                local v = vendor[vn]
                if v and not seen["v:" .. vn] then
                    seen["v:" .. vn] = true
                    if v.css then parts[#parts + 1] = link(v.css) end
                    if v.js then
                        if type(v.js) == "string" then v.js = { v.js } end
                        for _, p in ipairs(v.js) do parts[#parts + 1] = script(p) end
                    end
                end
            end
            if f.css then parts[#parts + 1] = link(f.css) end
            if f.js then parts[#parts + 1] = script(f.js) end
        end
    end
    return table.concat(parts, "\n")
end

local function renderIcons(seen)
    -- 裸标签方式（<i data-iconpark="xxx">）：仅注入 IconPark 全局；
    -- 与 ui-icon 组件的 vendor 注入共享 seen["v:icons"]，双方式同页只注入一次
    if seen["v:icons"] then return "" end
    seen["v:icons"] = true
    return script("vendor/iconpark/iconpark.umd.min.js")
end

--- 按 kind + args 渲染标签片段（调试/外部复用：HSUtil.ui.tags("ui", {"button"})）
--- seen 为共享去重表：同一 expand 内多个占位符共用一个表，同名 vendor/tpl/js_pre 只注入一次。
function ui.tags(kind, names, seen)
    seen = seen or {}
    if kind == "ui" then return renderComponents(names, seen) end
    if kind == "fx" then return renderFx(names, seen) end
    if kind == "icons" then return renderIcons(seen) end
    return ""
end

--- 展开 HTML 中的占位符（单次展开共享一张去重表）
function ui.expand(html)
    local seen = {}
    local function repl(kind, args)
        return ui.tags(kind, splitArgs(args), seen)
    end
    -- 匹配 <!-- hsutil:ui button,form table --> 形态（args 内不出现 < 与 --）
    return (html:gsub("<!%-%-%s*hsutil:(%w+)%s+([^<]-)%s*%-%->", repl))
end

--- FNV-1a 64 位内容 hash（与 static.lua 同算法；展开后重算 ETag 用）
local function hashContent(s)
    local h = 0xcbf29ce484222325
    for i = 1, #s do
        h = (h ~ s:byte(i)) * 0x100000001b3
    end
    return h
end

--- 响应 transform（挂到 server:transform）：
--- 仅处理 text/html 且含占位符的响应。
--- 注意：static 中间件先按「未展开的原始文件」计算并设置了 ETag；展开会改变 body
--- （依赖注册表/组件文件状态），原始 ETag 随即失效。若不重算，webview 拿旧 ETag
--- 直接 304 缓存旧展开——组件注册表或依赖变化（改 ui.lua 后 reload）不生效。
--- 这里展开后基于展开结果重算 ETag：raw 内容不变 + 展开结果不变 → ETag 不变 → 304 仍命中；
--- 任一侧变化 → ETag 变化 → 200 拉新。语义与 raw ETag 完全一致且更正确。
function ui.transform()
    return function(body, headers)
        local ct = headers["Content-Type"] or ""
        if not ct:find("text/html") then return body, headers end
        if type(body) ~= "string" then return body, headers end
        if not body or not body:find("hsutil:") then return body, headers end
        local out = ui.expand(body)
        headers["ETag"] = string.format('"%x"', hashContent(out))
        return out, headers
    end
end

return ui

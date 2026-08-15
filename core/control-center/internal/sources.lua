--- ControlCenter.internal.sources
--- 只读数据源：扫描 Spoons/*.spoon/ 与 core/*/ 下的 launcher-commands.lua，
--- 复用 Spoon 统一接入协议（各 Spoon 根目录的 launcher-commands.lua）。
---
--- 目录发现方式（与 launcher 时代的 registry.scanCommandDirs 一致）：
---   * 遍历给定目录的一级子目录（dirs 默认 hs.configdir/Spoons + hs.configdir/core）
---   * hs.fs.dir 返回 (iteratorFn, dirUserdata) 两个值，dirUserdata 是 for 循环的 state——
---     必须直接 `for entry in hs.fs.dir(dir)`（先 pcall 取第一个返回值再迭代会丢掉
---     state，报 "directory metatable expected, got nil"，且被外层 pcall 吞掉）
---   * 每目录 pcall 防单目录失败
---
--- 只提取 manifest 的 name/cards/pages（含 config_pages 老字段兼容），页面 URL 按
--- 统一规则归一化（值不含 "/" 时推断为 /<modName>/view/pages/<值>/index.html）。
--- 绝不写任何模块的配置、不注册任何路由、不改任何既有文件（只读零侵入）。
---
--- 对外：
---   sources.scan()  -> [{ name, icon?, cards={key,description,icon,kind,url?}, pages={name,icon,configUrl?,searchUrl?} }]
---   sources.get()   -> 同上（缓存，未扫描过则首次扫描）
local sources = {}

local HSUtil = require("core.hsutil")
local logger = HSUtil.log.new("ControlCenter.sources")
local pathUtil = HSUtil.path

-- 扫描缓存（scan 重扫覆盖；get 读缓存）
local cache = nil

--- 页面 URL 简写推断（与 launcher registry.resolvePageUrl 一致）：
--- 值不含 "/" 视为页面目录名 → /<modName>/view/pages/<v>/index.html；
--- 以 "/" 开头视为完整 URL 原样使用
--- @param modName string 提供者名（URL 推断基准）
--- @param v string 页面目录名或完整 URL
--- @return string|nil 归一化 URL
local function resolvePageUrl(modName, v)
    if type(v) ~= "string" or v == "" then return nil end
    if v:find("/", 1, true) then return v end
    return "/" .. modName .. "/view/pages/" .. v .. "/index.html"
end

--- 归一化一个页面条目（对齐 launcher sanitizePage）
--- 只取 name/icon/configUrl/searchUrl；非法返回 nil
--- @param v table pages 或 config_pages 条目
--- @param modName string 提供者名
--- @return table|nil { name, icon?, configUrl?, searchUrl? }
local function extractPage(v, modName)
    if type(v) ~= "table" then return nil end
    if type(v.name) ~= "string" or v.name == "" then return nil end
    local out = { name = v.name }
    if type(v.icon) == "string" and v.icon ~= "" then out.icon = v.icon end
    local configV = v.config or v.url   -- url 为 config_pages 老字段，视为 config
    if configV then
        local url = resolvePageUrl(modName, configV)
        if not url then return nil end
        out.configUrl = url
    end
    if v.search then
        local url = resolvePageUrl(modName, v.search)
        if not url then return nil end
        out.searchUrl = url
    end
    if not out.configUrl and not out.searchUrl then return nil end
    return out
end

--- 归一化一张卡片（对齐 launcher sanitizeCard 的字段视角）
--- 只取 key/description/icon/kind/url；openurl/page 卡的 url 做简写推断。
--- 构建新表，绝不修改协议原表（只读）。
--- @param key string 卡片名（协议表 key）
--- @param c table 卡片定义
--- @param modName string 提供者名
--- @return table|nil { key, description?, icon?, kind?, url? }
local function extractCard(key, c, modName)
    if type(c) ~= "table" then return nil end
    local card = { key = key }
    if type(c.description) == "string" and c.description ~= "" then
        card.description = c.description
    end
    if type(c.icon) == "string" and c.icon ~= "" then card.icon = c.icon end
    if type(c.kind) == "string" and c.kind ~= "" then card.kind = c.kind end
    -- 仅 openurl/page 卡携带 url（page 卡与 pages 条目同规则推断）
    if (c.kind == "openurl" or c.kind == "page") and type(c.url) == "string" then
        local url = resolvePageUrl(modName, c.url)
        if not url then
            logger.wf("提供者 %s 的卡片 %s url 推断失败", modName, key)
            return nil
        end
        card.url = url
    end
    return card
end

--- 从一个 manifest 提取提供者数据（只读，不触碰 launcher 任何状态）
--- @param entry string 目录名（name 缺省时的提供者名）
--- @param mod table dofile 得到的 manifest
--- @return table { name, icon?, cards={...}, pages={...} }
local function extractProvider(entry, mod)
    local name = type(mod.name) == "string" and mod.name ~= "" and mod.name or entry
    local prov = { name = name, cards = {}, pages = {} }
    if type(mod.icon) == "string" and mod.icon ~= "" then prov.icon = mod.icon end

    -- cards：{key, description, icon, kind, url?}
    if type(mod.cards) == "table" then
        for k, c in pairs(mod.cards) do
            local card = extractCard(k, c, name)
            if card then prov.cards[#prov.cards + 1] = card
            else logger.wf("提供者 %s 的卡片 %s 被跳过", name, tostring(k)) end
        end
    end

    -- pages（统一页面注册表，新字段）
    if type(mod.pages) == "table" then
        for _, v in ipairs(mod.pages) do
            local page = extractPage(v, name)
            if page then prov.pages[#prov.pages + 1] = page
            else logger.wf("提供者 %s 的页面条目被跳过", name) end
        end
    end

    -- config_pages（老字段，兼容）：仅当 pages 未声明同名 config 时补充
    -- （对齐 launcher _mergeManifest：pages 已声明 configUrl → 跳过；
    --   同名存在但无 configUrl → 补 configUrl；否则新增）
    if type(mod.config_pages) == "table" then
        for _, v in ipairs(mod.config_pages) do
            local page = extractPage(v, name)
            if page then
                local existing
                for _, p in ipairs(prov.pages) do
                    if p.name == page.name then existing = p break end
                end
                if existing and existing.configUrl then
                    -- pages 已声明该配置页，跳过（不覆盖新字段）
                elseif existing then
                    existing.configUrl = page.configUrl
                else
                    prov.pages[#prov.pages + 1] = page
                end
            else
                logger.wf("提供者 %s 的配置页被跳过", name)
            end
        end
    end
    return prov
end

--- 扫描目录下的命令提供者（目录发现方式与 launcher scanCommandDirs 完全一致）
--- @param dirs table|nil 待扫描目录列表，默认 { hs.configdir/Spoons, hs.configdir/core }
--- @return table 提供者列表（同名去重覆盖：后扫描者胜；位置保留）
function sources.scan(dirs)
    dirs = dirs or {
        pathUtil.join(hs.configdir, "Spoons"),
        pathUtil.join(hs.configdir, "core"),
    }
    local list, index = {}, {}
    for _, dir in ipairs(dirs) do
        -- 注意：hs.fs.dir 返回 (iteratorFn, dirUserdata) 两个值，dirUserdata 是 for 循环的
        -- state——必须直接 for entry in hs.fs.dir(dir)（不能先 pcall 取第一个返回值再迭代，
        -- 那会丢掉 state 导致 "directory metatable expected, got nil"，且被外层 pcall 吞掉）。
        local ok = pcall(function()
            for entry in hs.fs.dir(dir) do
                if entry:sub(1, 1) ~= "." then
                    local sub = pathUtil.join(dir, entry)
                    local okDir, mode = pcall(hs.fs.attributes, sub, "mode")
                    local isDir = okDir and mode == "directory"
                    if isDir then
                        local cmdFile = pathUtil.join(sub, "launcher-commands.lua")
                        local okFile, fmode = pcall(hs.fs.attributes, cmdFile, "mode")
                        local exists = okFile and fmode ~= nil
                        if exists then
                            -- pcall(dofile, ...) 可能返回多值，用表收集避免只取第一个
                            local results = { pcall(dofile, cmdFile) }
                            local okLoad = table.remove(results, 1)
                            local mod = results[1]
                            if not okLoad then
                                logger.ef("提供者 %s 加载失败: %s", entry, tostring(mod))
                            elseif type(mod) ~= "table" then
                                logger.wf("提供者 %s 返回非 table 类型: %s", entry, type(mod))
                            else
                                local prov = extractProvider(entry, mod)
                                -- 同名 provider 去重覆盖（与 launcher 行为对齐：后扫描者胜）
                                if index[prov.name] then
                                    list[index[prov.name]] = prov
                                else
                                    index[prov.name] = #list + 1
                                    list[#list + 1] = prov
                                end
                            end
                        end
                    end
                end
            end
        end)
        if not ok then
            logger.wf("目录扫描失败 %s", tostring(dir))
        end
    end
    cache = list
    return list
end

--- 取扫描结果（缓存；未扫描过则首次扫描）
--- @return table 提供者列表
function sources.get()
    if not cache then sources.scan() end
    return cache
end

return sources

--- HSUtil.internal.http.static
--- 静态文件 serve 中间件。MIME + ETag + 目录穿越防护 + index.html 回退。
local fs = require("hs.fs")

local static = {}

local MIME = {
    html = "text/html; charset=utf-8",
    htm  = "text/html; charset=utf-8",
    css  = "text/css; charset=utf-8",
    js   = "application/javascript; charset=utf-8",
    json = "application/json; charset=utf-8",
    png  = "image/png",
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    gif  = "image/gif",
    svg  = "image/svg+xml",
    ico  = "image/x-icon",
    txt  = "text/plain; charset=utf-8",
    woff = "font/woff",
    woff2= "font/woff2",
}

local function mimeType(p)
    local ext = p:match("%.([%w]+)$")
    return (ext and MIME[ext:lower()]) or "application/octet-stream"
end

local function readFile(p)
    local f, err = io.open(p, "rb")
    if not f then return nil, err end
    local content = f:read("*a")
    f:close()
    return content
end

--- FNV-1a 64 位内容 hash（ETag 用；Lua 5.4 整数 64 位 wrap 乘法）
local function hashContent(s)
    local h = 0xcbf29ce484222325
    for i = 1, #s do
        h = (h ~ s:byte(i)) * 0x100000001b3
    end
    return h
end

--- 创建静态文件中间件
--- @param prefix string URL 前缀，如 "/app"
--- @param root string 本地目录
function static.serve(prefix, root)
    if root:sub(-1) == "/" then root = root:sub(1, -2) end
    if prefix:sub(-1) == "/" then prefix = prefix:sub(1, -2) end

    return function(req, res, next)
        if req.method ~= "GET" and req.method ~= "HEAD" then return next() end
        if req.path:sub(1, #prefix) ~= prefix then return next() end

        local rel = req.path:sub(#prefix + 1)
        if rel == "" or rel == "/" then rel = "/index.html" end

        -- 防目录穿越
        if rel:find("%.%.") then
            res:error(403, "forbidden")
            res:_markSent()
            return
        end

        local full = root .. rel
        local attrs = fs.attributes(full)
        if not attrs then return next() end

        local filePath = full
        if attrs.mode == "directory" then
            filePath = full .. "/index.html"
            attrs = fs.attributes(filePath)
            if not attrs then return next() end
        end

        local content, err = readFile(filePath)
        if not content then
            res:error(500, tostring(err))
            res:_markSent()
            return
        end

        -- ETag 基于内容 hash（FNV-1a 64 位）：mtime 秒级 + size 在「同秒改内容且大小
        -- 相同」时会碰撞 → webview 304 缓存命中旧代码（Tab 注入/Enter 等改动不生效事故）
        local etag = string.format('"%x"', hashContent(content))
        res._headers["Content-Type"] = mimeType(filePath)
        res._headers["ETag"] = etag
        -- 每次使用前验证（配合内容 hash ETag，保证改文件后立即生效）
        res._headers["Cache-Control"] = "no-cache"
        if req.headers["If-None-Match"] == etag then
            res:status(304):body("")
        else
            res:body(content)
        end
        res:_markSent()
    end
end

return static

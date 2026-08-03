--- HSUtil.internal.http.request
--- 请求对象。包装原生 (method,path,headers,body)。
local json = require("HSUtil.internal.json")

local Request = {}
Request.__index = Request

local function parseQuery(qs)
    local q = {}
    if not qs or qs == "" then return q end
    for k, v in qs:gmatch("([^&=]+)=?([^&]*)") do
        local function dec(s)
            s = s:gsub("%+", " ")
            return s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        end
        q[dec(k)] = dec(v or "")
    end
    return q
end

--- @param method string GET/POST/...
--- @param path string /api/x?y=1
--- @param headers table
--- @param body string
local function new(method, path, headers, body)
    local cleanPath, qs = path, ""
    local idx = path:find("?", 1, true)
    if idx then
        cleanPath = path:sub(1, idx - 1)
        qs = path:sub(idx + 1)
    end
    return setmetatable({
        method = method,
        path = cleanPath,
        rawPath = path,
        headers = headers or {},
        body = body or "",
        query = parseQuery(qs),
        params = {},
        _jsonCache = nil,
    }, Request)
end

--- 解析 body 为 JSON（缓存）
--- @return table|nil
function Request:json()
    if self._jsonCache ~= nil then return self._jsonCache end
    self._jsonCache = json.tryDecode(self.body, nil)
    return self._jsonCache
end

return { new = new }

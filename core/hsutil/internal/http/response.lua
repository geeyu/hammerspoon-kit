--- HSUtil.internal.http.response
--- 响应构造器。链式 API，最后由 server 取出 (body, code, headers)。
local json = require("HSUtil.internal.json")

local Response = {}
Response.__index = Response

local function new()
    return setmetatable({
        _body = "",
        _code = 200,
        _headers = { ["Content-Type"] = "text/plain; charset=utf-8" },
        _sent = false,
    }, Response)
end

function Response:status(code)
    self._code = tonumber(code) or 200
    return self
end

function Response:header(key, value)
    self._headers[key] = value
    return self
end

function Response:body(s)
    self._body = s or ""
    return self
end

function Response:text(s)
    self._body = s or ""
    self._headers["Content-Type"] = "text/plain; charset=utf-8"
    return self
end

function Response:html(s)
    self._body = s or ""
    self._headers["Content-Type"] = "text/html; charset=utf-8"
    return self
end

function Response:json(v)
    self._body = json.encode(v)
    self._headers["Content-Type"] = "application/json; charset=utf-8"
    return self
end

--- 错误响应（统一 JSON 形态）
function Response:error(code, msg)
    self._code = tonumber(code) or 500
    self._body = json.encode({ err = msg or "error" })
    self._headers["Content-Type"] = "application/json; charset=utf-8"
    return self
end

function Response:_markSent()
    self._sent = true
end

return { new = new }

--- HSUtil.internal.http.router
--- Express 风格路由。method+path 匹配，:param 提取，中间件链。
local request = require("HSUtil.internal.http.request")
local response = require("HSUtil.internal.http.response")

local router = {}

local METHODS = { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" }

local function compilePath(pattern)
    local params = {}
    local regex = pattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    regex = regex:gsub("(:[%w_]+)", function(p)
        table.insert(params, p:sub(2))
        return "([^/]+)"
    end)
    regex = "^" .. regex .. "$"
    return { regex = regex, params = params, source = pattern }
end

local function new()
    local r = {
        _routes = {},      -- method -> array of {compiled, handler}
        _middleware = {},  -- array of fn(req,res,next)
        _transforms = {},  -- array of fn(body, headers, req) -> body, headers
    }
    for _, m in ipairs(METHODS) do r._routes[m] = {} end

    local function add(method, pattern, handler)
        table.insert(r._routes[method], {
            compiled = compilePath(pattern),
            handler = handler,
        })
    end

    -- 小写方法名（get/post/...）链式注册
    for _, m in ipairs({ "get","post","put","delete","patch","head","options" }) do
        r[m] = function(self, pattern, handler)
            add(m:upper(), pattern, handler)
            return self
        end
    end

    function r:use(fn)
        table.insert(self._middleware, fn)
        return self
    end

    function r:transform(fn)
        table.insert(self._transforms, fn)
        return self
    end

    --- 分发请求 -> body, code, headers
    function r:dispatch(method, path, headers, body)
        method = (method or "GET"):upper()
        local req = request.new(method, path, headers, body)
        local res = response.new()

        local matched
        for _, route in ipairs(self._routes[method] or {}) do
            if req.path:match(route.compiled.regex) then
                local values = { req.path:match(route.compiled.regex) }
                for i, pname in ipairs(route.compiled.params) do
                    req.params[pname] = values[i]
                end
                matched = route
                break
            end
        end

        local mwIdx = 0
        local chain
        chain = function()
            mwIdx = mwIdx + 1
            local mw = self._middleware[mwIdx]
            if mw then
                mw(req, res, chain)
            elseif matched then
                local ok, err = pcall(matched.handler, req, res)
                if not ok then
                    res:error(500, tostring(err))
                end
                res:_markSent()
            else
                res:error(404, "not found")
                res:_markSent()
            end
        end
        chain()

        for _, tf in ipairs(self._transforms) do
            res._body, res._headers = tf(res._body, res._headers, req)
        end

        return res._body, res._code, res._headers
    end

    return r
end

router.new = new
return router

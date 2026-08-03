--- HSUtil.internal.http.cors
--- CORS 中间件。OPTIONS 预检返回 204，所有响应加跨源头。
local cors = {}

--- @param opts table|nil { origin=, methods=, headers= }
function cors.new(opts)
    opts = opts or {}
    local origin = opts.origin or "*"
    local methods = opts.methods or "GET,POST,PUT,DELETE,PATCH,OPTIONS"
    local headers = opts.headers or "Content-Type"

    return function(req, res, next)
        res._headers["Access-Control-Allow-Origin"] = origin
        res._headers["Access-Control-Allow-Methods"] = methods
        res._headers["Access-Control-Allow-Headers"] = headers
        if req.method == "OPTIONS" then
            res:status(204):body("")
            res:_markSent()
            return
        end
        next()
    end
end

return cors

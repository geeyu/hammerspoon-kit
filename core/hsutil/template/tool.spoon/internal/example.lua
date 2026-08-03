--- Tool.internal.example
--- 示例 API：GET /api/tool/hello -> {message}（经共享 server，路径带 /api 前缀避免与其他包冲突）
local example = {}

function example.register(HSUtil)
    HSUtil.http.app:get("/api/tool/hello", function(req, res)
        res:json({ message = "hello from Tool", time = os.time() })
    end)
    HSUtil.http.app:get("/api/tool/items", function(req, res)
        res:json({ items = {
            { id = 1, name = "示例 A", status = "success" },
            { id = 2, name = "示例 B", status = "warning" },
            { id = 3, name = "示例 C", status = "offline" },
        } })
    end)
end

return example

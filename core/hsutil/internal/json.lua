--- HSUtil.internal.json
--- JSON helper，薄封装 hs.json。
local json = {}
local raw = require("hs.json")

--- 编码（pretty 可选）
function json.encode(v, pretty)
    if pretty then
        return raw.encode(v, true)
    end
    return raw.encode(v)
end

--- 解码，失败返回 nil + err
function json.decode(s)
    local ok, v = pcall(raw.decode, s)
    if not ok then return nil, v end
    return v
end

--- 解码，失败返回 default（不抛错）
function json.tryDecode(s, default)
    local v, err = json.decode(s)
    if v == nil then return default, err end
    return v
end

return json

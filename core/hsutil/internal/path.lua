--- HSUtil.internal.path
--- 路径工具。
local path = {}

local HOME = os.getenv("HOME") or "."

--- HSUtil 数据根目录（~/.hammerspoon/data/）
--- 统一收在仓库 data/ 下，避免在 HOME 散落 ~/.hsutil 之类目录。
function path.dataDir()
    return HOME .. "/.hammerspoon/data"
end

--- 缓存目录（~/.hammerspoon/data/cache/）
function path.cacheDir()
    return path.dataDir() .. "/cache"
end

--- 确保目录存在（递归 mkdir）
--- @param p string 目录路径
function path.ensureDir(p)
    if not p or p == "" then return end
    os.execute('mkdir -p "' .. p .. '"')
end

--- 路径拼接（去重斜杠）
function path.join(a, b)
    if not a or a == "" then return b or "" end
    if not b or b == "" then return a end
    if a:sub(-1) == "/" then a = a:sub(1, -2) end
    if b:sub(1, 1) == "/" then b = b:sub(2) end
    return a .. "/" .. b
end

return path

--- StayAwake.internal.settings
--- 配置持久化：~/.hammerspoon/data/StayAwake/settings.json
--- 内容：{ mode = "system" | "all" }（system=允许息屏，all=屏幕常亮）
--- json 依赖注入（默认 hs.json），便于纯逻辑测试。
local M = {}

local function defaultJson()
    return require("hs.json")
end

--- 读取配置。文件缺失/损坏 → 回退默认 { mode = "system" }
--- mode 非法归一化；bannerPos 合法时透传（banner 拖动位置持久化）
--- @param filePath string JSON 文件路径
--- @param json table|nil 注入 {encode, decode}
function M.load(filePath, json)
    json = json or defaultJson()
    local f = io.open(filePath, "r")
    if not f then return { mode = "system" } end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(json.decode, content)
    if not ok or type(data) ~= "table" then
        return { mode = "system" }
    end
    local out = { mode = (data.mode == "all") and "all" or "system" }
    if type(data.bannerPos) == "table"
        and type(data.bannerPos.x) == "number"
        and type(data.bannerPos.y) == "number" then
        out.bannerPos = { x = data.bannerPos.x, y = data.bannerPos.y }
    end
    return out
end

--- 保存配置（自动建目录）。成功返回 true
--- @param filePath string JSON 文件路径
--- @param data table {mode=...}
--- @param json table|nil 注入
function M.save(filePath, data, json)
    json = json or defaultJson()
    local dir = filePath:match("^(.*)/[^/]+$")
    if dir then os.execute('mkdir -p "' .. dir .. '"') end
    local ok, content = pcall(json.encode, data)
    if not ok then return false end
    local f = io.open(filePath, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

return M

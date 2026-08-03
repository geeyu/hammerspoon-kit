--- === Tool ===
--- 模板 Spoon：HSUtil 共享 UI 资产 + 多页面 webview。
--- 复制本目录改名为 <你的包>.spoon，全局替换 "Tool"/"tool" 为你的包名。
local Tool = {}

-- 版本与描述（meta.json 已废弃，身份信息在此）
Tool.VERSION = "0.1.0"
Tool.DESCRIPTION = "我的工具：HSUtil UI 快速开发模板"

if not Tool.spoonPath then
    local src = debug.getinfo(1, "S").source:sub(2)
    Tool.spoonPath = src:match("^(.*)/init%.lua$") or src:match("^(.*)/[^/]+$")
end

local HSUtil = hs.loadSpoon("HSUtil")
if not HSUtil or not HSUtil.http then
    hs.alert.show("Tool: HSUtil 未加载（先加载 core/hsutil）")
    return Tool
end

local viewsDir = Tool.spoonPath .. "/views"

-- 共享 HTTP server 上注册本包静态路由（/tool/assets/*）
HSUtil.http.app:static("/tool/assets", viewsDir)

-- ===== Webview 面板 =====
local panel = nil

local function openPage(name)
    -- 多页面导航：webview 切到 views/pages/<name>/index.html
    local url = HSUtil.http.BASE .. "/tool/assets/pages/" .. name .. "/index.html"
    if panel then
        panel:url(url)
        if not panel:isVisible() then panel:show() end
    end
end

local function showPanel()
    if not panel then
        panel = hs.webview.newBrowser({ x = 0, y = 0, w = 560, h = 640 }, {
            developerExtras = true,
        })
        panel:windowStyle({ "titled", "closable", "resizable", "utility" })
        panel:windowTitle("Tool")
        panel:allowGestures(true)
    end
    openPage("home")
    panel:show()
end

function Tool.toggle()
    if panel and panel:isVisible() then
        panel:hide()
    else
        showPanel()
    end
end

--- 打开指定页面（供热键/命令调用）
function Tool.open(name)
    openPage(name)
    if panel then panel:show() end
end

-- ===== 示例 API 路由（internal/example.lua 注册）=====
require("Tool.internal.example").register(HSUtil)

-- ===== 热键：Ctrl+Shift+T 呼出 =====
Tool.hotkey = hs.hotkey.bind({ "ctrl", "shift" }, "T", Tool.toggle)

return Tool

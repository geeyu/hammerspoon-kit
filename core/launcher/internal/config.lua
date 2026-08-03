--- Launcher.internal.config
--- 配置单点。所有可调项集中，供 init/registry/api/panel 使用。
local HS_HOME = require("core.hsutil")
local http = HS_HOME.http
local pathUtil = HS_HOME.path

-- 定位本 spoon 根目录（优先用 hs.configdir，跨加载方式可靠；
-- 不依赖 debug.getinfo 在 dofile 链里的 source 推导——那在部分环境下会返回空/相对路径）
local function spoon_root()
    if type(hs.configdir) == "string" and hs.configdir ~= "" then
        return hs.configdir .. "/core/launcher/"
    end
    -- 兜底：仍然能从自己文件的绝对 source 推导
    local str = debug.getinfo(1, "S").source:sub(2)
    local dir = str:match("(.*)[/\\]") or ""
    return dir:match("(.*)[/\\]internal[/\\]") or dir
end
local ROOT = spoon_root()

return {
    -- 呼出热键（Option+Space；Cmd+Space 被 macOS 系统层占用 -9878，退回 Option）
    hotkey_show = { "alt", "space" },
    -- 包名前缀（HTTP 路由 + 静态挂载隔离）
    pkg = "launcher",
    -- 资源前缀
    base_url = http.BASE .. "/launcher",
    -- 前端视图目录（views/pages/<page>/ 规范）
    views_dir = HS_HOME.path.join(ROOT, "views"),
    -- 数据目录（默认走 HSUtil 数据目录：~/.hammerspoon/data/launcher）
    data_dir = HS_HOME.path.join(HS_HOME.path.dataDir(), "launcher"),
    -- 面板尺寸（对齐 Clipboard：屏幕 52% 宽 × 62% 高，垂直 22% 处）
    panel = { widthRatio = 0.52, heightRatio = 0.62, yRatio = 0.22 },
    -- 前端查询节流（毫秒）
    debounce_ms = 100,
    -- 启用的源（对应 sources.lua 里的源名）
    enabled_sources = { "apps", "calc", "screencapture", "urlformats", "useractions", "custom", "cards" },
    -- urlformats 的 providers（用户按需填）：{ key = { name="", url="https://…%s" } }
    url_providers = {},
    -- useractions 的 actions（含 keyword/fn/url/description/hotkey）：{ ["名称"] = {…} }
    user_actions = {},
    -- 自定义命令扩展点（未来挂 pi agent / siyuan-cli 等）
    -- 每项: { keyword="proj", title="打开项目", kind="shell",
    --        exec={ "/usr/bin/open", { "-R", "$HOME/Projects" } } }  -- argv 内 "${query}" 会被替换
    custom_commands = {},

    -- 功能卡片（常驻动作，可自建）：{ ["名称"] = { description, kind, ... } }
    --   kind=shell      exec={cmd, {argv}}，argv 内 "${query}" 替换
    --   kind=openurl    url="https://...${query}"，裸启动
    --   kind=screen     截屏卡片：sub={ kind=interactive|fullscreen|clipboard|menu, postUI=true }
    --   kind=page       url="/<pkg>/view/..."，面板内 iframe 打开任意 spoon 的 view（子页面协议）
    --   kind=runFunction fn=function(cfg)，cfg 为配置表单值（见 README「Spoon 接入协议」）
    cards = {
        -- 示例（可按需开启）：
        -- ["全屏截图"]         = { description="整屏截屏到桌面", kind="screen", sub={ kind="fullscreen" } },
        -- ["选区截图"]         = { description="交互式选区截屏", kind="screen", sub={ kind="interactive", postUI=true } },
    },
}

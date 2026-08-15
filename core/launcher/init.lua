--- === Launcher ===
---
--- Raycast 式启动中枢（替代 Seal 的可插拔启动器）。
--- 参考 Clipboard 分层重构：init 装配 + config/api/panel/registry/runner。
--- 能力：应用启动/聚焦、kill、reveal、计算器、屏幕截图、URL/搜索格式、剪贴板书签、
---       以及可扩展的自定义命令（config.custom_commands，未来可挂 pi agent / siyuan-cli 等）。
---
--- 使用（框架层）：
---   local launcher = require("core.launcher")
---   launcher:start()
---
--- 快捷键：Option+Space 呼出（Raycast 式居中输入框）
--- ============================================================

local obj = {}

obj.name = "Launcher"
obj.version = "1.0.0"
obj.author = "geeyu"
obj.homepage = "https://github.com/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- 定位本 spoon 目录
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[/\\])") or ""
end
local spoonPath = script_path()
local loadMod = function(n) return dofile(spoonPath .. "internal/" .. n) end

-- 加载各层
local config  = loadMod("config.lua")
local registry = loadMod("registry.lua")
local api     = loadMod("api.lua")
local panel   = loadMod("panel.lua")

local HSUtil = require("core.hsutil")

obj.config = config
obj.logger = HSUtil.log.new("Launcher")

-- 运行期状态
obj.hotkeyToggle = nil

--- 显示面板
function obj:show()
    panel.show()
    return self
end

--- 切换（可见时隐藏，隐藏时呼出）
function obj:toggle()
    if panel.visible() then
        panel.hide()
    else
        panel.show()
    end
    return self
end

--- Launcher:query(text)
--- Method：程序化查询候选（供调试/其它模块调用）。
function obj:query(text)
    return registry.query(text)
end

--- Launcher:registerCommands(name, manifest)
--- Method：运行时注册命令提供者（Spoon 接入协议，见 README「Spoon 接入协议」）。
--- manifest: { name=, cards={...}, custom_commands={...}, user_actions={...} }
--- start() 前/后均可调用；重复注册同名提供者按 key 覆盖。
function obj:registerCommands(name, manifest)
    if registry and registry.registerProvider then
        registry.registerProvider(name, manifest)
    end
    return self
end

--- Launcher:start()
--- Method：初始化 registry + 注册 API + 绑定热键。
function obj:start()
    -- 初始化 registry（含 runner 注入 + 源激活 + custom 命令）
    registry.setup(obj.config)
    obj.registry = registry

    -- 初始化面板（webview 尺寸 / URL）
    panel.setup(obj.config)

    -- 注册 HTTP 路由 + 前端静态；注入关闭面板回调
    -- 前端视图目录用 init 的 script_path() 定位（与 Clipboard 一致，可可靠解析到本 spoon 目录），
    -- 不走 config 里基于 debug.getinfo 二次推导的 views_dir（在部分加载方式下会推导成空路径导致静态 404）
    api.setup(registry, obj.config.pkg, spoonPath .. "views", function() panel.hide() end)

    -- 热键（Option+Space）
    if not self.hotkeyToggle then
        self.hotkeyToggle = hs.hotkey.new(config.hotkey_show[1], config.hotkey_show[2], function()
            if panel.visible() then panel.hide() else panel.show() end
        end)
    end
    self.hotkeyToggle:enable()

    obj.logger.f("Launcher 已启动（Option+Space 呼出，源: %s）",
        table.concat(config.enabled_sources, ","))
    return self
end

--- Launcher:stop()
--- Method：停用热键 + 清理面板与 registry 资源。
function obj:stop()
    if self.hotkeyToggle then self.hotkeyToggle:disable() end
    panel.teardown()
    if registry.stop then pcall(function() registry.stop() end) end
    return self
end

return obj

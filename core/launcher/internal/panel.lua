--- Launcher.internal.panel
--- 表现层：基于 HSUtil.webview 的面板生命周期。
--- 创建/失焦隐藏/Esc 兜底/加载保护由 HSUtil.webview 承担（三 Spoon 共用），
--- 本层只配置 Launcher 特有参数：尺寸（config.panel）、每次 show 时 reset 输入框。
local panel = {}

local cfg
local HSUtil = require("core.hsutil")
local logger = HSUtil.log.new("Launcher.panel")
local view = nil

--- @param config table 配置单点（需 base_url、panel.widthRatio/heightRatio/yRatio）
function panel.setup(config)
    cfg = config
    -- 尺寸对齐 Clipboard：按主屏比例计算（52% 宽 × 62% 高）
    local scr = hs.screen.mainScreen():frame()
    local p = cfg.panel or {}
    view = HSUtil.webview.new({
        url = config.base_url .. "/view/pages/launcher/index.html",
        width = math.floor(scr.w * (p.widthRatio or 0.52)),
        height = math.floor(scr.h * (p.heightRatio or 0.62)),
        yRatio = p.yRatio or 0.22,
        -- Launcher 模式：每次 show 清空上次输入并聚焦（首次由 didFinishNavigation 处理）
        resetJs = [[window.__launcherReset && window.__launcherReset();]],
        resetOnShow = true,
        logger = logger,
        -- 启动器加载失败只记日志，不弹窗打断（保持原行为）
        onLoadFail = function(action, err)
            logger.e("webview 加载失败: %s %s", action, tostring(err))
        end,
    })
end

function panel.show()
    return view ~= nil and view:show() or false
end

function panel.hide()
    if view then view:hide() end
end

function panel.visible()
    return view ~= nil and view:visible() or false
end

function panel.teardown()
    if view then view:teardown() end
end

return panel

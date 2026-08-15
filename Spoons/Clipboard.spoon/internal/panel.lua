--- Clipboard.internal.panel
--- 表现层：基于 HSUtil.webview 的面板生命周期。
--- 创建/失焦隐藏/Esc 兜底/加载保护全部由 HSUtil.webview 承担（三 Spoon 共用），
--- 本层只配置 CH 特有参数：URL、尺寸（config.panel 屏幕比例）、
--- 跟随鼠标所在屏幕呼出、隐藏时刷新策略。
local panel = {}

local HSUtil = require("core.hsutil")
local view = nil

--- @param config table 配置单点（需 pkg、panel 字段）
function panel.setup(config)
    local p = config.panel or {}
    view = HSUtil.webview.new({
        url = HSUtil.http.BASE .. "/" .. config.pkg .. "/view/pages/history/index.html",
        -- 比例尺寸：按目标屏幕（鼠标所在屏）frame 计算，副屏/竖屏自动适配不越界
        widthRatio = p.widthRatio or 0.52,
        heightRatio = p.heightRatio or 0.62,
        yRatio = p.yRatio or 0.22,
        -- 跨屏粘贴场景：面板跟随鼠标所在屏幕（Raycast/Alfred 习惯），
        -- 副屏工作时不用移鼠标回主屏点选；退化主屏
        screenFor = function()
            return hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
        end,
        -- 每次呼出重定位：屏幕布局变化（拔外接屏/改分辨率）后面板不悬空
        repositionOnShow = true,
        -- CH 模式：隐藏时刷新前端（下次展示即最新），show 不刷新
        resetJs = "QW.reload && QW.reload()",
        resetOnShow = false,
        logger = hs.logger.new("Clipboard.panel", "info"),
        onTimeout = function()
            hs.alert.show("面板加载超时，请重试")
        end,
        onLoadFail = function()
            hs.alert.show("剪贴板面板加载失败，请重试")
        end,
    })
end

--- 设置保存后应用面板尺寸（config.panel 变化 → 即时 resize；webview 未创建则下次 show 生效）
--- @param p table {widthRatio=, heightRatio=, yRatio=}
function panel.applySettings(p)
    if view and p then
        view:resize({
            widthRatio = p.widthRatio,
            heightRatio = p.heightRatio,
            yRatio = p.yRatio,
        })
    end
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

--- 面板是否已初始化（show() 懒初始化判断用）
function panel.ready()
    return view ~= nil
end

--- 数据变更回调（watcher.onChange 触发）：隐藏态下静默刷新，下次展示即最新
function panel.onDataChanged()
    if view and not panel.visible() then view:reset() end
end

function panel.teardown()
    if view then view:teardown() end
end

return panel

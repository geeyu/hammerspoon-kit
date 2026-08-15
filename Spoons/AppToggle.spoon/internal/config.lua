--- AppToggle.internal.config
--- 配置单点：默认值 + settings 表覆盖（全局项）。
--- 面板/布局不做配置项——布局由 toggle 引擎按屏自动锁定（管理页可查看/清除）。
local HSUtil = require("core.hsutil")

local defaults = {
    -- 包名（HTTP 路由前缀：/apptoggle/api/*、/apptoggle/view/*）
    pkg = "apptoggle",
    -- 数据目录
    data_dir = HSUtil.path.dataDir() .. "/apptoggle",
    -- 默认热键（新添加应用时预填，可改）
    default_mods = { "ctrl", "alt" },
    default_key = "t",
}

local config = {}
for k, v in pairs(defaults) do config[k] = v end

return config

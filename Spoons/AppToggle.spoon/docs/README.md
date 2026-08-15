# AppToggle.spoon

任意应用一键显隐（全局热键 + 布局锁定），带管理页面。
引擎移植自 `core/app-toggle.lua`（Ghostty 场景打磨），封装为独立 Spoon：

- 每个应用一个全局热键：呼出 / 隐藏切换
- 布局锁定：手动调整好窗口后按热键隐藏即记录该屏布局并持久化，呼出时还原
- 跨屏呼出自动移动窗口；全屏 Space 上呼出 → 全屏形态接管
- 隐藏后焦点还原给呼出前的应用；120ms 防抖防连按

## 使用

```lua
hs.loadSpoon("AppToggle"):start()
```

管理页面（应用增删改 / 热键录制 / 测试 / 布局管理）：

1. Launcher → "应用显隐" 卡片
2. 或直调 `hs.loadSpoon("AppToggle"):showManager()`

## 管理页功能

| 区块 | 功能 |
| ------ | ------ |
| 应用列表 | 名称 / Bundle ID / 热键 / 运行状态（运行中·已隐藏·未运行） |
| 添加/编辑 | 名称 + Bundle ID + 热键录制（remote 吞键模式）+ 选项 |
| 选项 | 未运行时行为（启动 / 仅激活）、全屏接管、还原焦点、跟随鼠标屏 |
| 测试 | 触发一次显隐（与热键同一逻辑） |
| 布局 | 每应用显示已锁定布局的屏幕数，可一键清除全部 |

## 配置存储

SQLite（`~/.hammerspoon/data/apptoggle/apptoggle.db`）：

- `apps` 表：应用绑定（bundle_id 唯一，upsert）
- `settings` 表：按屏锁定布局（`layouts.<bundleID>` → JSON）

## 编程式添加

```lua
local at = hs.loadSpoon("AppToggle")
at:start()
at:bindApp({
  name = "Ghostty",
  bundle_id = "com.mitchellh.ghostty",
  mods = { "ctrl", "alt" },
  key = "t",
  on_no_window = "launch",
})
```

## 热键语义（以 Ghostty 为例）

- 应用已隐藏 → 呼出：按鼠标所在屏的锁定布局显示并聚焦
- 窗口在当前桌面 → 隐藏（焦点还给呼出前的应用）
- 同屏别的桌面 → 呼到当前桌面
- 另一块屏可见 → 隐藏（再按一次即在鼠标屏呼出）
- 目标空间是别的应用的全屏 → 全屏形态接管（再按退出全屏并隐藏）
- 应用未运行/无窗口 → 按选项处理（默认启动）

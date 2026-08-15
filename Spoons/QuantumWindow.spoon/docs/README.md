# QuantumWindow.spoon

窗口管理工具：分屏 / 相邻 Space / 跨显示器 / 铺满 / 居中，所有操作带屏幕中央 HUD 反馈。

## 使用

```lua
-- ~/.hammerspoon/init.lua
local qw = hs.loadSpoon("QuantumWindow")
qw:start()
```

## 功能与默认热键

| 功能 | 默认热键 | 说明 |
| ------ | ---------- | ------ |
| 左/右/上/下半屏 | `Ctrl+Opt+Cmd+←/→/↑/↓` | 当前窗口按方向半屏摆放 |
| 移到上一个/下一个 Space | `Ctrl+Cmd+←/→` | 基于内置 hs.spaces |
| 移到上方/下方显示器 | `Ctrl+Cmd+↑/↓` | 多显示器场景 |
| 铺满 | `Ctrl+Opt+Cmd+M` | 当前 Space 内铺满可用区域，再次按还原 |
| 居中 | `Ctrl+Opt+Cmd+C` | 按绝对尺寸居中（默认 800×600） |

所有操作执行时屏幕中央弹出 **HUD**（显示按键 + 动作名，如 `⌃⌥⌘→ 右半屏`），约 1 秒后消失。

## 配置（internal/config.lua）

```lua
config.enabled = { split = true, spaces = true, fullscreen = true, center = true }
config.center  = { hotkey = { { "ctrl", "alt", "cmd" }, "C" }, width = 800, height = 600 }
```

- 单独关闭某模块：`qw.config.enabled.center = false`（start 之前设置）
- 自定义热键：`qw:bindHotkeys({ left_half = { "cmd", "Left" } })`，未指定的沿用默认
- 热键格式：`{ { 修饰键表 }, 键名 }`

## 架构

- `init.lua`（装配/API）→ `internal/`：`window.lua`（窗口工具）、`split.lua`、`spaces.lua`、
  `fullscreen.lua`、`center.lua`、`notify.lua`（HUD）、`api.lua`（HTTP 路由）、`config.lua`
- 零第三方依赖；`hs.window.animationDuration = 0` 消除窗口动画延迟
- 控制中心集成：`launcher-commands.lua` 提供「窗口管理」配置页入口（菜单栏 🛠 → 控制中心）

## 测试

```bash
hs -c "dofile('$HOME/.hammerspoon/Spoons/QuantumWindow.spoon/test/run.lua')"
```

## 已知限制

- Space 移动基于 macOS 私有 API（hs.spaces），切换时有系统层面的视觉过渡
- `Ctrl+Cmd+方向键` 若无效，检查「系统设置 → 键盘快捷键 → 调度中心」是否占用

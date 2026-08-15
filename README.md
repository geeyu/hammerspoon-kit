# Hammerspoon Kit

> 基于 [Hammerspoon](https://www.hammerspoon.org/) 的开源 macOS 桌面工具包：
> **窗口管理 · 剪贴板历史 · 防睡眠**，外加一个 Raycast 式命令中枢（Launcher）。

由个人配置沉淀而来，遵循 Spoon 生态规范，克隆即用。

## ✨ 功能一览

| 分类 | 说明 | 所属包 |
| ------ | ------ | -------- |
| 🪟 分屏 | 一屏四向半屏摆放 | QuantumWindow |
| 🔀 相邻 Space | 快速把窗口移到上/下一个虚拟桌面 | QuantumWindow |
| 🖥️ 跨显示器 | 把窗口移到上/下方显示器 | QuantumWindow |
| 🧱 铺满 | 当前 Space 内铺满屏幕可用区域（可还原） | QuantumWindow |
| 🎯 居中 | 按绝对尺寸居中显示 | QuantumWindow |
| 📋 剪贴板历史 | 记录复制内容，弹出面板回选粘贴（SQLite 持久化 + 模糊搜索） | Clipboard |
| 🌙 防睡眠 | 菜单栏防睡眠：永久 / 1-24 小时 / 5-90 分钟 / 直到指定时间（允许息屏或屏幕常亮） | StayAwake |
| 🔄 应用显隐 | 任意应用一键显隐（全局热键 + 按屏布局锁定 + 全屏接管，带管理页） | AppToggle |
| 🖼️ Bing 壁纸 | Bing 每日壁纸（自动轮询 + 一键应用/随机 + 历史浏览 + 下载记录） | BingDaily |
| 🚀 启动器 | Option+Space 命令中枢（启动应用/计算器/截屏/URL/书签，支持自定义命令，自动发现各 Spoon 功能卡片） | Launcher |

## ⌨️ 快捷键速查表

| 快捷键 | 动作 |
| -------- | ------ |
| `Ctrl` + `Opt` + `Cmd` + `←` | 左半屏 |
| `Ctrl` + `Opt` + `Cmd` + `→` | 右半屏 |
| `Ctrl` + `Opt` + `Cmd` + `↑` | 上半屏 |
| `Ctrl` + `Opt` + `Cmd` + `↓` | 下半屏 |
| `Ctrl` + `Cmd` + `←` | 窗口移到上一个 Space |
| `Ctrl` + `Cmd` + `→` | 窗口移到下一个 Space |
| `Ctrl` + `Cmd` + `↑` | 移到上方显示器 |
| `Ctrl` + `Cmd` + `↓` | 移到下方显示器 |
| `Ctrl` + `Opt` + `Cmd` + `M` | 当前 Space 内**铺满**（再次按还原原尺寸） |
| `Ctrl` + `Opt` + `Cmd` + `C` | **居中** + 绝对尺寸（默认 800×600，可配） |
| `Ctrl` + `V` | **剪贴板历史**面板（输入即搜索；**→/←** 开启/取消右侧预览；Enter 粘贴，Esc 关） |
| `Option` + `Space` | **Launcher** 命令中枢（应用/计算器/截屏/URL/书签/自定义命令 + 各 Spoon 功能卡片） |
| `Cmd` + `Opt` + `Ctrl` + `R` | 重载 Hammerspoon 配置 |

> QuantumWindow 各窗口操作执行时会在屏幕中央弹出 **HUD**，同时显示「按键 + 动作」，如 `⌃⌥⌘→ 右半屏`。
> 按键说明：`Opt` = Option / ⌥，`Cmd` = Command / ⌘。

## 🚀 安装

### 前置要求

1. 安装 [Hammerspoon](https://www.hammerspoon.org/)
2. 授权：`系统设置 → 隐私与安全性 → 辅助功能` → 勾选 **Hammerspoon**

### 方式一：直接使用（推荐）

```bash
git clone <本仓库地址> ~/.hammerspoon
```

重启 Hammerspoon（或菜单栏图标 → Reload Config）即开即用。

### 方式二：自定义安装位置

```bash
git clone <本仓库地址> ~/path/to/hammerspoon-kit
ln -s ~/path/to/hammerspoon-kit/init.lua ~/.hammerspoon/init.lua
ln -s ~/path/to/hammerspoon-kit/core ~/.hammerspoon/core
ln -s ~/path/to/hammerspoon-kit/Spoons ~/.hammerspoon/Spoons
```

> 说明：Hammerspoon 固定读取 `~/.hammerspoon/`，符号链接可让仓库留在任意位置并保持可 `git pull` 更新。

## 🧪 运行测试

| 测试 | 命令 | 环境 |
| ------ | ------ | ------ |
| Launcher 单元测试 | `lua5.4 core/launcher/test/unit_test.lua` | 纯 Lua，无需 Hammerspoon |
| QuantumWindow | `hs -c "dofile('$HOME/.hammerspoon/Spoons/QuantumWindow.spoon/test/run.lua')"` | Hammerspoon 运行中 |
| StayAwake | `hs -c "dofile('$HOME/.hammerspoon/Spoons/StayAwake.spoon/test/run.lua')"` | Hammerspoon 运行中 |
| Clipboard 前端（历史面板） | `node Spoons/Clipboard.spoon/test/headless-panel-test.js` | 需 Microsoft Edge |
| Clipboard 前端（设置页） | `node Spoons/Clipboard.spoon/test/settings-panel-test.js` | 需 Microsoft Edge |

## 📁 目录结构

```
hammerspoon-kit/
├── init.lua                  # 入口：加载核心框架与三个 Spoon
├── core/
│   ├── hsutil/               # 核心框架：HTTP 网关 + SQLite ORM + webview + UI 组件库 + Spoon 脚手架模板
│   └── launcher/             # 命令中枢（Option+Space，Vue3 面板）
├── Spoons/
│   ├── QuantumWindow.spoon/  # 窗口管理（init.lua + internal/ 分层 + launcher-commands.lua）
│   ├── Clipboard.spoon/      # 剪贴板历史（SQLite + chooser 面板 + webview 预览）
│   ├── StayAwake.spoon/      # 防睡眠（菜单栏入口 + 倒计时横幅）
│   ├── AppToggle.spoon/      # 应用一键显隐（全局热键 + 布局锁定 + 管理页）
│   └── BingDaily.spoon/      # Bing 每日壁纸（轮询 + 一键执行 + 归档浏览）
├── docs/
│   ├── quickstart.md         # 五分钟上手
│   └── development.md        # 二次开发指南
├── LICENSE                   # MIT
└── .gitignore
```

## 🧩 架构说明

- **Spoon 封装**：功能全部收敛进 `Spoons/*.spoon/`，根目录只留装载入口，便于分发与跨机复用。
- **核心框架（core/hsutil）**：共享 HTTP 网关（各 Spoon 通过 `HS.http.app` 挂路由）、SQLite ORM、webview 面板工具与 Vue3 UI 组件库；`core/hsutil/template/tool.spoon` 提供新 Spoon 脚手架。
- **命令中枢（core/launcher）**：与 Spoon 通过 `launcher-commands.lua` 协议解耦——任何 Spoon 放一个 `launcher-commands.lua` 即可向 Launcher 提供功能卡片/命令，无需改动 Launcher 本体。
- **零第三方依赖**：不依赖任何第三方 spoon；Space 操作基于内置 `hs.spaces`。

## 📦 数据与配置

- 剪贴板数据：`~/.clips/`（history.db + images/，默认保留近 7 天自动清理）
- 各 Spoon 运行时配置：`~/.hammerspoon/data/`（不入库）

## ⚠️ 常见问题

- **快捷键无效**：检查 `系统设置 → 键盘 → 键盘快捷键 → 调度中心` 是否占用了 `Ctrl+Cmd+方向键`。
- **Space 切换有视觉过渡**：`hs.spaces.moveWindowToSpace` 基于 macOS 私有 API，过渡动画属系统层面行为。
- **剪贴板不记录**：确认 Hammerspoon 已获「辅助功能」授权。
- **BingDaily 默认不启用**：默认不下载/更换壁纸；取消 `init.lua` 中对应注释即可启用。

## 📄 开源协议

[MIT](LICENSE) © 2026 geeyu

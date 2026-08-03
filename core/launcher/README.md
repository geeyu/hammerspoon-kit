# Launcher — Raycast 式启动中枢

Option+Space 呼出的居中启动面板：空输入显示快捷命令卡片网格（剪贴板/文件搜索/防睡眠控制台/应用入口），点「应用」进入应用组网格（运行中 + 最常用），输入即实时过滤候选，↑↓/←→ 选、Enter 执行、Tab 应用二级操作、Esc 返回/关闭。Vue3 webview（hsutil 占位符体系）+ Lua 分层（init/config/api/panel/registry/runner/store）。

## 使用

```lua
-- 在 ~/.hammerspoon/init.lua
local launcher = require("core.launcher")
launcher:start()          -- Option+Space 呼出
```

- 热键：`config.hotkey_show = { "alt", "space" }`（Cmd+Space 被 macOS 系统层占用 -9878，故用 Option）。
- 面板尺寸：`config.panel = { widthRatio = 0.52, heightRatio = 0.62, yRatio = 0.22 }`（屏幕 52% 宽 × 62% 高，对齐 Clipboard）。
- 空输入：快捷命令卡片网格（config.cards + Spoon 协议卡片，末尾「应用」入口）；点「应用」进入应用组网格（运行中 + 按 SQLite 频次排序的常用应用，取 24 个），`Esc` 返回主页。
- 应用行选中后按 `Tab` 展开二级操作（打开 / 聚焦 / 退出 / 新建窗口 / 在 Finder 显示），`Esc` 返回一级。

## 能力（源）

| 源 | 关键词 | 说明 |
|----|--------|------|
| apps | kill / reveal | 目录扫描应用（/Applications、/System/Applications、~/Applications、CoreServices，不用 Spotlight，秒出）+ Tab 二级操作（聚焦/退出/新窗口/Finder 显示） |
| calc | - | 算术表达式（回车复制结果） |
| screencapture | sc | 截屏（全屏/选区/剪贴板/菜单） |
| urlformats | uf | URL scheme 打开 + 裸 URL 搜索（`url_providers` 模板拼 URL） |
| useractions | add / del | 书签/静态动作（存 SQLite `user_actions` 表）；`add <url> <名>` 收藏、`del <名>` 删除 |
| custom | 自定义 keyword | `config.custom_commands` 命令（keyword 置顶不独占） |
| cards | - | 功能卡片墙（`config.cards` + 协议提供者，见「Spoon 接入协议」） |

源开关在 `config.enabled_sources`。

## 配置

全部集中在 `internal/config.lua`：

| 字段 | 默认 | 说明 |
|------|------|------|
| `hotkey_show` | `{ "alt", "space" }` | 呼出热键 |
| `panel` | `{ widthRatio=0.52, heightRatio=0.62, yRatio=0.22 }` | 面板尺寸（屏幕比例，对齐 Clipboard） |
| `debounce_ms` | `100` | 前端查询节流（毫秒） |
| `enabled_sources` | 7 源全开 | 启用的源（apps/calc/screencapture/urlformats/useractions/custom/cards） |
| `url_providers` | `{}` | urlformats 的 URL 模板：`{ key = { name = "", url = "https://…%s" } }` |
| `user_actions` | `{}` | 书签/静态动作：`{ ["名称"] = { keyword?, url?, fn?, description?, hotkey? } }` |
| `custom_commands` | 内置"文件搜索" | 自定义命令：`{ keyword, title, kind="shell", exec={cmd, {argv}} }`，argv 内 `"${query}"` 替换 |
| `cards` | `{}`（协议提供） | 功能卡片：`{ ["名称"] = { description, kind, ... } }`（kind 表见「Spoon 接入协议」） |

## Spoon 接入协议

任何 spoon 都可以向 Launcher 提供功能卡片、关键词命令与书签动作，无需改动 Launcher 本体。详见下方小节。

### 接入清单（三步）

1. 在 spoon 根目录放 `launcher-commands.lua`（或运行时调 `launcher:registerCommands`）。
   启动时自动扫描 `Spoons/*.spoon/` 与 `core/*/` 下的 `launcher-commands.lua`。
2. 在 manifest 中声明 `cards` / `custom_commands` / `user_actions`。
3. 重启 Hammerspoon（或运行时注册即时生效）。

### manifest 格式

```lua
-- Spoons/<你的spoon>.spoon/launcher-commands.lua
return {
  name = "myspoon",
  cards = { ... },           -- 可选：功能卡片（常驻卡片墙）
  custom_commands = { ... }, -- 可选：关键词命令
  user_actions = { ... },    -- 可选：书签/动作
}
```

### 卡片 kind 表

| kind | 字段 | 行为 |
|------|------|------|
| shell | exec={cmd,{argv}} | 后台执行；argv 内 "${query}" 替换（卡片墙场景无 query） |
| openurl | url | 默认浏览器打开；url 内 "${query}" 替换 |
| screen | sub={kind,postUI} | 截屏（interactive/fullscreen/clipboard/menu） |
| page | url | 面板内 iframe 打开任意 spoon 的 view（子页面协议，见下） |
| runFunction | fn=function(cfg) | 执行 Lua 闭包；cfg 为配置表单值（config schema 驱动） |

### config schema（runFunction 配置表单）

```lua
config = { { key = "type", label = "模式", type = "select", options = {{ label, value }} },
           { key = "untilTime", label = "时间", type = "text" } }
```

`type` ∈ select/radio/checkbox/text；select/radio 需要 `options`（`{label, value}` 列表）。
表单键盘：↑↓ 聚焦字段、←→ 切换选项、空格 checkbox、Enter 执行。

### 子页面协议（kind="page"）

- url 指向自家静态路由，如 `"/myspoon/view/index.html"`（自家 init.lua 用 `app:static("/myspoon/view", spoonPath .. "views")` 挂载；参考实现 StayAwake 挂的是 `spoonPath .. "assets"`）。
- 子页面可同源调用 `window.parent.closePage()` 关闭面板内 iframe（前端另暴露 `closeStayAwake` 兼容别名）。
- 参考实现：`Spoons/StayAwake.spoon/launcher-commands.lua`。

### 运行时注册

```lua
local launcher = require("core.launcher")
launcher:registerCommands("myspoon", { cards = { ... } })  -- 即时生效
```

### 校验规则

合并期校验：未知 kind / 缺必需字段（shell.exec、openurl/page.url、runFunction.fn、custom.keyword、action 的 url|fn）→ 警告日志 + 跳过；config schema 非法字段丢弃。用户直接写 config.cards 不受校验约束（宽松默认 shell 行为保留）。

## 开发

分层：`init`（装配：热键 / start/stop / 模块协调）、`internal/config`（配置单点）、`internal/api`（HTTP 路由 + 静态挂载）、`internal/panel`（webview 生命周期）、`internal/registry`（源注册 + 关键词解析 + 候选聚合 + runner 注入 + 「Spoon 接入协议」manifest 校验与合并）、`internal/runner`（动作执行分发）、`internal/store`（SQLite 存储）、`internal/sources`（七源）。

测试：

```bash
# 纯 Lua 单元测试（mock 掉 hs.* 的 IO）
lua5.4 core/launcher/test/unit_test.lua
# 预期：结果: 54 通过, 0 失败

# Hammerspoon console 集成自测
require("core.launcher.internal._test").run()
```

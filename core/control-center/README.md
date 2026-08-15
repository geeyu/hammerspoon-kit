# ControlCenter — 统一菜单栏控制中心

常驻菜单栏按钮（🛠）下拉：打开聚合配置页 + 各 Spoon 配置入口 + 重载/退出。聚合配置页是 webview 功能块网格（Vue3 + HSUtil 占位符组件库），数据源只读复用各 Spoon 的 launcher-commands.lua 协议，配置面板为单例（HSUtil.webview 惰性创建，setUrl 切换）。

## 使用

```lua
-- 根 init.lua
require("core.control-center")   -- 自启：require 即装配，菜单栏按钮即现
```

- 自启：`require` 即完成装配（与 HSUtil 模式一致）；`ControlCenter:stop()` 移除菜单栏按钮并销毁面板。
- 面板尺寸：默认 `{ widthRatio=0.7, heightRatio=0.78, yRatio=0.1 }`（聚合配置页大面板，宽 70% 高 78%），可经 `menubar.setup` 透传 `panel.setup` 覆盖。

## 能力（菜单栏下拉结构）

每次打开菜单时**重新扫描**数据源（数据新鲜）；扫描异常回退缓存，仍失败则降级为固定三项，绝不抛错阻塞启动。

```
① 打开控制中心        → panel.showAggregate()（切回聚合配置页）
② 分隔线
③ 各 Spoon 配置入口    → 见下方「入口规则」
④ 分隔线（仅在有配置入口时）
⑤ 重载 Hammerspoon    → hs.reload()
⑥ 退出 Hammerspoon    → 兼容 hs.exit()（HS 1.1.1 已移除，回退 application:kill）
```

入口规则（provider 维度）：

| provider 形态 | 菜单表现 | 点击行为 |
| --------------- | ---------- | ---------- |
| 有 `pages`（含 configUrl） | 子菜单，每配置页一项（icon + name） | `panel.open(configUrl)` |
| 无 pages，但有 `kind="page"` 卡片 | 每卡单项 | `panel.open(卡 url)` |
| 两者皆无（含 pages 全是搜索页） | 禁用项（provider 名） | — |

## 能力（聚合配置页）

webview **功能块网格**（双列大格子，宽 70% 高 78% 大面板），`GET /control-center/api/providers` 拉取提供者列表：

- 每 provider 一个**格子**：图标（自身 icon → 卡片 icon → 配置页 icon，无则名称首字母徽标）+ 显示名（卡片中文名优先，如「应用显隐」）+ 摘要（首个卡片 description → 「N 个配置页」→「暂无配置」）+ 「打开配置 →」入口。
- 格子系统：圆角边框卡片，悬停抬升 + 边框高亮 + 箭头位移，打开中按压动效防重复点击。
- 点击格子 `POST /control-center/api/open` 打开该 provider 首个配置入口（与 menubar 同优先级：`pages[].configUrl` → `page` 卡 url → 任意带 url 卡片）。
- 加载/空/失败三态：加载 spinner、空态「暂无可用组件」、失败态提示 + 重试按钮（`ui-loading`/`ui-empty`/`ui-button`）。

## 能力（配置面板单例，setUrl 切换）

`internal/panel.lua`：基于 HSUtil.webview 的惰性单例（首次 `open` 才建 webview）。创建/居中/失焦自动隐藏/Esc 兜底/加载保护全部由 HSUtil.webview 承担，本层只加：

- **setUrl 切换**：`open(url)` 时 url 与当前加载页不同 → 先 `wv:url(url)` 再 show（面板隐藏时先切好，避免旧页闪现）；相同 → 仅 show。
- **返回 shim**：既有 Spoon 配置页的返回按钮调 `window.parent.closePage()`（StayAwake 旧页面兼容别名 `closeStayAwake()`）；本面板以**顶层 URL** 打开，`parent === window`，返回即失效。故导航完成后自动注入 shim：`window.closePage = window.closeStayAwake = 切回聚合页`（`location.href`，幂等），**既有页面零修改即可返回聚合页**。
- 导航完成检测不用 navigationCallback（HSUtil.webview 内部已占用且为 setter-only），改用同步 getter 轻轮询（0.25s/次：`wv:url()` 指向新文档且 `wv:loading()==false`），任何导航来源后都自动补注，每文档只注入一次。

## HTTP API（共享 HSUtil server，端口 8821）

| 路由 | 说明 |
| ------ | ------ |
| `GET  /control-center/api/providers` | 提供者列表（name/icon/cards/pages，已剔除非可序列化字段） |
| `POST /control-center/api/open` | 打开配置面板（body `{ url }`；缺 url → 400） |
| `POST /control-center/api/close` | 隐藏配置面板 |
| `静态 /control-center/view/*` | 聚合配置页前端（本目录 views/ 根） |

## 数据来源（只读复用 launcher-commands.lua 协议）

`internal/sources.lua` **独立扫描**各 Spoon 根目录的 `launcher-commands.lua`：

- 扫描目录：`hs.configdir/Spoons/*.spoon/` 与 `hs.configdir/core/*/` 一级子目录下的 `launcher-commands.lua`。
- 只提取 manifest 的 `name` / `cards` / `pages`（含 `config_pages` 老字段兼容）。
- 页面 URL 统一归一化：值不含 `/` → 推断 `/ <modName> /view/pages/<值>/index.html`；以 `/` 开头 → 原样使用。
- 同名 provider 去重覆盖（后扫描者胜，位置保留）。

**只读原则（零副作用）**：

- 构建新表，绝不修改协议原表；只读 manifest，绝不执行其中任何函数（卡片 kind 的 `fn` 字段不读取不执行）。
- 绝不写任何模块的配置、不注册任何路由。
- 不缓存落盘、不写 SQLite；`scan()` 每次重扫覆盖内存缓存，`get()` 读缓存（未扫描过则首次扫描）。

## 开发

分层：`init`（装配：dofile 兄弟模块、panel.setup 注入聚合页 URL、api.setup 挂路由+静态、menubar.setup 注入同一实例后 start；模块自启）、`internal/sources`（只读协议扫描）、`internal/panel`（配置面板单例 + setUrl + 返回 shim）、`internal/api`（HTTP 路由）、`internal/menubar`（常驻菜单栏按钮，每次打开重建菜单）。

测试：

```bash
# 纯 Lua 单元测试（mock 掉 hs.*，133 用例：sources 30 + panel 31 + menubar 41 + api 23 + init 装配 8）
lua5.5 core/control-center/test/unit_test.lua
# 预期：结果: 133 通过, 0 失败（lua5.4 亦可运行）

# 前端 index.html 占位符展开验证（14 项：vendor/组件/脚本顺序/私有样式）
lua5.5 core/control-center/test/verify_frontend.lua
# 预期：== 占位符展开: 14 PASS / 0 FAIL ==

# 前端 store.js 逻辑验证（node 环境，17 项：providerUrl 选择/open 流程/失败兜底）
node core/control-center/test/verify_frontend_store.js
# 预期：== store.js 功能验证: 17 PASS / 0 FAIL ==
```

集成自测（需 Hammerspoon GUI）：`require("core.control-center")` 后菜单栏 🛠 即现；打开菜单核对各 Spoon 配置入口、点「打开控制中心」核对功能块网格、点格子/入口核对单例面板 setUrl 切换与返回聚合页。

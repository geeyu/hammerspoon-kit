# 二次开发指南

本仓库把「工具开发」拆成三个可独立理解的部分：**核心框架（core/hsutil）**、**控制中心（core/control-center）**、**工具包（Spoons/*.spoon）**。开发新工具 = 用框架写一个 Spoon + 通过 launcher-commands.lua 协议注册配置入口。

## 1. 用脚手架建一个新 Spoon

```bash
cp -r core/hsutil/template/tool.spoon Spoons/MyTool.spoon
```

模板自带：`init.lua`（装配层）、`internal/example.lua`（功能层）、`views/`（Vue3 webview 面板：home + settings 两页）、`test/unit_test.lua`（测试入口）。

## 2. Spoon 的标准结构

```
MyTool.spoon/
├── init.lua                 # 公开 API：start/stop/配置读取，负责装配
├── internal/                # 功能实现，按职责拆分小文件
│   ├── config.lua           #   配置单点（默认值 + 读取 ~/.hammerspoon/data/MyTool/settings.json）
│   ├── api.lua              #   HTTP 路由挂载（HS.http.app:get/post ...）
│   └── ...                  #   各功能模块
├── views/                   # webview 面板（纯 Vue3，无构建工具）
├── launcher-commands.lua    # 配置入口协议（可选，见下）
└── test/                    # 测试
```

## 3. 核心框架能力（core/hsutil）

| 能力 | 入口 | 说明 |
| ------ | ------ | ------ |
| HTTP 网关 | `HS.http.app` | 各 Spoon 共享一个本地 HTTP server，`HS.http.app:get("/mytool/api/x", fn)` 挂路由 |
| SQLite ORM | `HS.db` | 建表/迁移/增删改查，数据落 `data/` 目录 |
| Webview 面板 | `HS.webview` | 创建/管理 webview 面板，加载 `views/` 静态页 |
| UI 组件库 | `core/hsutil/assets/components/` | Vue3 通用组件（ui-tabs/ui-form/...），按 `assets/README.md` 说明引入 |
| 工具函数 | `HS.util` | 路径/任务/JSON 等杂项 |
| 脚手架 | `core/hsutil/template/tool.spoon` | 新 Spoon 起点 |

## 4. 注册配置入口（launcher-commands.lua 协议）

在 Spoon 根目录放 `launcher-commands.lua`（控制中心自动发现）：

```lua
-- 启动时 ControlCenter 自动扫描 Spoons/*.spoon/ 下的该文件
return {
    name = "mytool",
    cards = {
        ["我的工具"] = {
            description = "一句话说明",
            kind = "page",          -- page=面板子页面
            icon = "🔧",
            url = "home",           -- views/pages/home/index.html
        },
    },
    pages = {
        { name = "我的工具", icon = "🔧", config = "home" },
    },
}
```

重启 Hammerspoon 后，菜单栏 🛠 → 控制中心即出现「我的工具」入口。

## 5. 开发流程约定

1. 功能按 `init.lua`（装配）→ `internal/*.lua`（实现）→ `views/`（面板）分层
2. 配置集中在 `internal/config.lua`，支持 `data/` 目录 JSON 持久化
3. 测试放 `test/`：纯逻辑用 `lua5.4` 直跑（mock hs.*），面板用 headless 浏览器测试
4. 提交信息遵循 Conventional Commits（feat/fix/refactor/docs/...）

## 6. 深入阅读

- `core/control-center/README.md` — 控制中心能力与入口协议说明
- `core/hsutil/assets/README.md` — UI 组件库用法
- 各 `Spoons/*.spoon/docs/README.md` — 既有包的实现范例

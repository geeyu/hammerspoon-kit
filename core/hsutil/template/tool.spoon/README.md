# Tool.spoon 模板

HSUtil UI 快速开发脚手架。复制本目录 → 改名 `<你的包>.spoon` → 全局替换 `Tool`/`tool` → 开始写页面。

## 结构

- `init.lua` — Spoon 入口：共享 server 静态路由 + webview + openPage() 导航
- `internal/` — Lua 业务逻辑与 API 路由（前缀 `/api/<包名>/` 避免冲突）
- `views/` — 前端根（镜像 dashboard 组织）
  - `pages/<page>/index.html` — 一个页面一个文件夹
  - `pages/<page>/store.js` — 页面级状态（Vue reactive + provide/inject）
  - `pages/<page>/components/` — 页面私有组件（每组件一文件夹）
  - `components/` — 业务全局共享组件
  - `utils/` — 业务工具
  - `styles/` — 业务全局样式
- `test/` — Lua 单元测试

## 页面接入 hsutil UI

index.html 中声明占位符，服务端自动注入（勿手写 hsutil 的 link/script）：

```html
<!-- hsutil:ui button,form,table use-crud -->
<!-- hsutil:fx glass -->
<!-- hsutil:amis -->
```

注意：`ui-amis` 是组件名，占位符 `<!-- hsutil:ui ... ui-amis -->` 会自动带出 amis SDK + utils/amis.js；纯 JS 页面（无组件）才用独立 `<!-- hsutil:amis -->` 占位符。

页面逻辑必须放在外部 `defer` 脚本（store.js → app.js 顺序），内联 `<script>` 会在 defer 的组件 js 之前执行，`registerUiComponents` 未定义会报错。

## 使用

1. `hs.loadSpoon("Tool")`（或直接 `dofile`）
2. `Tool.toggle()` 呼出面板；`Tool.open("settings")` 打开指定页面
3. 新页面：`views/pages/<name>/` 下建 index.html + store.js + components/

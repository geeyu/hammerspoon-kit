# HSUtil UI 资产库（core/hsutil/assets）

HSUtil 的浏览器端 UI 资产：Vue 3 组件库 + 动效 + 图标 + 页面特效。
服务端（`HSUtil.internal.ui`，`core/hsutil/internal/ui.lua`）负责把 HTML 中的占位符展开为资源标签，页面零手工 script/link。

## 目录结构

```
assets/
├── styles/      基础样式（base.css：进场动画 / 玻璃面板 / spinner / kbd / 滚动条 / 补充色值变量）
├── vendor/      第三方库（vue / anime / IconPark / highlight，见版本清单）
├── effects/     页面级特效（glass-fx/：玻璃光尘粒子 + 卡片扫光，每特效一目录）
├── components/
│   ├── ui/      Vue 组件（ui-button、ui-form、ui-table … 每组件一目录：index.js + style.css + tpl.html）
│   └── ui/README.md  组件清单与注册说明
├── recipes/     效果配方（recipes/anime-text.md：anime v4 文本特效）
├── pages/       页面（pages/demo/：组件预览页，index.html + app.js + style.css 同目录）
└── README.md    本文件
```

## 快速开始（5 步）

1. 页面 `<body>` 顶部声明占位符（可多行，逗号/空格分隔）：
   ```html
   <!-- hsutil:ui button,form,table -->
   <!-- hsutil:fx glass -->
   ```
2. 写页面结构，用 `ui-` 前缀组件标签：`<ui-button>`、`<ui-form :schema="...">`、`<ui-table :columns="..." :items="...">` …（组件清单见 `components/ui/README.md`）。
3. 引入 `registerUiComponents` 注册组件（`components/ui/index.js`）：
   ```js
   var { createApp } = Vue;
   var app = createApp({ ... });
   registerUiComponents(app);
   app.mount('#app');
   ```
4. 用 hsutil http 服务打开页面；`http://127.0.0.1:8821/hsutil/assets/pages/demo/index.html` 是完整预览页。
5. 服务端对 text/html 响应自动展开占位符：vendor → base.css → 组件 css → tpl 内联 → 组件 js（defer，依赖拓扑序在前）。Network 面板应只见注入资源，无 404、无重复。

## 占位符语法与依赖表

| 占位符 | 注入内容 | 用途 |
|---|---|---|
| `<!-- hsutil:ui button,form … -->` | vue + 组件 vendor 依赖 + base.css + 组件 css / tpl 内联 / js（defer） | Vue 页面（组件名可用全名 `ui-button` 或短名 `button`；`use-crud` 本身即全名） |
| `<!-- hsutil:fx glass -->` | anime + glass-fx.css + glass-fx.js | 页面级玻璃光尘特效 |
| `<!-- hsutil:icons -->` | IconPark 全局 | 页面脚本直调 `IconPark[name](...)` 生成 SVG |

依赖自动带出：`ui-icon` → IconPark；`ui-button`/`ui-tabs`/`ui-empty` → `ui-icon`。

## vendor 版本清单

| 库 | 版本 | 文件 |
|---|---|---|
| Vue | 3.5.40（3.x） | `vendor/vue.global.prod.js` |
| anime | 4.5.0 | `vendor/anime.umd.min.js` |
| IconPark | 1.4.2 | `vendor/iconpark/iconpark.umd.min.js`（2658 图标，Apache-2.0） |
| highlight.js | 11.9.0 | `vendor/highlight.min.js` + `atom-one-dark.min.css` |

highlight 已入库但未注册占位符（按需自引），供代码高亮场景使用。

## 图标库：两种方式

1. **`ui-icon` 组件（推荐）**：`<ui-icon name="search" :size="18" />`，经注册表自动注入 IconPark，kebab-case 名自动归一化为 PascalCase 导出，stroke=currentColor 随主题色。
2. **裸标签**：`<!-- hsutil:icons -->` 注入全局后页面脚本直调 `IconPark['Search']({ size: '100%', colors: ['currentColor','transparent','currentColor','transparent'], strokeWidth: 4 })` 生成 SVG——不经 Vue，适合静态 HTML 页面。

## 关联

- 预览页：`pages/demo/`（index.html + app.js + style.css，占位符注入全部组件 + fx glass）
- 特效 recipe：`recipes/anime-text.md`（splitText / scrambleText / count-up / stagger+spring 四个示例）
- 组件清单与注册说明：`components/ui/README.md`
- 模板脚手架：`core/hsutil/template/tool.spoon/`（含占位符用法的完整示例页面）

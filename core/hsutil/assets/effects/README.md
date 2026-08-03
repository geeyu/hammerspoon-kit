# HSUtil 页面级特效（assets/effects/）

与组件库（`components/ui/`）分离的页面级视觉特效：不注册为组件标签，经
`<!-- hsutil:fx <name> -->` 占位符注入（服务端展开见 `core/hsutil/internal/ui.lua` 的 fx 注册表）。

## 特效清单

| 特效 | 文件 | 说明 | 依赖 | 用法 |
|---|---|---|---|---|
| glass | `glass-fx.js` + `glass-fx.css` | 玻璃光尘粒子（贝塞尔曲线路径 + 柔光微粒漂移 + 呼吸闪烁）+ 卡片 hover 扫光 | anime（经占位符自动带出） | `HSUI.initGlassFX()` 自动创建 `.fx-paths`(SVG) + `.fx-layer` 并撒粒子；`HSUI.cardSheen(el)` 对卡片做 hover 扫光（目标需 `position:relative` + `overflow:hidden`） |

## 注入方式

页面 index.html 中声明（可与其他占位符并存，vendor 资产共享去重）：

```html
<!-- hsutil:fx glass -->
```

展开后注入 `vendor/anime.umd.min.js` + `effects/glass-fx.js` + `effects/glass-fx.css`。

## 约定

- 特效脚本以 `HSUI.*` 全局暴露（与组件 `UiXxx` 全局变量区分），页面脚本在
  `defer` 顺序上晚于特效脚本，直接调用即可。
- 特效内部对 `window.anime` 缺失和 `prefers-reduced-motion: reduce` 做了降级，无
  anime 时功能完整可用（仅少动画）。

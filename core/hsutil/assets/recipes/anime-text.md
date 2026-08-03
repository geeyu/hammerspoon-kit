# anime v4 文本特效 recipe

前置：`<!-- hsutil:fx glass -->` 会注入 anime；纯文本特效只需 `<!-- hsutil:ui ... -->` 任意组件（vue 恒有）+ 手动在页面加 `<script src="/hsutil/assets/vendor/anime.umd.min.js" defer></script>`（或经 fx 占位符）。

## 标题逐字入场（splitText）

```html
<h2 id="title">HSUtil UI</h2>
<script defer>
window.addEventListener('DOMContentLoaded', function () {
  var chars = anime.splitText('#title');
  anime({ targets: chars, translateY: [20, 0], opacity: [0, 1], delay: anime.stagger(40), ease: 'outQuad' });
});
</script>
```

## 数字乱码跳动（scrambleText）

```js
// 加载中数字：文字先乱码后定格
anime.scrambleText('#count', { text: '42', duration: 1200 });
```

## count-up（数字滚动）

```js
// 用 round + 手动 tween 实现
var el = document.querySelector('#num');
anime({ targets: { v: 0 }, v: 128, round: 1, duration: 1200, ease: 'outExpo',
  update: function (a) { el.textContent = a.animations[0].currentValue; } });
```

## 弹簧列表（stagger + spring）

```js
anime({ targets: '.item', scale: [0.8, 1], opacity: [0, 1], delay: anime.stagger(50),
  ease: anime.spring({ stiffness: 260, damping: 18 }) });
```

/**
 * HSUtil 页面级特效：玻璃光尘粒子 + 卡片扫光。
 * 依赖：anime v4（/hsutil/assets/vendor/anime.umd.min.js，经 <!-- hsutil:fx glass --> 注入）。
 * 用法：
 *   HSUI.initGlassFX();   // 自动创建 .fx-paths(SVG) + .fx-layer 并撒粒子
 *   HSUI.cardSheen(el);   // hover 扫光（目标元素需 position:relative + overflow:hidden）
 * 样式：effects/glass-fx.css（随 fx 占位符注入）
 */
(() => {
  // 合并而非覆盖：overlay.js 等可能已挂载 HSUI 子模块
  window.HSUI = window.HSUI || {};
  var HSUI = window.HSUI;

  // hover 高光扫过：一道玻璃反光快速扫过卡面
  HSUI.cardSheen = (card) => {
    if (!window.anime || !card || card.querySelector(".card-sheen")) return;
    var s = document.createElement("span");
    s.className = "card-sheen";
    card.appendChild(s);
    anime({
      targets: s,
      translateX: ["-130%", "340%"],
      duration: 680,
      ease: "inOutQuad", // v4: easing → ease，easeInOutQuad → inOutQuad
      onComplete: () => {
        s.remove();
      },
    });
  };

  // 玻璃光尘：4 条贝塞尔曲线 + 柔光微粒漂移 + 呼吸闪烁
  HSUI.initGlassFX = () => {
    if (!window.anime || !anime.svg || !anime.svg.createMotionPath) return;
    if (
      window.matchMedia &&
      matchMedia("(prefers-reduced-motion: reduce)").matches
    )
      return;
    // 控制中心 iframe 内嵌入：宿主面板已有光效，不再重复撒粒子（避免双层光效）
    if (document.documentElement.classList.contains("in-iframe")) return;
    // 特效层自动创建：所有使用 glass-panel 背景的页面只需声明 fx 占位符 + 调用本函数，
    // 无需手写 <div class="fx-layer">（页面已自带 layer 时复用，避免重复）。
    var layer = document.querySelector(".fx-layer");
    if (!layer) {
      var host = document.querySelector(".glass-panel") || document.body;
      layer = document.createElement("div");
      layer.className = "fx-layer";
      layer.setAttribute("aria-hidden", "true");
      host.appendChild(layer);
    }

    var svg = document.querySelector(".fx-paths");
    if (!svg) {
      svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.setAttribute("viewBox", "0 0 360 600");
      svg.setAttribute("class", "fx-paths");
      svg.setAttribute("fill", "none");
      layer.appendChild(svg); // 随特效层裁剪，不污染 body
    }
    var defs = [
      "M 40,60 C 140,20 260,120 200,240 C 150,340 300,380 320,520",
      "M 320,80 C 220,140 100,100 80,220 C 60,340 200,320 240,440 C 270,520 160,560 60,540",
      "M 180,580 C 100,480 260,420 220,320 C 180,220 60,260 80,140 C 95,60 220,80 300,40",
      "M 20,300 C 100,220 180,380 260,300 C 320,240 340,160 300,100",
    ];
    defs.forEach((d, i) => {
      var p = document.createElementNS("http://www.w3.org/2000/svg", "path");
      p.setAttribute("id", "fxp" + (i + 1));
      p.setAttribute("d", d);
      svg.appendChild(p);
    });
    var paths = defs.map((_, i) => {
      return anime.svg.createMotionPath("#fxp" + (i + 1)); // v4: anime.path → anime.svg.createMotionPath
    });
    // 注：createMotionPath 返回 { translateX, translateY, rotate } 函数描述符（非数组），
    // 内部经 getCTM() 感知 SVG 实际渲染尺寸——.fx-paths 已铺满面板（100%），
    // 粒子坐标自动为面板像素，无需手动缩放。

    function makeOrb(cls, size, baseOpacity) {
      var el = document.createElement("i");
      el.className = "fx-orb" + (cls ? " " + cls : "");
      el.style.width = el.style.height = size.toFixed(1) + "px";
      el.style.opacity = baseOpacity;
      el.dataset.o = baseOpacity;
      layer.appendChild(el);
      return el;
    }
    function drift(el) {
      var p = paths[Math.floor(Math.random() * paths.length)];
      var a = anime(
        Object.assign(
          {
            targets: el,
            duration: 18000 + Math.random() * 22000,
            alternate: true,
            loop: true, // v4: direction:'alternate' → alternate:true
            ease: "inOutSine", // v4: easeInOutSine → inOutSine
          },
          { translateX: p.translateX, translateY: p.translateY },
        ),
      );

      a.seek(a.duration * Math.random());
      var base = parseFloat(el.dataset.o);
      var tw = anime({
        targets: el,
        opacity: [base * 0.3, base],
        duration: 2200 + Math.random() * 3400,
        alternate: true,
        loop: true,
        ease: "inOutSine",
      });
      tw.seek(tw.duration * Math.random());
    }
    var i;
    for (i = 0; i < 8; i++)
      drift(
        makeOrb(
          "",
          2 + Math.random() * 3,
          (0.35 + Math.random() * 0.35).toFixed(2),
        ),
      );
    for (i = 0; i < 5; i++)
      drift(
        makeOrb(
          "fx-orb--bokeh",
          12 + Math.random() * 12,
          (0.08 + Math.random() * 0.12).toFixed(2),
        ),
      );
  };

  window.HSUI = HSUI;
})();

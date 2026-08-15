/**
 * 控制中心 — Vue3 前端 UI 层（聚合配置页）
 * 数据层在 store.js（provide/inject）：GET /providers + iframe 内打开配置页。
 * 本文件只做 UI：功能块格子渲染、图标/摘要装饰、加载/空/失败三态、
 * closePage 桥（iframe 内配置页的返回按钮调 parent.closePage()）。
 */
const { createApp, onMounted, inject } = Vue;

// 无图标提供者的徽标色板（按名称 hash 取色）
const BADGE_COLORS = [
  "#1e3a5f",
  "#1a3a2a",
  "#3a2815",
  "#2a1a3a",
  "#1a2a3a",
  "#3a1a1a",
  "#3a3a1a",
];

function hashStr(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

createApp({
  setup() {
    const store = inject("controlCenterStore");
    const state = store.state;

    // ===== 格子装饰 =====

    // 提供者图标：自身 icon → 卡片 icon → 配置页 icon（emoji 类，直接文本渲染）
    function providerIcon(p) {
      if (!p) return "";
      if (p.icon) return p.icon;
      const cards = p.cards || [];
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].icon) return cards[i].icon;
      }
      const pages = p.pages || [];
      for (let i = 0; i < pages.length; i++) {
        if (pages[i].icon) return pages[i].icon;
      }
      return "";
    }

    // 显示名：卡片中文名（首卡 key，如「应用显隐」）优先，内部 name 兜底
    function displayName(p) {
      if (!p) return "";
      const cards = p.cards || [];
      if (cards.length && cards[0].key) return cards[0].key;
      return p.name || "";
    }

    // 兜底徽标：名称首字母
    function iconText(p) {
      return (p && p.name ? p.name : "?").charAt(0).toUpperCase();
    }
    function iconStyle(p) {
      const color =
        BADGE_COLORS[hashStr((p && p.name) || "") % BADGE_COLORS.length];
      return { background: color, color: "#fff" };
    }

    // 描述摘要：首个非空 description；无卡片时展示配置页数量（无则「暂无配置」）
    function cardSummary(p) {
      if (!p) return "";
      const cards = p.cards || [];
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].description) return cards[i].description;
      }
      const pages = p.pages || [];
      if (pages.length) return pages.length + " 个配置页";
      return "暂无配置";
    }

    // 失败态重试
    function reload() {
      store.load();
    }

    onMounted(() => {
      store.load();
      // iframe 桥：配置页在 iframe 内打开，其返回按钮调 window.parent.closePage()
      // （launcher 子页面协议）——本页是 parent，提供实现：隐藏 iframe 回首页。
      // 兼容旧别名 closeStayAwake（StayAwake 老页面）。
      window.closePage = () => store.closePage();
      window.closeStayAwake = () => store.closePage();
      window.__ccPanelShim = true;
      // 玻璃光尘特效（fx 占位符已注入 anime/glass-fx）
      try {
        if (window.HSUI && HSUI.initGlassFX) HSUI.initGlassFX();
      } catch (e) {}
    });

    return {
      providers: state.providers,
      loading: state.loading,
      error: state.error,
      opening: state.opening,
      activeUrl: state.activeUrl,
      openProvider: store.openProvider,
      reload,
      providerIcon,
      displayName,
      iconText,
      iconStyle,
      cardSummary,
    };
  },
})
  .use(ControlCenterStore)
  .mount("#app");

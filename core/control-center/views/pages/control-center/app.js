/**
 * 控制中心 — Vue3 前端 UI 层（聚合配置页，与 launcher 一致 uTools/深色玻璃风格）
 * 数据层在 store.js（provide/inject）：GET /providers + POST /open 的 fetch 与页面状态。
 * 本文件只做 UI：provider 卡片渲染、图标/摘要装饰、加载/空/失败三态、玻璃光尘。
 */
const { createApp, onMounted, inject } = Vue;

// 无图标提供者的徽标色板（按名称 hash 取色，与 launcher 一致）
const BADGE_COLORS = ['#1e3a5f','#1a3a2a','#3a2815','#2a1a3a','#1a2a3a','#3a1a1a','#3a3a1a'];

function hashStr(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

createApp({
  setup() {
    const store = inject('controlCenterStore');
    const state = store.state;

    // ===== 卡片装饰 =====

    // 提供者图标：自身 icon → 卡片 icon → 配置页 icon（emoji 类，直接文本渲染）
    function providerIcon(p) {
      if (!p) return '';
      if (p.icon) return p.icon;
      const cards = p.cards || [];
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].icon) return cards[i].icon;
      }
      const pages = p.pages || [];
      for (let i = 0; i < pages.length; i++) {
        if (pages[i].icon) return pages[i].icon;
      }
      return '';
    }

    // 兜底徽标：名称首字母（与 launcher 应用徽标同规则）
    function iconText(p) {
      return (p && p.name ? p.name : '?').charAt(0).toUpperCase();
    }
    function iconStyle(p) {
      const color = BADGE_COLORS[hashStr((p && p.name) || '') % BADGE_COLORS.length];
      return { background: color, color: '#fff' };
    }

    // cards 描述摘要：首个非空 description；无卡片时展示配置页数量（无则「暂无配置」）
    function cardSummary(p) {
      if (!p) return '';
      const cards = p.cards || [];
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].description) return cards[i].description;
      }
      const pages = p.pages || [];
      if (pages.length) return pages.length + ' 个配置页';
      return '暂无配置';
    }

    // 失败态重试
    function reload() {
      store.load();
    }

    onMounted(function () {
      store.load();
      // 玻璃光尘粒子（由 <!-- hsutil:fx glass --> 注入）：
      // 特效故障不应阻断页面挂载/使用，包 try/catch 兜底
      try {
        if (window.HSUI && HSUI.initGlassFX) HSUI.initGlassFX();
      } catch (e) {
        console.error('initGlassFX 失败', e);
      }
    });

    return { providers: state.providers, loading: state.loading, error: state.error,
             opening: state.opening, openProvider: store.openProvider, reload,
             providerIcon, iconText, iconStyle, cardSummary };
  },
}).use(ControlCenterStore).mount("#app");

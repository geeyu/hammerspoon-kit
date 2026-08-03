/**
 * Launcher — Vue3 前端 UI 层（uTools 风格）
 * 数据层在 store.js（provide/inject）：query/run/close 的 fetch 与页面状态。
 * 本文件只做 UI：键盘导航、详情面板动画、选中、图标装饰、玻璃光尘。
 */
const { createApp, ref, computed, onMounted, inject } = Vue;

const TYPE_SHORT = {
  launchOrFocus: "打开", kill: "结束", reveal: "显示",
  copyToClipboard: "复制", screenUI: "截图", screen: "截图",
  screen_clipboard: "截图", interactive: "截图", interactive_clipboard: "截图",
  launch: "打开", openURL: "打开", runFunction: "执行",
  invokeKeyword: "执行", addURL: "收藏", delURL: "删除",
  custom: "命令", cardShell: "命令", cardOpenURL: "打开", cardScreen: "截图",
};
const ICON_CHARS = { apps: "", calc: "#", screencapture: "▣", urlformats: "◦", useractions: "✓", custom: "⚡", cards: "◆" };
// 无图标应用的徽标色板（按名称 hash 取色）
const BADGE_COLORS = ['#1e3a5f','#1a3a2a','#3a2815','#2a1a3a','#1a2a3a','#3a1a1a','#3a3a1a'];
// Detail Panel 动作图标
const ACTION_ICONS = { open: "▶", focus: "◎", kill: "✕", newWindow: "⧉", reveal: "⌕" };

function hashStr(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

createApp({
  setup() {
    const store = inject('launcherStore');
    const state = store.state;

    const list = ref(null);
    const q = ref(null);

    // Detail / 命令详情关闭动画 timer（防重复触发）
    let closeTimer = null;
    let cmdCloseTimer = null;

    // 网格列数（随面板宽度自适应：74px 卡片 + 10px gap + 32px 边距）
    const GRID_COLS = Math.max(4, Math.floor((window.innerWidth - 32) / 84));

    // 按 section 分组（保持原始顺序；无 section 的行并入一个默认组）
    const groups = computed(() => {
      const out = [];
      let cur = null;
      state.items.value.forEach((row, idx) => {
        if (!cur || cur.section !== (row.section || null)) {
          cur = { section: row.section || null, rows: [] };
          out.push(cur);
        }
        cur.rows.push({ row: row, idx: idx });
      });
      return out;
    });

    // 网格项：按视图模式过滤空输入的 items
    //   home = 快捷命令卡片（含「应用」入口 appGroup）
    //   apps = 组件配置页（cardPage）+ 应用组（最近使用）
    const gridItems = computed(() => {
      const out = [];
      state.items.value.forEach((row, idx) => {
        const isHomeCard = row.section === '快捷命令';
        const isConfigPage = row.section === '组件配置';
        const isApp = row.plugin === 'apps';
        if ((state.mode.value === 'home' && isHomeCard) || (state.mode.value === 'apps' && (isConfigPage || isApp))) {
          out.push({ row: row, idx: idx });
        }
      });
      return out;
    });

    // ===== 输入 =====
    function onInput() {
      const text = state.query.value;
      // 任何输入都退出 Detail Panel
      if (state.detailOpen.value) closeDetail();
      // 注入模式：输入转发给应用搜索 iframe，不走全局查询
      if (state.injectedApp.value) {
        store.sendToApp({ type: 'query', text: text });
        return;
      }
      if (text.trim() === "") {
        state.terms.value = "";
        store.loadHome();
        return;
      }
      state.terms.value = text.trim();
      state.loading.value = true;
      store.search(text);   // 防抖在 store 内（100ms）
    }

    // ===== 视图切换 =====
    // home → apps（点「应用」入口卡片）；Esc 反向
    function gotoApps() {
      state.mode.value = 'apps';
      state.selected.value = 0;
    }
    function gotoHome() {
      state.mode.value = 'home';
      state.selected.value = 0;
    }
    // 命令网格 Enter/点击（主页）：按类型直接打开，不弹中间执行面板
    //   appGroup → 应用组视图；cardPage → iframe 打开页面；带 config 表单 → 命令详情；其它 → 直接执行
    function openGridCard(g) {
      if (!g) return;
      const row = g.row;
      if (row.type === 'appGroup') { gotoApps(); return; }
      if (row.type === 'cardPage') { openPage(row); return; }
      if (row.config && row.config.length) { openCmdDetail(row); return; }
      store.run(g.idx);
    }
    // 应用组视图 Enter/点击：组件配置页 → iframe；应用 → 直接运行
    function openAppsCard(g) {
      if (!g) return;
      if (g.row.type === 'cardPage') openPage(g.row);
      else store.run(g.idx);
    }

    // ===== Detail Panel（应用二级操作）=====
    // 从一级应用 row 计算动作列表（纯前端）
    function appActions(row) {
      const name = shortName(row.text);
      const acts = [
        { action: "open", icon: ACTION_ICONS.open, text: "打开 " + name },
      ];
      if (row.pid) {
        acts.push({ action: "focus", icon: ACTION_ICONS.focus, text: "聚焦 " + name });
        acts.push({ action: "kill",  icon: ACTION_ICONS.kill,  text: "退出 " + name });
      }
      acts.push({ action: "newWindow", icon: ACTION_ICONS.newWindow, text: "新建窗口 " + name });
      acts.push({ action: "reveal", icon: ACTION_ICONS.reveal, text: "在 Finder 显示" });
      return acts;
    }

    function openDetail(row) {
      state.detailTarget.value = row;
      state.detailActions.value = appActions(row);
      state.detailIdx.value = 0;
      state.detailOpen.value = true;
    }

    function closeDetail() {
      state.detailOpen.value = false;
      state.detailIdx.value = 0;
      // 两段式关闭：先触发 CSS transition 滑出，240ms 后移除 DOM
      clearTimeout(closeTimer);
      closeTimer = setTimeout(() => {
        state.detailTarget.value = null;
        state.detailActions.value = [];
      }, 240);
    }

    // ===== 命令详情面板（config schema）=====
    // 命令详情动作列表（按卡片 kind 生成可执行变体）
    function cmdActions(row) {
      if (row.type === 'cardScreen') {
        return [
          { text: '全屏截图',       sub: '截取整个屏幕',       subKind: 'fullscreen',          icon: '▣' },
          { text: '选区截图',       sub: '拖拽选择区域',       subKind: 'interactive',         icon: '▢' },
          { text: '全屏到剪贴板',   sub: '截取并复制',         subKind: 'clipboard',           icon: '⧉' },
          { text: '选区到剪贴板',   sub: '选区并复制',         subKind: 'interactive_clipboard', icon: '⧉' },
          { text: '截图菜单',       sub: 'macOS 原生截图菜单', subKind: 'menu',                icon: '☰' },
        ];
      }
      return [ { text: '执行', sub: row.subText || '运行该命令', run: true, icon: '▶' } ];
    }

    function openCmdDetail(row) {
      clearTimeout(cmdCloseTimer);  // 防止关闭动画窗口期内重开时，超时回调清掉新面板的 target
      // 子页面卡片（kind="page"）：直接打开面板内 iframe
      if (row.type === 'cardPage') { openPage(row); return; }
      state.cmdDetailTarget.value = row;
      const cfg = row.config || [];
      state.cmdDetailFields.value = cfg;
      const values = {};
      cfg.forEach(c => {
        values[c.key] = c.type === 'checkbox' ? false
          : (c.options && c.options[0] ? c.options[0].value : '');
      });
      state.cmdDetailValues.value = values;
      state.cmdDetailActions.value = cmdActions(row);   // 无 schema 时老路径
      state.cmdDetailOpen.value = true;
      state.cmdDetailIdx.value = 0;
      state.cmdDetailFocus.value = 0;
    }

    function closeCmdDetail() {
      state.cmdDetailOpen.value = false;
      state.cmdDetailIdx.value = 0;
      state.cmdDetailFields.value = [];
      state.cmdDetailValues.value = {};
      state.cmdDetailFocus.value = 0;
      // 两段式关闭：先触发 CSS transition 滑出，240ms 后移除 DOM
      clearTimeout(cmdCloseTimer);
      cmdCloseTimer = setTimeout(() => {
        state.cmdDetailTarget.value = null;
        state.cmdDetailActions.value = [];
      }, 240);
    }

    // 当前聚焦字段的选项显示文本
    function cfgDisplay(f) {
      const v = state.cmdDetailValues.value[f.key];
      const opt = (f.options || []).find(o => o.value === v);
      return opt ? opt.label : String(v ?? '');
    }

    // ===== 子页面（iframe，kind="page" 卡片）=====
    function openPage(row) {
      if (!row || !row.pageUrl) return;   // 缺 URL 忽略（后端校验已防呆，前端再兜一层）
      // 先清空再设 src，强制 iframe 重新导航：同 URL 二次打开时 Vue 不会重设属性（同值 no-op），
      // 否则 iframe 保持旧文档（如首次加载失败/旧版本页面）——旧 openStayAwake 直接重设 f.src 的语义
      state.pageSrc.value = '';
      state.pageOpen.value = true;
      Vue.nextTick(function () {
        state.pageSrc.value = row.pageUrl;
      });
    }
    function closePage() { state.pageOpen.value = false; }
    // iframe 同源调用：parent.closePage()
    window.closePage = closePage;
    // 兼容别名：StayAwake 旧子页面仍调 parent.closeStayAwake()
    window.closeStayAwake = closePage;

    // ===== 键盘导航 =====
    function onKey(e) {
      // 注入模式（应用搜索）：Esc/Tab/空退格 = 移除注入；↑↓/Enter = 转发 iframe
      if (state.injectedApp.value) {
        if (e.key === 'Escape' || e.key === 'Tab') {
          e.preventDefault();
          store.removeInject();
          return;
        }
        if (e.key === 'Backspace' && !state.query.value) {
          e.preventDefault();
          store.removeInject();
          return;
        }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter') {
          e.preventDefault();
          store.sendToApp({ type: 'key', key: e.key });
          return;
        }
        return;   // 其它键：字符输入走 onInput（转发 query）
      }

      // 命令详情模式：↑↓ 字段/动作导航；←→ 切换选项；空格 checkbox；Enter 执行
      if (state.cmdDetailOpen.value) {
        if (e.key === 'Escape') { e.preventDefault(); closeCmdDetail(); return; }
        if (e.key === 'ArrowDown') {
          e.preventDefault();
          if (state.cmdDetailFields.value.length) {
            state.cmdDetailFocus.value = Math.min(state.cmdDetailFocus.value + 1, state.cmdDetailFields.value.length);  // 最后一项是执行按钮
          } else if (state.cmdDetailActions.value.length) {
            state.cmdDetailIdx.value = (state.cmdDetailIdx.value + 1) % state.cmdDetailActions.value.length;
          }
          return;
        }
        if (e.key === 'ArrowUp') {
          e.preventDefault();
          if (state.cmdDetailFields.value.length) {
            state.cmdDetailFocus.value = Math.max(state.cmdDetailFocus.value - 1, 0);
          } else if (state.cmdDetailActions.value.length) {
            state.cmdDetailIdx.value = (state.cmdDetailIdx.value - 1 + state.cmdDetailActions.value.length) % state.cmdDetailActions.value.length;
          }
          return;
        }
        if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
          e.preventDefault();
          const f = state.cmdDetailFields.value[state.cmdDetailFocus.value];
          if (f && (f.type === 'select' || f.type === 'radio') && f.options && f.options.length > 1) {
            const i = f.options.findIndex(o => o.value === state.cmdDetailValues.value[f.key]);
            const ni = (i + (e.key === 'ArrowRight' ? 1 : f.options.length - 1)) % f.options.length;
            state.cmdDetailValues.value[f.key] = f.options[ni].value;
          }
          return;
        }
        if (e.key === ' ') {
          e.preventDefault();
          const f = state.cmdDetailFields.value[state.cmdDetailFocus.value];
          if (f && f.type === 'checkbox') state.cmdDetailValues.value[f.key] = !state.cmdDetailValues.value[f.key];
          return;
        }
        if (e.key === 'Enter') {
          e.preventDefault();
          store.runCmdAction();
          return;
        }
        return;
      }

      // Detail Panel 模式：Esc/Tab 返回一级；↑↓/Enter 在动作内导航
      if (state.detailOpen.value) {
        if (e.key === "Escape" || e.key === "Tab") {
          e.preventDefault();
          closeDetail();
          return;
        }
        if (e.key === "ArrowDown") {
          e.preventDefault();
          if (state.detailActions.value.length) { state.detailIdx.value = (state.detailIdx.value + 1) % state.detailActions.value.length; }
          return;
        }
        if (e.key === "ArrowUp") {
          e.preventDefault();
          if (state.detailActions.value.length) {
            state.detailIdx.value = (state.detailIdx.value - 1 + state.detailActions.value.length) % state.detailActions.value.length;
          }
          return;
        }
        if (e.key === "Enter") {
          e.preventDefault();
          store.runAction(state.detailIdx.value);
          return;
        }
        return;   // Detail 模式下其它键不处理
      }

      // 网格模式（home=快捷命令 / apps=应用组）：←→↑↓ 网格导航 + Enter 执行/进详情
      if (!state.terms.value) {
        if (e.key === 'ArrowDown') { e.preventDefault(); if (gridItems.value.length) { state.selected.value = gridMove(0, 1); scrollGrid(); } return; }
        if (e.key === 'ArrowUp') { e.preventDefault(); if (gridItems.value.length) { state.selected.value = gridMove(0, -1); scrollGrid(); } return; }
        if (e.key === 'ArrowRight') { e.preventDefault(); if (gridItems.value.length) { state.selected.value = gridMove(1, 0); scrollGrid(); } return; }
        if (e.key === 'ArrowLeft') { e.preventDefault(); if (gridItems.value.length) { state.selected.value = gridMove(-1, 0); scrollGrid(); } return; }
        if (e.key === 'Enter') {
          e.preventDefault();
          const g = gridItems.value[state.selected.value];
          if (g) {
            if (state.mode.value === 'home') openGridCard(g);
            else openAppsCard(g);
          }
          return;
        }
        if (e.key === 'Tab') {
          e.preventDefault();
          const g = gridItems.value[state.selected.value];
          if (!g) return;
          if (e.shiftKey) { if (g.row.type === 'launchOrFocus') openDetail(g.row); return; }
          tabInject(g.row);
          return;
        }
        if (e.key === 'Escape') {
          e.preventDefault();
          // 应用组 → 回主页网格；主页 → 关闭面板
          if (state.mode.value === 'apps') gotoHome();
          else store.closePanel();
          return;
        }
        return;   // 网格模式下其它键不处理
      }

      // 列表模式
      if (e.key === "Tab") {
        e.preventDefault();
        const it = state.items.value[state.selected.value];
        if (!it) return;
        if (e.shiftKey) { if (it.type === "launchOrFocus") openDetail(it); return; }
        tabInject(it);
        return;
      } else if (e.key === "ArrowDown") {
        e.preventDefault();
        if (state.items.value.length) { state.selected.value = (state.selected.value + 1) % state.items.value.length; scrollToSelected(); }
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        if (state.items.value.length) {
          state.selected.value = (state.selected.value - 1 + state.items.value.length) % state.items.value.length;
          scrollToSelected();
        }
      } else if (e.key === "Enter") {
        e.preventDefault();
        const it = state.items.value[state.selected.value];
        // 配置页卡：Enter 直接打开子页面（与网格模式一致）
        if (it && it.type === "cardPage") { openPage(it); return; }
        store.run(state.selected.value);
      } else if (e.key === "Escape") {
        e.preventDefault();
        if (state.cmdDetailOpen.value) { closeCmdDetail(); }
        else if (state.terms.value) { state.query.value = ''; onInput(); }
        else store.closePanel();
      }
    }

    function pick(idx) {   // 鼠标点击
      // Detail 打开时点击一级列表：关闭 Detail 并选中该行（不误触动作）
      if (state.detailOpen.value) { closeDetail(); state.selected.value = idx; return; }
      const it = state.items.value[idx];
      // 配置页卡：点击直接打开子页面
      if (it && it.type === "cardPage") { openPage(it); return; }
      store.run(idx);
    }

    // ===== Tab 注入应用搜索 =====
    function tabInject(row) {
      if (!row) return;
      if (row.searchUrl) {
        store.injectApp({ name: row.text, icon: row.icon || null, searchUrl: row.searchUrl });
        // 注入后清空输入：开始应用内搜索（uTools 一致）
        state.query.value = '';
        state.terms.value = '';
        return;
      }
      toast('「' + row.text + '」不支持搜索');
    }
    function removeInject() {
      store.removeInject();
    }
    // 注入 iframe 就绪：挂引用（postMessage 目标）
    function onAppFrameLoad() {
      store.setAppFrame(document.getElementById('app-search-frame'));
    }
    // 注入 iframe 地址（追加 embed 标记：应用页隐藏自带输入框）
    const injectSrc = computed(function () {
      const a = state.injectedApp.value;
      if (!a) return '';
      return a.searchUrl + (a.searchUrl.indexOf('?') >= 0 ? '&' : '?') + 'embed=1';
    });
    function toast(msg) {
      if (window.UiToast && window.UiToast.show) window.UiToast.show(msg, { type: 'error' });
      else console.warn('[Launcher]', msg);
    }

    // ===== 网格移动/滚动 =====
    function gridMove(dc, dr) {
      const n = gridItems.value.length;
      if (n === 0) return state.selected.value;
      const c0 = state.selected.value % GRID_COLS;
      const r0 = Math.floor(state.selected.value / GRID_COLS);
      const lastR = Math.floor((n - 1) / GRID_COLS);
      if (dc !== 0) {
        let c = c0 + dc;
        if (c < 0) c = GRID_COLS - 1;
        if (c >= GRID_COLS) c = 0;
        const idx = r0 * GRID_COLS + c;
        return idx < n ? idx : (r0 * GRID_COLS + (n - 1) % GRID_COLS);
      }
      let r = r0 + dr;
      if (r < 0) r = lastR;
      if (r > lastR) r = 0;
      let c = c0;
      const rowEnd = Math.min(GRID_COLS, n - r * GRID_COLS);
      if (c >= rowEnd) c = rowEnd - 1;
      if (c < 0) c = 0;
      return r * GRID_COLS + c;
    }

    function scrollGrid() {
      const el = list.value;
      if (!el) return;
      const sel = el.querySelector('.ut-gcard.selected');
      if (sel) sel.scrollIntoView({ block: 'nearest' });
    }

    function scrollToSelected() {
      const el = list.value;
      if (!el) return;
      const sel = el.querySelector(".ut-row.selected");
      if (sel) sel.scrollIntoView({ block: "nearest" });
    }

    // ===== 图标装饰 =====
    function iconText(row) {
      if (row.plugin === "apps" && !row.image) {
        return (shortName(row.text)[0] || "?").toUpperCase();
      }
      return ICON_CHARS[row.plugin] || "·";
    }
    function iconStyle(row) {
      if (row.plugin === "apps" && !row.image) {
        const color = BADGE_COLORS[hashStr(row.text || "") % BADGE_COLORS.length];
        return { background: color, color: "#fff" };
      }
      return {};
    }
    function shortType(t) { return TYPE_SHORT[t] || t; }
    function shortName(t) { return String(t || "").replace(/\s+\(Running\)$/i, ""); }

    function focusInput() {
      const el = q.value;
      if (el && el.focus) { try { el.focus(); } catch (e) {} }
    }

    // 每次面板呼出时由后端 evaluateJavaScript 调用：清空输入 + 聚焦；
    // 视图回主页网格，保留上次选中位置（用户不需要重新选择）
    function reset() {
      store.resetState();
      closeCmdDetail();
      closeDetail();
      closePage();
      store.loadHome();
      focusInput();
    }
    // 暴露给后端 hs.webview:evaluateJavaScript("window.__launcherReset && window.__launcherReset()")
    window.__launcherReset = reset;

    onMounted(function() {
      focusInput();
      store.loadHome();
      // 玻璃光尘粒子（由 <!-- hsutil:fx glass --> 注入）：
      // 特效故障不应阻断面板挂载/使用，包 try/catch 兜底
      try {
        if (window.HSUI && HSUI.initGlassFX) HSUI.initGlassFX();
      } catch (e) {
        console.error('initGlassFX 失败', e);
      }
    });

    return { query: state.query, terms: state.terms, items: state.items,
             selected: state.selected, loading: state.loading, keyword: state.keyword,
             list, q, groups, gridItems, mode: state.mode, gotoApps, gotoHome, openGridCard, openAppsCard,
             detailOpen: state.detailOpen, detailTarget: state.detailTarget,
             detailActions: state.detailActions, detailIdx: state.detailIdx,
             cmdDetailOpen: state.cmdDetailOpen, cmdDetailTarget: state.cmdDetailTarget,
             cmdDetailActions: state.cmdDetailActions, cmdDetailIdx: state.cmdDetailIdx,
             cmdDetailFields: state.cmdDetailFields, cmdDetailValues: state.cmdDetailValues,
             cmdDetailFocus: state.cmdDetailFocus, cfgDisplay,
             pageOpen: state.pageOpen, pageSrc: state.pageSrc, openPage, closePage,
             onInput, onKey, run: store.run, runAction: store.runAction, pick, closeDetail,
             openCmdDetail, closeCmdDetail, runCmdAction: store.runCmdAction,
             scrollGrid, gridMove,
             iconText, iconStyle, shortType, shortName,
             injectedApp: state.injectedApp,
             injectSrc, tabInject, removeInject, onAppFrameLoad };
  },
}).use(LauncherStore).mount("#app");

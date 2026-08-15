/**
 * Bing 壁纸搜索页 — Vue3 UI 层（对齐 Clipboard history：搜索栏 + 卡片列表）
 * 浏览最近 N 天壁纸，点击/Enter 直接应用（下载 + 设壁纸）。
 * Tab 注入：launcher 以 ?embed=1 打开并 postMessage {type:'query',text}/{type:'key',key}。
 */
const { createApp, ref, computed, onMounted, inject } = Vue;

createApp({
  setup() {
    const store = inject('bingSearchStore');
    const state = store.state;
    const list = ref(null);
    const q = ref(null);
    const thumbErr = ref(false);

    // 注入模式（?embed=1 = launcher iframe 内，隐藏搜索栏/状态栏）
    const isEmbed = new URLSearchParams(location.search).get('embed') === '1';

    // 过滤后的列表
    const filtered = computed(function () {
      return state.filteredRows(state);
    });

    function fmtDate(d) {
      if (!d) return '';
      return d.slice(0, 4) + '-' + d.slice(4, 6) + '-' + d.slice(6, 8);
    }

    function onQuery() { state.selected.value = 0; }

    function apply(i) { store.apply(i); }

    function scrollSelected() {
      const el = list.value;
      if (!el) return;
      const sel = el.querySelector('.wall-card.selected');
      if (sel) sel.scrollIntoView({ block: 'nearest' });
    }

    function move(d) {
      const n = filtered.value.length;
      if (n === 0) return;
      state.selected.value = (state.selected.value + d + n) % n;
      scrollSelected();
    }

    function onKey(e) {
      if (e.key === 'Escape') {
        e.preventDefault();
        // embed 模式 Esc 归 launcher（移除注入）
        if (isEmbed) { try { window.parent.postMessage({ type: 'escape' }, '*'); } catch (err) {} return; }
        return;
      }
      if (e.key === 'ArrowDown') { e.preventDefault(); move(1); return; }
      if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); return; }
      if (e.key === 'Enter') { e.preventDefault(); apply(state.selected.value); return; }
    }

    // Launcher Tab 注入
    window.addEventListener('message', function (e) {
      const d = e.data || {};
      if (d.type === 'query') { state.query.value = d.text || ''; state.selected.value = 0; return; }
      if (d.type === 'key') {
        if (d.key === 'ArrowDown') move(1);
        else if (d.key === 'ArrowUp') move(-1);
        else if (d.key === 'Enter') apply(state.selected.value);
      }
    });

    onMounted(function () {
      store.load().then(function () {
        // 加载后补当前壁纸状态（status 接口）
        fetch('/bingdaily/api/status').then(function (r) { return r.json(); })
          .then(function (d) { if (d && d.last_pic) state.currentName.value = d.last_pic; })
          .catch(function () {});
      });
      const el = q.value;
      if (el && el.focus && !isEmbed) { try { el.focus(); } catch (e) {} }
    });

    return { query: state.query, filtered, selected: state.selected,
             loading: state.loading, applying: state.applying, currentName: state.currentName,
             isEmbed, list, q, thumbErr,
             fmtDate, onQuery, apply, onKey };
  },
}).use(BingSearchStore).mount("#app");

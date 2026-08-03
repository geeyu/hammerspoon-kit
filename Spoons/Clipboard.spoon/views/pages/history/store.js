// ===== views/pages/history/store.js —— 页面级状态（provide/inject）=====
// 数据层：列表/分页/搜索/删除/星标/确认的 fetch 全在这里，UI（选中/动画/键盘）在 app.js。
// 注意：本文件必须在 app.js 之前引入（defer 顺序），
// const 是全局词法绑定、不挂 window，不能用 if (window.ClipStore) 做安装守卫。

// ===== HTTP 客户端（同源 fetch，页面本身就在 http://127.0.0.1:8821 加载）=====
// 数据接口走相对路径 /clipboard/api/*，无需写 host/port
function apiUrl(p) { return '/clipboard/api' + p; }
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(apiUrl(p), opts).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  });
}

var PAGE = 20;

const ClipStore = {
  install(app) {
    const state = Vue.reactive({
      items: [],
      total: 0,
      hasMore: false,
      loading: false,
      term: '',        // 当前搜索词（'' = 全量）
    });

    // 在途请求中止句柄（list/more 共用：新请求顶掉旧请求）
    let abortCtrl = null;
    const newAbort = function () {
      if (abortCtrl) abortCtrl.abort();
      abortCtrl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
      return abortCtrl ? { signal: abortCtrl.signal } : {};
    };

    // 条目装饰：时间文本/类型细分/预览截断/图片延迟加载 URL（幂等）
    const decorate = function (it) {
      if (it.__dec) return it;
      it.__dec = true;
      it.timeText = ClipFormat.timeText(it.created);
      var raw = String(it.text || '');
      it.subKind = ClipFormat.detectSubKind(raw, it.kind);
      if (it.subKind === 'image') {
        it.preview = '';
        // 真·延迟加载：列表接口不下发 data URI（text 为空），
        // 这里构造按需拉图 URL，配合 <img loading="lazy"> 只请求视口内图片
        it.imgUrl = apiUrl('/history/' + it.id + '/image');
      } else {
        it.preview = raw.length > 200 ? raw.slice(0, 200) + '…' : raw;
      }
      return it;
    };

    const actions = {
      // 搜索/分页拉取（term 为空串 = 全量）。返回 Promise，完成后 state 已更新
      // @param showLoading boolean 是否显示加载态（仅空列表→首次/清空搜索时）
      list(term, showLoading) {
        term = (term || '').trim();
        state.term = term;
        state.hasMore = false;
        if (showLoading) state.loading = true;
        const opts = newAbort();
        const q = encodeURIComponent(term);
        return hsFetch('/history?term=' + q + '&offset=0&limit=' + PAGE, opts)
          .then(function (d) {
            state.items = (d.rows || []).map(decorate);
            state.total = d.total || 0;
            state.hasMore = state.items.length < state.total;
          })
          .catch(function (e) {
            if (e && e.name === 'AbortError') return;   // 忽略主动中止
            console.error('[Clipboard] list:', e);
          })
          .then(function () { state.loading = false; });
      },

      // 翻页追加。返回 Promise
      more() {
        if (state.loading || !state.hasMore) return Promise.resolve();
        state.loading = true;
        const opts = newAbort();
        const q = encodeURIComponent(state.term);
        return hsFetch('/history?term=' + q + '&offset=' + state.items.length + '&limit=' + PAGE, opts)
          .then(function (d) {
            state.items = state.items.concat((d.rows || []).map(decorate));
            state.total = d.total || 0;
            state.hasMore = state.items.length < state.total;
          })
          .catch(function (e) {
            if (e && e.name === 'AbortError') return;
            console.error('[Clipboard] more:', e);
          })
          .then(function () { state.loading = false; });
      },

      // 静默刷新：不清空列表、不显示 loading（隐藏期间执行，呼出时用户无感知）
      silentRefresh() {
        const q = encodeURIComponent(state.term);
        return hsFetch('/history?term=' + q + '&offset=0&limit=' + PAGE)
          .then(function (d) {
            state.items = (d.rows || []).map(decorate);
            state.total = d.total || 0;
            state.hasMore = state.items.length < state.total;
          })
          .catch(function (e) { console.error('[Clipboard] silentRefresh:', e); });
      },

      // 删除（服务端）。本地移除由 removeLocal 做（配合退场动画）
      remove(id) {
        return hsFetch('/history/' + id, { method: 'DELETE' });
      },
      // 本地移除（动画完成后调用）
      removeLocal(i) {
        state.items.splice(i, 1);
        state.total = Math.max(0, state.total - 1);
      },

      // 星标置顶（服务端）。返回 {ok, starred}；本地翻转由调用方做（即时反馈）
      toggleStar(id, nv) {
        return hsFetch('/history/' + id + '/star', { method: 'POST', body: '{}' });
      },

      // 确认粘贴（选中条目）
      confirm(id) {
        // 带 body 避免 hs.httpserver 对空 POST 返回 400
        return hsFetch('/history/' + id + '/confirm', { method: 'POST', body: '{}' });
      },

      // 关闭面板（Esc / 前端调用）
      close() {
        return hsFetch('/close', { method: 'POST', body: '{}' });
      },
    };

    app.provide('clipStore', { state, ...actions });
  },
};

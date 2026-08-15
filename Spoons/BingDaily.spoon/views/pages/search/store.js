// ===== views/pages/search/store.js —— 壁纸列表数据层 =====
// 对齐 Clipboard history：GET /archive 列表；POST /apply 应用；embed 注入（query/key）。
const BASE = "/bingdaily/api";
// 轻量提示：优先命令式 UiToast（占位符注入），否则 console 兜底
function toast(msg, opts) {
  if (window.UiToast && window.UiToast.show)
    window.UiToast.show(msg, opts || {});
  else console.warn("[BingDaily]", msg);
}
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(BASE + p, opts).then((r) => {
    if (!r.ok)
      return r.json().then((d) => {
        throw new Error((d && d.err) || "HTTP " + r.status);
      });
    return r.json();
  });
}

const BingSearchStore = {
  install(app) {
    const state = {
      rows: Vue.ref([]), // 归档壁纸
      query: Vue.ref(""), // 过滤词（Tab 注入也写这里）
      selected: Vue.ref(0),
      loading: Vue.ref(false),
      applying: Vue.ref(""), // 正在应用的文件名
      currentName: Vue.ref(""), // 当前壁纸文件名
    };

    const actions = {
      load() {
        state.loading.value = true;
        return hsFetch("/archive")
          .then((d) => {
            state.rows.value = d.rows || [];
            state.loading.value = false;
            clampSelected();
            // 后端缓存 miss（cached=false）：后台拉取中，稍后自动刷新一次
            if (d.cached === false) {
              setTimeout(() => actions.load(), 2500);
            }
          })
          .catch(() => {
            state.loading.value = false;
          });
      },
      apply(idx) {
        const it = filteredRows(state);
        const row = it[idx];
        if (!row || state.applying.value) return;
        state.applying.value = row.name;
        return hsFetch("/apply", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          // 带 date/copyright：后端下载历史记录用
          body: JSON.stringify({
            name: row.name,
            url: row.url,
            date: row.date,
            copyright: row.copyright,
          }),
        })
          .then(() => {
            state.currentName.value = row.name;
            // 下载在后台进行（立即响应），状态提示保留 2 秒
            setTimeout(() => {
              state.applying.value = "";
            }, 2000);
          })
          .catch((e) => {
            state.applying.value = "";
            toast("应用失败: " + e.message, { type: "error" });
          });
      },
    };

    // 过滤逻辑（store 与 app 共享）
    function filteredRows(state) {
      const kw = state.query.value.trim().toLowerCase();
      if (!kw) return state.rows.value;
      return state.rows.value.filter(
        (it) =>
          (it.name || "").toLowerCase().indexOf(kw) !== -1 ||
          (it.date || "").indexOf(kw) !== -1 ||
          (it.copyright || "").toLowerCase().indexOf(kw) !== -1,
      );
    }
    state.filteredRows = filteredRows;

    function clampSelected() {
      const n = filteredRows(state).length;
      if (state.selected.value >= n) {
        state.selected.value = Math.max(0, n - 1);
      }
    }

    app.provide("bingSearchStore", { state, ...actions });
  },
};

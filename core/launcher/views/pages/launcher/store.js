// ===== views/pages/launcher/store.js —— 页面级状态（provide/inject）=====
// 数据层：query/run/close 的 fetch 与页面状态全在这里，UI（键盘/动画/选中）在 app.js。
// 注意：本文件必须在 app.js 之前引入（defer 顺序）。

// ===== HTTP 客户端（同源 fetch，页面本身就在 http://127.0.0.1:8821 加载）=====
const BASE = "/launcher/api";
function apiUrl(p) { return BASE + p; }
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(apiUrl(p), opts).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  });
}

const LauncherStore = {
  install(app) {
    // 页面状态（refs 对象：模板绑定与 v-model 直接可用，app.js 经 state.xxx 访问）
    const state = {
      query: Vue.ref(""),
      terms: Vue.ref(""),       // 已提交搜索词（'' = 网格/首页模式）
      items: Vue.ref([]),       // 扁平 rows（含 section）
      selected: Vue.ref(0),     // 选中 index
      loading: Vue.ref(false),
      keyword: Vue.ref(null),

      // Detail Panel（应用二级操作）
      detailOpen: Vue.ref(false),
      detailTarget: Vue.ref(null),
      detailActions: Vue.ref([]),
      detailIdx: Vue.ref(0),

      // 视图模式（去 Tab 后）：'home' = 快捷命令网格 | 'apps' = 应用组网格（terms 非空即列表模式）
      mode: Vue.ref('home'),

      // 命令详情面板（config schema）
      cmdDetailOpen: Vue.ref(false),
      cmdDetailTarget: Vue.ref(null),
      cmdDetailActions: Vue.ref([]),
      cmdDetailIdx: Vue.ref(0),
      cmdDetailFields: Vue.ref([]),   // schema 数组
      cmdDetailValues: Vue.ref({}),   // 当前值表
      cmdDetailFocus: Vue.ref(0),     // 聚焦字段索引

      // 子页面（iframe，kind="page" 卡片打开任意 spoon 的 view）
      pageOpen: Vue.ref(false),
      pageSrc: Vue.ref(''),

      // 应用搜索注入（Tab Inject）：{name, icon, searchUrl}
      injectedApp: Vue.ref(null),
    };

    // 应用搜索注入 iframe 引用（app.js 挂载后设置）
    let appFrame = null;
    function setAppFrame(el) { appFrame = el; }

    // 搜索防抖 + 过期响应守卫（install 闭包）
    let _timer = null;
    let _seq = 0;

    const actions = {
      // GET /query（text 为空返回分组首页）
      fetchQuery(text) {
        return hsFetch('/query?text=' + encodeURIComponent(text || ""));
      },

      // 空输入：加载分组首页（最近使用 + 快捷命令）
      loadHome() {
        clearTimeout(_timer);
        state.loading.value = true;
        const mySeq = ++_seq;
        actions.fetchQuery("").then(function (data) {
          if (mySeq !== _seq) return;
          state.items.value = data.rows || [];
          // 保持上次选中位置（越界则收敛到最后一项）
          if (state.selected.value >= state.items.value.length) {
            state.selected.value = Math.max(0, state.items.value.length - 1);
          }
          state.keyword.value = null;
          state.loading.value = false;
        }).catch(function () { state.loading.value = false; });
      },

      // 输入防抖查询：调用方（onInput）置 loading=true，本函数在回调结束（成功或失败）后置 false
      search(text) {
        clearTimeout(_timer);
        _timer = setTimeout(function () {
          const mySeq = ++_seq;
          actions.fetchQuery(text).then(function (data) {
            if (mySeq !== _seq) return;   // 丢弃过期的并发响应
            state.items.value = data.rows || [];
            state.keyword.value = data.keyword || null;
            state.selected.value = 0;
            state.loading.value = false;
          }).catch(function () { state.loading.value = false; });
        }, 100);   // config.debounce_ms
      },

      // 执行一级候选（按扁平列表 idx），执行后关闭面板
      run(idx) {
        const it = state.items.value[idx];
        if (!it) return Promise.resolve();
        return hsFetch('/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ row: { id: it.id } }),
        }).catch(function (err) { console.error("run 失败", err); })
          .then(function () { actions.closePanel(); });
      },

      // 执行 Detail 动作（id + action，后端 runner 映射），执行后关闭面板
      runAction(idx) {
        const act = state.detailActions.value && state.detailActions.value[idx];
        const tgt = state.detailTarget.value;
        if (!act || !tgt) return Promise.resolve();
        return hsFetch('/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ row: { id: tgt.id, action: act.action } }),
        }).catch(function (err) { console.error("Detail 执行失败", err); })
          .then(function () { actions.closePanel(); });
      },

      // 命令详情执行：有 schema 提交 config；无 schema 老路径提交 subKind，执行后关闭面板
      runCmdAction() {
        const tgt = state.cmdDetailTarget.value;
        if (!tgt) return Promise.resolve();
        const body = { row: { id: tgt.id } };
        if (state.cmdDetailFields.value.length) {
          body.row.overrides = { config: Object.assign({}, state.cmdDetailValues.value) };
        } else {
          const act = state.cmdDetailActions.value[state.cmdDetailIdx.value];
          if (act && act.subKind) body.row.overrides = { subKind: act.subKind };
        }
        return hsFetch('/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        }).catch(function (err) { console.error('命令详情执行失败', err); })
          .then(function () { actions.closePanel(); });
      },

      // 注入应用搜索（Tab）：chip 显示 + 结果区切 iframe
      injectApp(app) {
        state.injectedApp.value = app;
        state.items.value = [];
        state.loading.value = false;
      },
      // 移除注入，回全局搜索（输入内容保留，重新走全局查询）
      removeInject() {
        if (!state.injectedApp.value) return;
        state.injectedApp.value = null;
        clearTimeout(_timer);
        const q = state.query.value;
        if (q) { actions.search(q); } else { actions.loadHome(); }
      },
      // 转发消息到应用搜索 iframe（query 输入 / key 键盘）
      sendToApp(msg) {
        if (appFrame && appFrame.contentWindow) {
          appFrame.contentWindow.postMessage(msg, '*');
        }
      },

      // 关闭面板：记住选中位置（localStorage 兜底）+ 通知后端
      closePanel() {
        try {
          localStorage.setItem('launcher.state',
            JSON.stringify({ selected: state.selected.value }));
        } catch (err) { /* 忽略 */ }
        try {
          hsFetch('/close', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
            .catch(function () { /* 忽略 */ });
        } catch (err) { /* 忽略 */ }
      },

      // 读取上次关闭时保存的选中位置（无记录时默认 0；视图模式每次从主页开始）
      loadState() {
        try {
          const s = JSON.parse(localStorage.getItem('launcher.state') || '{}');
          return { mode: 'home', selected: s.selected || 0 };
        } catch (err) { return { mode: 'home', selected: 0 }; }
      },

      // 复位（reset 调用）：清输入/结果/关键词/loading + 回主页网格
      resetState() {
        clearTimeout(_timer);
        _seq = 0;
        state.query.value = "";
        state.items.value = [];
        state.terms.value = "";
        state.keyword.value = null;
        state.injectedApp.value = null;   // 面板复位：清注入
        const saved = actions.loadState();
        state.mode.value = saved.mode;
        state.selected.value = saved.selected;
      },
    };

    app.provide('launcherStore', { state: state, ...actions, setAppFrame: setAppFrame });
  },
};

// ===== HomeStore —— 首页状态（provide/inject）=====
// 注意：本文件必须在 app.js 之前引入（defer 顺序），app.js 中直接 app.use(HomeStore)；
// const 是全局词法绑定、不挂 window，不能用 if (window.HomeStore) 做安装守卫。
const HomeStore = {
  install(app) {
    const state = Vue.reactive({
      items: [],
      loading: false,
      lastRefresh: 0,
    });

    const actions = {
      async load() {
        state.loading = true;
        try {
          const r = await fetch('/api/tool/items');
          const d = await r.json();
          state.items = d.items || [];
          state.lastRefresh = Date.now();
        } finally {
          state.loading = false;
        }
      },
      setItems(items) { state.items = items; },
    };

    app.provide('homeStore', { state, ...actions });
  },
};

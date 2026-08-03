// ===== SettingsStore —— 设置页状态（provide/inject）=====
// 注意：本文件必须在 app.js 之前引入（defer 顺序），app.js 中直接 app.use(SettingsStore)；
// const 是全局词法绑定、不挂 window，不能用 if (window.SettingsStore) 做安装守卫。
const SettingsStore = {
  install(app) {
    const state = Vue.reactive({
      settings: { name: '', theme: 'light', notify: true },
      saved: false,
    });

    const actions = {
      save(patch) {
        Object.assign(state.settings, patch || {});
        state.saved = true;
      },
      setSettings(patch) { Object.assign(state.settings, patch || {}); },
    };

    app.provide('settingsStore', { state, ...actions });
  },
};

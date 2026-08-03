// ===== views/pages/settings/store.js —— 数据层（provide/inject）=====
// 配置：每动作 启用开关 + 热键（GET/POST /quantumwindow/api/config；改动即保存）。
// UI（渲染/交互/toast/冲突校验）在 app.js。
// 注意：本文件必须在 app.js 之前引入（defer 顺序）。
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(p, opts).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  });
}

const QwStore = {
  install(app) {
    const state = {
      actions: Vue.ref([]),     // [{key, group, label, desc, enabled, hotkey}]
      saving: Vue.ref(false),   // 防连点（保存中忽略新请求，UI 上值已就绪）
    };

    const actions = {
      load() {
        return hsFetch('/quantumwindow/api/config')
          .then(function (d) { state.actions.value = d.actions || []; })
          .catch(function (e) { console.error('[QuantumWindow] config:', e); throw e; });
      },

      // 全量提交（幂等）：{actions: {key: {enabled, hotkey}}}
      save() {
        if (state.saving.value) return Promise.resolve();
        state.saving.value = true;
        const payload = {};
        state.actions.value.forEach(function (a) {
          payload[a.key] = { enabled: !!a.enabled, hotkey: a.hotkey || '' };
        });
        return hsFetch('/quantumwindow/api/config', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ actions: payload }),
        }).then(function () { state.saving.value = false; })
          .catch(function (e) { state.saving.value = false; throw e; });
      },
    };

    app.provide('qwStore', { state, ...actions });
  },
};

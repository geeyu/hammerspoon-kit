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
      dirty: Vue.ref(false),    // 保存进行中又有新变更 → 完成后自动补一次提交
    };
    let chain = Promise.resolve();   // 保存链：串行化，避免并发 POST 乱序覆盖

    const actions = {
      load() {
        return hsFetch('/quantumwindow/api/config')
          .then(function (d) { state.actions.value = d.actions || []; })
          .catch(function (e) { console.error('[QuantumWindow] config:', e); throw e; });
      },

      // 全量提交（幂等）：{actions: {key: {enabled, hotkey}}}
      // 保存中的新变更不再静默丢弃：dirty 置位，当前保存完成后自动补一次全量提交
      // （全量幂等，补提交即最终一致；旧实现直接忽略新变更 → 服务器与页面显示不一致）
      save() {
        if (state.saving.value) {
          state.dirty.value = true;
          return chain;
        }
        state.saving.value = true;
        const payload = {};
        state.actions.value.forEach(function (a) {
          payload[a.key] = { enabled: !!a.enabled, hotkey: a.hotkey || '' };
        });
        const p = hsFetch('/quantumwindow/api/config', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ actions: payload }),
        }).then(function () { state.saving.value = false; })
          .catch(function (e) { state.saving.value = false; throw e; });
        chain = p.then(function () {
          if (state.dirty.value) {
            state.dirty.value = false;
            return actions.save();
          }
        });
        return chain;
      },
    };

    app.provide('qwStore', { state, ...actions });
  },
};

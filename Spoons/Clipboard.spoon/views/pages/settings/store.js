// ===== views/pages/settings/store.js —— 设置页状态（provide/inject）=====
// 数据层：GET/POST /clipboard/api/settings；前后端格式转换在此（后端 {mods,key} ↔ 前端 "ctrl+shift+v"）。
// 注意：本文件必须在 app.js 之前引入（defer 顺序）。

// ===== 热键编码/解码（后端 {mods,key} ↔ 前端 "mods+key" 字符串）=====
// 后端格式：[mods数组, key]（0-based，如 [{"ctrl"}, "v"]）
function hotkeyEncode(hk) {
  if (!hk || !hk[0] || !hk[1]) return '';
  return hk[0].join('+') + '+' + hk[1];
}
function hotkeyDecode(s) {
  if (!s) return null;
  var parts = String(s).split('+');
  var key = parts.pop();
  if (!key) return null;
  // 数组格式 {mods 数组, key}，与后端 sanitizeHotkey 一致
  return [parts, key];
}

const SettingsStore = {
  install(app) {
    const state = Vue.reactive({
      form: {            // 表单模型（前端格式）
        hotkey: '',
        retainDays: 7,
        maxEntries: 300,
        recordImages: true,
        panelWidth: 52,     // 面板宽占目标屏幕比例（%）
        panelHeight: 62,    // 面板高占目标屏幕比例（%）
        panelPos: 22,       // 面板垂直位置（0=贴顶，50=居中，%）
      },
      loaded: false,
    });

    const actions = {
      // 拉取当前配置 → 填充表单
      load() {
        return fetch('/clipboard/api/settings').then((r) => {
          if (!r.ok) throw new Error('HTTP ' + r.status);
          return r.json();
        }).then((s) => {
          state.form.hotkey = hotkeyEncode(s.hotkey_show);
          state.form.retainDays = s.retain_days;
          state.form.maxEntries = s.max_entries;
          state.form.recordImages = !s.text_only;
          var p = s.panel || {};
          state.form.panelWidth = Math.round((p.widthRatio || 0.52) * 100);
          state.form.panelHeight = Math.round((p.heightRatio || 0.62) * 100);
          state.form.panelPos = Math.round((p.yRatio || 0.22) * 100);
          state.loaded = true;
        });
      },
      // 保存（转后端格式 + POST）
      save() {
        const payload = {
          hotkey_show: hotkeyDecode(state.form.hotkey),
          retain_days: state.form.retainDays,
          max_entries: Number(state.form.maxEntries) || 300,
          text_only: !state.form.recordImages,
          panel: {
            widthRatio: (Number(state.form.panelWidth) || 52) / 100,
            heightRatio: (Number(state.form.panelHeight) || 62) / 100,
            yRatio: (Number(state.form.panelPos) || 22) / 100,
          },
        };
        return fetch('/clipboard/api/settings', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }).then((r) => r.json().then((d) => {
            if (!r.ok) throw new Error(d.err || ('HTTP ' + r.status));
            return d;
          }));
      },
    };

    app.provide('settingsStore', { state, ...actions });
  },
};

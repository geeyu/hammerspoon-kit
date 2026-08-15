// ===== views/pages/apps/store.js —— 应用显隐管理数据层 =====
const BASE = "/apptoggle/api";
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(BASE + p, opts).then((r) => {
    if (!r.ok) return r.json().then((d) => { throw new Error((d && d.err) || ('HTTP ' + r.status)); });
    return r.json();
  });
}

const AppToggleStore = {
  install(app) {
    const state = {
      apps: Vue.ref([]),          // 应用列表（含运行状态/布局数）
      editorOpen: Vue.ref(false),
      editor: Vue.ref(null),      // 编辑中的草稿
      saving: Vue.ref(false),
    };

    // 后端应用行 → 编辑器草稿
    function toDraft(a) {
      return {
        id: a ? a.id : null,
        name: a ? a.name : '',
        bundle_id: a ? a.bundle_id : '',
        hotkeyStr: a ? (a.mods || []).join('+') + '+' + (a.key || '') : '',
        on_no_window: a ? (a.on_no_window || 'launch') : 'launch',
        fullscreen_fallback: a ? a.fullscreen_fallback : true,
        restore_focus: a ? a.restore_focus : true,
        move_to_mouse_screen: a ? a.move_to_mouse_screen : true,
      };
    }

    const actions = {
      load() {
        return hsFetch('/apps').then((d) => {
          state.apps.value = d.apps || [];
        }).catch((e) => {
          console.error('加载应用列表失败', e);
          throw e;
        });
      },

      openEditor(a) {
        state.editor.value = toDraft(a);
        state.editorOpen.value = true;
      },

      // hotkeyStr 形如 "ctrl+alt+t" → {mods: ['ctrl','alt'], key: 't'}
      parseHotkey(s) {
        if (!s) return null;
        const parts = String(s).split('+');
        const key = (parts.pop() || '').trim();
        const mods = parts.map((m) => m.trim()).filter(Boolean);
        if (!key || mods.length === 0) return null;
        return { mods: mods, key: key };
      },

      // ui-hotkey 组件回调：更新草稿 hotkeyStr
      onHotkey(val) {
        if (state.editor.value) state.editor.value.hotkeyStr = val || '';
      },

      saveEditor() {
        const ed = state.editor.value;
        if (!ed) return Promise.resolve();
        const hk = actions.parseHotkey(ed.hotkeyStr);
        if (!hk) {
          alert('热键格式无效：需为 修饰键+主键，如 ctrl+alt+t');
          return Promise.resolve();
        }
        if (!ed.name.trim()) { alert('名称不能为空'); return Promise.resolve(); }
        if (!ed.bundle_id.trim()) { alert('Bundle ID 不能为空'); return Promise.resolve(); }
        state.saving.value = true;
        return hsFetch('/apps', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: ed.name.trim(),
            bundle_id: ed.bundle_id.trim(),
            mods: hk.mods,
            key: hk.key,
            on_no_window: ed.on_no_window,
            fullscreen_fallback: ed.fullscreen_fallback,
            restore_focus: ed.restore_focus,
            move_to_mouse_screen: ed.move_to_mouse_screen,
          }),
        }).then(() => {
          state.editorOpen.value = false;
          return actions.load();
        }).catch((e) => {
          alert('保存失败: ' + e.message);
          throw e;
        }).finally(() => {
          state.saving.value = false;
        });
      },

      remove(a) {
        return hsFetch('/apps/' + a.id, { method: 'DELETE' }).then(() => actions.load()).catch((e) => {
          alert('删除失败: ' + e.message);
          throw e;
        });
      },

      press(a) {
        return hsFetch('/apps/' + a.id + '/press', { method: 'POST' }).then(() => {
          // 稍后刷新运行状态（显隐有 100ms 级异步）
          setTimeout(actions.load, 500);
        }).catch((e) => {
          alert('触发失败: ' + e.message);
        });
      },

      clearLayouts(a) {
        return hsFetch('/apps/' + a.id + '/clear-layouts', { method: 'POST' }).then(() => actions.load()).catch((e) => {
          alert('清除失败: ' + e.message);
        });
      },

      fmtHotkey(a) {
        if (!a || !a.key) return '';
        const label = (p) => {
          const map = { cmd: '⌘', ctrl: '⌃', alt: '⌥', shift: '⇧' };
          return map[p] || p;
        };
        const mods = (a.mods || []).map(label).join('');
        const key = a.key.length === 1 ? a.key.toUpperCase() : a.key;
        return mods + key;
      },
    };

    app.provide('appToggleStore', { state, ...actions });
  },
};

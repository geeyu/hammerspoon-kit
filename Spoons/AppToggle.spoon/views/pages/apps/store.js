// ===== views/pages/apps/store.js —— 应用显隐管理数据层 =====
const BASE = "/apptoggle/api";
// 轻量提示：优先命令式 UiToast（占位符注入），否则 console 兜底
function toast(msg, opts) {
  if (window.UiToast && window.UiToast.show)
    window.UiToast.show(msg, opts || {});
  else console.warn("[AppToggle]", msg);
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

const AppToggleStore = {
  install(app) {
    const state = {
      apps: Vue.ref([]), // 应用列表（含运行状态/布局数）
      editorOpen: Vue.ref(false),
      editor: Vue.ref(null), // 编辑中的草稿
      saving: Vue.ref(false),
      runningApps: Vue.ref([]), // 运行中的应用（添加时下拉选择）
    };

    // 后端应用行 → 编辑器草稿
    function toDraft(a) {
      return {
        id: a ? a.id : null,
        name: a ? a.name : "",
        bundle_id: a ? a.bundle_id : "",
        hotkeyStr: a ? (a.mods || []).join("+") + "+" + (a.key || "") : "",
        on_no_window: a ? a.on_no_window || "launch" : "launch",
        fullscreen_fallback: a ? a.fullscreen_fallback : true,
        restore_focus: a ? a.restore_focus : true,
        move_to_mouse_screen: a ? a.move_to_mouse_screen : true,
        selectedApp: "", // 新增时下拉选中值（bundle_id）
      };
    }

    const actions = {
      load() {
        return hsFetch("/apps")
          .then((d) => {
            state.apps.value = d.apps || [];
          })
          .catch((e) => {
            console.error("加载应用列表失败", e);
            throw e;
          });
      },

      openEditor(a) {
        state.editor.value = toDraft(a);
        state.editorOpen.value = true; // 先开弹窗（不阻塞动画）
        // 运行应用列表后端已缓存（毫秒级）：打开弹窗时重拉一次保持新鲜
        actions.loadRunningApps().catch(() => {});
      },

      // 运行中的应用（{name, bundle_id}；后端已用 .app 目录名=中文名）
      // 后端为纯缓存读取（后台定期分批刷新）：查询零阻塞；
      // 缓存未就绪时返回空列表，1.5s 后自动补拉一次
      loadRunningApps() {
        return hsFetch("/running-apps")
          .then((d) => {
            const list = (d.apps || []).map((app) => ({
              value: app.bundle_id,
              label: app.name + "  (" + app.bundle_id + ")",
              name: app.name,
              bundle_id: app.bundle_id,
            }));
            const hadEmpty =
              state.runningApps.value.length === 0 && list.length === 0;
            state.runningApps.value = list;
            // 后端后台收集中返回空：1.5s 后补拉（距上次补拉 >3s，防循环）
            if (
              hadEmpty &&
              Date.now() - (state._lastRunningRetry || 0) > 3000
            ) {
              state._lastRunningRetry = Date.now();
              setTimeout(() => actions.loadRunningApps(), 1500);
            }
          })
          .catch((e) => console.error("加载运行应用失败", e));
      },

      // 下拉选择应用：自动填名称 + Bundle ID
      onSelectApp(bundleId) {
        const ed = state.editor.value;
        if (!ed || !bundleId) return;
        const found = state.runningApps.value.find((a) => a.value === bundleId);
        if (found) {
          ed.name = found.name;
          ed.bundle_id = found.bundle_id;
        }
      },

      // hotkeyStr 形如 "ctrl+alt+t" → {mods: ['ctrl','alt'], key: 't'}
      // F1-F12 等功能键允许无修饰键（"F1" → {mods: [], key: 'F1'}）
      parseHotkey(s) {
        if (!s) return null;
        const parts = String(s).split("+");
        const key = (parts.pop() || "").trim();
        const mods = parts.map((m) => m.trim()).filter(Boolean);
        const isFnKey = /^F1?[0-9]$/.test(key) || /^F1[0-2]$/.test(key);
        if (!key) return null;
        if (mods.length === 0 && !isFnKey) return null;
        return { mods: mods, key: key };
      },

      // ui-hotkey 组件回调：更新草稿 hotkeyStr
      onHotkey(val) {
        if (state.editor.value) state.editor.value.hotkeyStr = val || "";
      },

      saveEditor() {
        const ed = state.editor.value;
        if (!ed) return Promise.resolve();
        const hk = actions.parseHotkey(ed.hotkeyStr);
        if (!hk) {
          toast(
            "热键格式无效：需为 修饰键+主键（如 ctrl+alt+t），或 F1-F12 功能键",
            { type: "error" },
          );
          return Promise.resolve();
        }
        if (!ed.name.trim()) {
          toast("名称不能为空", { type: "error" });
          return Promise.resolve();
        }
        if (!ed.bundle_id.trim()) {
          toast("Bundle ID 不能为空", { type: "error" });
          return Promise.resolve();
        }
        state.saving.value = true;
        return hsFetch("/apps", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
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
        })
          .then(() => {
            state.editorOpen.value = false;
            return actions.load();
          })
          .catch((e) => {
            toast("保存失败: " + e.message, { type: "error" });
            throw e;
          })
          .finally(() => {
            state.saving.value = false;
          });
      },

      remove(a) {
        return hsFetch("/apps/" + a.id, { method: "DELETE" })
          .then(() => actions.load())
          .catch((e) => {
            toast("删除失败: " + e.message, { type: "error" });
            throw e;
          });
      },

      press(a) {
        // 带 body 避免 hs.httpserver 对无 Content-Length 的 POST 返回 400（WKWebView 下 fetch 无法保证）
        return hsFetch("/apps/" + a.id + "/press", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        })
          .then(() => {
            // 稍后刷新运行状态（显隐有 100ms 级异步）
            setTimeout(actions.load, 500);
          })
          .catch((e) => {
            toast("触发失败: " + e.message, { type: "error" });
          });
      },

      clearLayouts(a) {
        // 带 body 避免 hs.httpserver 对无 Content-Length 的 POST 返回 400（WKWebView 下 fetch 无法保证）
        return hsFetch("/apps/" + a.id + "/clear-layouts", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        })
          .then(() => actions.load())
          .catch((e) => {
            toast("清除失败: " + e.message, { type: "error" });
          });
      },

      fmtHotkey(a) {
        if (!a || !a.key) return "";
        const label = (p) => {
          const map = { cmd: "⌘", ctrl: "⌃", alt: "⌥", shift: "⇧" };
          return map[p] || p;
        };
        const mods = (a.mods || []).map(label).join("");
        const key = a.key.length === 1 ? a.key.toUpperCase() : a.key;
        return mods + key;
      },
    };

    app.provide("appToggleStore", { state, ...actions });
  },
};

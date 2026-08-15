/**
 * 应用显隐管理页 — Vue3 UI 层
 * 列表 + 编辑弹窗（ui-modal + 运行应用下拉选择 + ui-hotkey remote 录制）。
 */
const { createApp, onMounted, inject } = Vue;

createApp({
  setup() {
    const store = inject("appToggleStore");
    const state = store.state;

    const noWindowOptions = [
      { label: "启动应用（未运行时自动打开）", value: "launch" },
      { label: "仅激活（未运行则不做任何事）", value: "activate" },
    ];

    function openEditor(a) {
      store.openEditor(a);
    }

    function onHotkey(val) {
      store.onHotkey(val);
    }

    function onSelectApp() {
      store.onSelectApp();
    }

    function saveEditor() {
      store.saveEditor();
    }

    function remove(a) {
      if (!confirm("删除「" + a.name + "」的显隐绑定？")) return;
      store.remove(a);
    }

    function press(a) {
      store.press(a);
    }

    function clearLayouts(a) {
      if (!confirm("清除「" + a.name + "」在全部屏幕的锁定布局？")) return;
      store.clearLayouts(a);
    }

    // 返回：iframe 内关 launcher 子页面（回主页）；独立打开时 history.back
    function goBack() {
      try {
        if (
          window.self !== window.top &&
          window.parent &&
          window.parent.closePage
        ) {
          window.parent.closePage();
          return;
        }
      } catch (e) {}
      history.back();
    }

    onMounted(() => {
      store.load().catch(() => {});
    });

    return {
      apps: state.apps,
      editorOpen: state.editorOpen,
      editor: state.editor,
      saving: state.saving,
      appOptions: state.runningApps,
      noWindowOptions,
      openEditor,
      onHotkey,
      onSelectApp,
      saveEditor,
      remove,
      press,
      clearLayouts,
      goBack,
      fmtHotkey: store.fmtHotkey,
    };
  },
})
  .use(AppToggleStore)
  .mount("#app");

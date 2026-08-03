/**
 * QuantumWindow 配置页 — Vue3 UI 层
 * 防睡眠设置页风格：每个功能一行（左标签右控件），行内 启用开关 + 热键录制
 * （ui-hotkey remote：录制期间后端 eventtap 吞键，系统快捷键不触发）。
 * 改动即保存：拨开关/录完键立即 POST；快捷键冲突拦截并回滚该项。
 * 数据层在 store.js。
 */
const { createApp, onMounted, inject } = Vue;

createApp({
  setup() {
    const store = inject('qwStore');
    const state = store.state;

    // 最近一次保存成功的快照（key → {enabled, hotkey}），冲突回滚用
    let lastSaved = {};

    function toast(msg, isErr) {
      const type = isErr ? 'error' : 'success';
      if (window.UiToast && window.UiToast.show) {
        window.UiToast.show(msg, { type: type });
      } else {
        console.warn('[QuantumWindow] UiToast 不可用:', msg);
      }
    }

    // 冲突校验：同一快捷键被多个「启用中」功能使用 → 返回 [先者, 后者]
    function findConflict() {
      const map = {};
      for (const a of state.actions.value) {
        if (!a.enabled || !a.hotkey) continue;
        if (map[a.hotkey]) return [map[a.hotkey], a];
        map[a.hotkey] = a;
      }
      return null;
    }

    // 改动即保存：先落值再校验（冲突拦截并回滚刚改的那项）；成功则更新快照
    function onChange(a, field, val) {
      a[field] = val;
      const dup = findConflict();
      if (dup) {
        // 始终回滚刚改的动作（findConflict 返回的是数组序的先后者，不一定是被改的那个）
        const prev = lastSaved[a.key] || {};
        if (prev[field] !== undefined) a[field] = prev[field];
        const other = (dup[0] === a) ? dup[1] : dup[0];
        toast('快捷键冲突：「' + a.label + '」与「' + other.label + '」相同', true);
        return;
      }
      store.save().then(function () {
        const snap = {};
        state.actions.value.forEach(function (x) {
          snap[x.key] = { enabled: !!x.enabled, hotkey: x.hotkey || '' };
        });
        lastSaved = snap;
        toast('已保存');
      }).catch(function (e) {
        toast('保存失败: ' + e.message, true);
      });
    }

    // 返回：launcher 子页面协议优先，独立打开时回退
    function goBack() {
      try {
        if (window.self !== window.top && window.parent && window.parent.closePage) {
          window.parent.closePage();
          return;
        }
      } catch (e) {}
      history.back();
    }
    // Backspace 快速返回 launcher（输入框有内容时正常删字，不拦截）
    window.addEventListener('keydown', function (e) {
      if (e.key !== 'Backspace') return;
      const t = e.target;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA') && t.value) return;
      e.preventDefault();
      goBack();
    });

    onMounted(function () {
      store.load().then(function () {
        const snap = {};
        state.actions.value.forEach(function (x) {
          snap[x.key] = { enabled: !!x.enabled, hotkey: x.hotkey || '' };
        });
        lastSaved = snap;
      }).catch(function () { toast('配置加载失败', true); });
    });

    return { actions: state.actions, onChange, goBack };
  },
}).use(QwStore).mount("#app");

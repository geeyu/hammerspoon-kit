// ===== views/pages/control/store.js —— 页面级状态（provide/inject）=====
// 数据层：/stayawake/api/state + /stayawake/api/action 的 fetch 与倒计时 tick。
// UI（渲染/交互/toast）在 app.js。
// 注意：本文件必须在 app.js 之前引入（defer 顺序）。
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(p, opts).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  });
}

const StayAwakeStore = {
  install(app) {
    // 页面状态
    const state = {
      status: Vue.ref(null),    // 后端状态 {active, type, mode, remaining, endsAt}
      remaining: Vue.ref(0),    // 本地倒计时显示的剩余秒数（每秒递减）
      loading: Vue.ref(false),
    };

    // 本地倒计时（install 闭包）
    let countdownTimer = null;
    let baseTs = 0;

    const actions = {
      // 拉取后端状态并启动本地倒计时
      loadState() {
        state.loading.value = true;
        return hsFetch('/stayawake/api/state')
          .then(function (d) {
            state.status.value = d;
            state.remaining.value = (d && d.active && d.remaining != null) ? d.remaining : 0;
            actions.startCountdown();
          })
          .catch(function (e) { console.error('[StayAwake] state:', e); throw e; })
          .then(function () { state.loading.value = false; });
      },

      // 本地每秒递减剩余时间（避免频繁请求）；到期自动重拉真实状态
      startCountdown() {
        actions.stopCountdown();
        const s = state.status.value;
        if (!s || !s.active || s.remaining == null) return;
        baseTs = Date.now();
        countdownTimer = setInterval(function () {
          state.remaining.value = s.remaining - Math.floor((Date.now() - baseTs) / 1000);
          if (state.remaining.value <= 0) {
            actions.stopCountdown();
            actions.loadState();
          }
        }, 1000);
      },
      stopCountdown() {
        if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
      },

      // 执行动作（permanent/timer/until/mode/close），成功后刷新状态
      action(name, params) {
        return hsFetch('/stayawake/api/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(Object.assign({ action: name }, params || {})),
        }).then(function (d) {
          if (d.ok) {
            return actions.loadState().catch(function () {}).then(function () { return d; });
          }
          return d;
        });
      },
    };

    app.provide('stayAwakeStore', { state, ...actions });
  },
};

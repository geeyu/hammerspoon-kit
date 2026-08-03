/**
 * StayAwake — 防睡眠控制页 UI 层
 * 设置行式布局（对齐 Clipboard 设置页）：左标签右控件。
 * 交互：先选后启——小时/分钟/永久/直到 只做选择（互斥），底部动态按钮统一启动/停止；
 * 启动成功后全部配置重置（不保留状态）。数据层在 store.js。
 */
const { createApp, ref, computed, watch, inject } = Vue;

const app = createApp({
  setup() {
    const store = inject('stayAwakeStore');
    const state = store.state;

    // ===== 配置选择（互斥：同时只有一个生效）=====
    const hourVal = ref('');
    const minuteVal = ref('');
    const foreverVal = ref('');
    const untilVal = ref('');
    const modeVal = ref('');
    let lastAppliedMode = null;   // 防抖：loadState 回填时不重复提交

    // ===== 选项 =====
    const modeOptions = [
      { label: '允许息屏（系统不休眠）', value: 'system' },
      { label: '屏幕常亮', value: 'all' },
    ];
    const hourOptions = [];
    for (let h = 1; h <= 24; h++) hourOptions.push({ label: h + ' 小时', value: String(h) });
    const minuteOptions = [5, 10, 15, 30, 45, 60, 90].map(function (m) {
      return { label: m + ' 分钟', value: String(m) };
    });
    const foreverOptions = [{ label: '永久保持清醒', value: 'forever' }];

    // 互斥：新选择清掉其他三个
    watch(hourVal, function (v) { if (v) { minuteVal.value = ''; foreverVal.value = ''; untilVal.value = ''; } });
    watch(minuteVal, function (v) { if (v) { hourVal.value = ''; foreverVal.value = ''; untilVal.value = ''; } });
    watch(foreverVal, function (v) { if (v) { hourVal.value = ''; minuteVal.value = ''; untilVal.value = ''; } });
    watch(untilVal, function (v) { if (v) { hourVal.value = ''; minuteVal.value = ''; foreverVal.value = ''; } });

    // ===== 状态卡 =====
    function fmtDur(sec) {
      sec = Math.max(0, Math.floor(sec));
      const h = Math.floor(sec / 3600);
      const m = Math.floor((sec % 3600) / 60);
      const s = sec % 60;
      return h > 0
        ? h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0')
        : m + ':' + String(s).padStart(2, '0');
    }
    const active = computed(() => !!(state.status.value && state.status.value.active));
    // 配置已修改（选了新时长/时间）且当前激活中 → 底部按钮变「重置」
    const configDirty = computed(function () {
      return !!(hourVal.value || minuteVal.value || foreverVal.value || untilVal.value);
    });
    const statusText = computed(() => {
      const s = state.status.value;
      if (!s) return '加载中…';
      if (!s.active) return '系统正常睡眠';
      if (s.type === 'permanent') return '保持清醒中（无限期）';
      return '保持清醒中（剩余 ' + fmtDur(state.remaining.value) + '）';
    });
    const modeText = computed(() => {
      const s = state.status.value;
      if (!s) return '';
      return s.mode === 'all' ? '屏幕常亮' : '允许息屏';
    });
    const endsAtText = computed(() => {
      const s = state.status.value;
      if (!s || !s.active) return '';
      if (s.type === 'permanent') return '无限期';
      return s.endsAt || '';
    });

    function toast(msg, isErr) {
      const type = isErr ? 'error' : 'success';
      if (window.UiToast && window.UiToast.show) {
        window.UiToast.show(msg, { type: type });
      } else {
        console.warn('[StayAwake] UiToast 不可用:', msg);
      }
    }

    // ===== 动作 =====
    function run(actionName, params, okMsg) {
      return store.action(actionName, params).then(function (d) {
        if (!d.ok) { toast(d.msg || '操作失败', true); return false; }
        if (okMsg) toast(okMsg);
        return true;
      }).catch(function () { toast('请求失败', true); return false; });
    }

    // 模式 radio：选中即生效（loadState 回填用 lastAppliedMode 跳过）
    watch(modeVal, function (v) {
      if (!v || v === lastAppliedMode) return;
      lastAppliedMode = v;
      run('mode', { mode: v }, v === 'all' ? '已切换：屏幕常亮' : '已切换：允许息屏');
    });

    // 底部「启动」：按当前选中配置生效，成功后全部重置（不保留状态）
    function startSelected() {
      let name = null, params = {};
      if (hourVal.value) { name = 'timer'; params = { minutes: parseInt(hourVal.value, 10) * 60 }; }
      else if (minuteVal.value) { name = 'timer'; params = { minutes: parseInt(minuteVal.value, 10) }; }
      else if (foreverVal.value) { name = 'permanent'; params = {}; }
      else if (untilVal.value) { name = 'until'; params = { endsAt: untilVal.value }; }
      if (!name) { toast('请先选择时长或时间点', true); return; }
      run(name, params).then(function (ok) { if (ok) resetConfig(); });
    }
    function resetConfig() {
      hourVal.value = '';
      minuteVal.value = '';
      foreverVal.value = '';
      untilVal.value = '';
    }

    // 直到时间点：选完即选中（互斥清理由 watch 完成），点底部「启动」生效

    function closeAll() {
      run('close', {}, '已关闭防睡眠');
    }

    // ===== 返回 launcher（子页面协议：parent.closePage()）=====
    function goBack() {
      store.stopCountdown();   // v-show 下 iframe 不销毁，先停掉倒计时 timer
      if (window.parent && window.parent.closePage) window.parent.closePage();
      else if (window.parent && window.parent.closeStayAwake) window.parent.closeStayAwake();
    }

    // Backspace 快速返回 launcher（输入框有内容时正常删字，不拦截）
    window.addEventListener('keydown', function (e) {
      if (e.key !== 'Backspace') return;
      const t = e.target;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA') && t.value) return;
      e.preventDefault();
      goBack();
    });

    // 首屏加载状态；成功后将后端 mode 回填 radio（不触发 watch 提交）
    store.loadState().then(function () {
      const s = state.status.value;
      if (s && s.mode) { lastAppliedMode = s.mode; modeVal.value = s.mode; }
    }).catch(function () { toast('状态加载失败', true); });

    return { state, hourVal, minuteVal, foreverVal, untilVal, modeVal,
             modeOptions, hourOptions, minuteOptions, foreverOptions,
             active, configDirty, statusText, modeText, endsAtText,
             startSelected, closeAll, goBack };
  },
});
// ui 组件由 hsutil 注册表统一自动注册（components/ui/index.js patch Vue.createApp），页面无需手动接入
app.use(StayAwakeStore).mount('#app');

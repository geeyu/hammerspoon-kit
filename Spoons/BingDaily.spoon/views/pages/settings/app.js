/**
 * Bing 壁纸设置页 — Vue3 UI 层
 * 状态卡 + 一键执行区 + 设置行（间隔/保存位置/归档/自动应用/范围/通知）+ 下载历史
 */
const { createApp, onMounted, inject } = Vue;

const HOUR_OPTIONS = [1, 3, 6, 12, 24].map((h) => ({
  label: "每 " + h + " 小时",
  value: h,
}));
const SCREEN_OPTIONS = [
  { label: "仅主屏", value: "main" },
  { label: "全部屏幕", value: "all" },
];

createApp({
  setup() {
    const store = inject("bingSettingsStore");
    const state = store.state;

    const hourOptions = HOUR_OPTIONS;
    const screenOptions = SCREEN_OPTIONS;

    const statusText = Vue.computed(() => {
      const s = state.status.value.status || "idle";
      if (s === "fetching") return "正在拉取今日壁纸…";
      if (s === "error") return "拉取失败，请检查网络";
      if (s === "ok") return "运行中";
      return "等待首次拉取";
    });
    const fmtTime = (t) => {
      if (!t) return "-";
      const d = new Date(t * 1000);
      const p = (n) => (n < 10 ? "0" + n : "" + n);
      return (
        d.getFullYear() +
        "-" +
        p(d.getMonth() + 1) +
        "-" +
        p(d.getDate()) +
        " " +
        p(d.getHours()) +
        ":" +
        p(d.getMinutes())
      );
    };
    const fmtDate = (d) => {
      if (!d) return "-";
      return (
        String(d).slice(0, 4) +
        "-" +
        String(d).slice(4, 6) +
        "-" +
        String(d).slice(6, 8)
      );
    };

    // 轻量提示：优先命令式 UiToast（占位符注入），否则 console 兜底
    function toast(msg, opts) {
      if (window.UiToast && window.UiToast.show)
        window.UiToast.show(msg, opts || {});
      else console.warn("[BingDaily]", msg);
    }

    function save() {
      store.save().catch((e) => {
        toast("保存失败: " + e.message, { type: "error" });
      });
    }

    // 一键执行（store 内处理 busy/loading 与错误提示）
    function refresh() {
      store.refresh();
    }
    function applyToday() {
      store.applyToday();
    }
    function applyRandom() {
      store.applyRandom();
    }
    function openDir() {
      store.openDir();
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
      store.load();
      // 玻璃光尘特效（fx 占位符已注入 anime/glass-fx）
      try {
        if (window.HSUI && HSUI.initGlassFX) HSUI.initGlassFX();
      } catch (e) {}
    });

    return {
      form: state.form,
      saved: state.saved,
      status: state.status,
      busy: state.busy,
      downloads: state.downloads,
      hourOptions,
      screenOptions,
      statusText,
      fmtTime,
      fmtDate,
      load: store.load,
      save,
      refresh,
      applyToday,
      applyRandom,
      openDir,
      goBack,
    };
  },
})
  .use(BingSettingsStore)
  .mount("#app");

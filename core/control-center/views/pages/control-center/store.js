// ===== views/pages/control-center/store.js —— 页面级状态（provide/inject）=====
// 数据层：GET /control-center/api/providers（提供者列表）+ POST /control-center/api/open
// （打开配置面板）的 fetch 与页面状态全在这里；UI（卡片渲染/状态切换）在 app.js。
// 注意：本文件必须在 app.js 之前引入（defer 顺序）。

// ===== HTTP 客户端（同源 fetch，页面本身就在 http://127.0.0.1:8821 加载）=====
const BASE = "/control-center/api";
function apiUrl(p) {
  return BASE + p;
}
function hsFetch(p, opts) {
  opts = opts || {};
  return fetch(apiUrl(p), opts).then((r) => {
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.json();
  });
}

// 轻量提示：优先命令式 UiToast（占位符注入），否则 console 兜底（不阻断流程）
function toast(msg) {
  if (window.UiToast && window.UiToast.show)
    window.UiToast.show(msg, { type: "error" });
  else console.warn("[ControlCenter]", msg);
}

const ControlCenterStore = {
  install(app) {
    // 页面状态（refs 对象：模板绑定与 v-model 直接可用，app.js 经 state.xxx 访问）
    const state = {
      providers: Vue.ref([]), // 提供者列表 [{name, icon?, cards[], pages[]}]
      loading: Vue.ref(false), // 列表加载中
      error: Vue.ref(""), // 加载失败信息（'' = 无错）
      opening: Vue.ref(""), // 正在打开配置面板的提供者名（防重复点击）
      activeUrl: Vue.ref(""), // 当前打开的配置页 URL（iframe 模式；'' = 首页）
    };

    // 过期响应守卫（install 闭包：任何新请求的序号必然大于全部在途旧请求）
    let _seq = 0;

    const actions = {
      // GET /providers：提供者列表（卡片网格数据源，api.lua 已剔除非可序列化字段）
      fetchProviders() {
        return hsFetch("/providers");
      },

      // POST /open：panel.open(url) 打开配置面板（url 校验与 pcall 容错在服务端）
      openUrl(url) {
        return hsFetch("/open", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ url: url }),
        });
      },

      // 提供者配置入口 URL（与 menubar.lua 同一优先级，前端独立实现）：
      //   ① 首个配置页 pages[].configUrl
      //   ② 无 pages 时取首个 page 卡 url（kind === 'page'）
      //   ③ 兜底任意带 url 的卡片（openurl 卡）
      // 全无 → ''（调用方提示不可打开）
      providerUrl(p) {
        if (!p) return "";
        const pages = p.pages || [];
        for (let i = 0; i < pages.length; i++) {
          if (pages[i].configUrl) return pages[i].configUrl;
        }
        const cards = p.cards || [];
        for (let i = 0; i < cards.length; i++) {
          if (cards[i].kind === "page" && cards[i].url) return cards[i].url;
        }
        for (let i = 0; i < cards.length; i++) {
          if (cards[i].url) return cards[i].url;
        }
        return "";
      },

      // 加载提供者列表（成功清空错误；失败置 error 供失败态渲染）
      load() {
        state.loading.value = true;
        state.error.value = "";
        const mySeq = ++_seq;
        actions
          .fetchProviders()
          .then((data) => {
            if (mySeq !== _seq) return; // 丢弃过期的并发响应
            state.providers.value = data.providers || [];
            state.loading.value = false;
          })
          .catch((err) => {
            if (mySeq !== _seq) return;
            state.loading.value = false;
            state.error.value = "无法连接控制中心服务";
            console.error("加载提供者列表失败", err);
          });
      },

      // 点击卡片：iframe 内打开该提供者的首个配置页（聚合页常驻，
      // 返回 = 隐藏 iframe 立即回首页，零延迟不重载）
      openProvider(p) {
        if (!p || state.opening.value) return; // 打开中防重复点击
        const url = actions.providerUrl(p);
        if (!url) {
          toast("「" + p.name + "」没有可打开的配置页");
          return;
        }
        state.opening.value = p.name;
        state.activeUrl.value = url;
        state.opening.value = "";
      },

      // 返回首页（配置页内调 parent.closePage() → 这里）
      closePage() {
        state.activeUrl.value = "";
      },
    };

    app.provide("controlCenterStore", { state: state, ...actions });
  },
};

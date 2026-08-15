// 前端 store.js 逻辑功能验证（node 环境，mock Vue/fetch）
// 覆盖：providerUrl 选择（configUrl → page 卡 url → 任意卡 url → ''）、
//       load() GET /providers、openProvider() POST /open 的 url 正确性
const fs = require("fs");
const vm = require("vm");

let pass = 0,
  fail = 0;
function check(name, cond, detail) {
  if (cond) {
    console.log("  [PASS] " + name);
    pass++;
  } else {
    console.log("  [FAIL] " + name + (detail ? "  (" + detail + ")" : ""));
    fail++;
  }
}

// ---- mock Vue ----
const ref = (v) => ({ value: v });
const VueMock = { ref };

// ---- 记录 fetch 调用 ----
const calls = [];
let fetchImpl = null;
function mockFetch(fn) {
  fetchImpl = fn;
}

const sandbox = {
  Vue: VueMock,
  window: {},
  console,
  fetch: (url, opts) => {
    calls.push({ url, opts });
    return fetchImpl(url, opts);
  },
};
vm.createContext(sandbox);
vm.runInContext(
  fs.readFileSync(
    "core/control-center/views/pages/control-center/store.js",
    "utf8",
  ) + "\n;this.__storeExport = ControlCenterStore;",
  sandbox,
);
const ControlCenterStore = sandbox.__storeExport;

let provided = {};
ControlCenterStore.install({
  provide: (k, v) => {
    provided = v;
  },
});
const actions = provided;

// ---- providerUrl ----
const p1 = {
  name: "a",
  pages: [{ name: "x", configUrl: "/a/view/pages/x/index.html" }],
  cards: [],
};
check(
  "configUrl 优先",
  actions.providerUrl(p1) === "/a/view/pages/x/index.html",
);

const p2 = {
  name: "b",
  pages: [{ name: "x" }],
  cards: [{ key: "k", kind: "page", url: "/b/view/pages/y/index.html" }],
};
check(
  "无 configUrl 取 page 卡 url",
  actions.providerUrl(p2) === "/b/view/pages/y/index.html",
);

const p3 = {
  name: "c",
  pages: [],
  cards: [{ key: "k", kind: "openurl", url: "https://x" }],
};
check("兜底任意卡 url", actions.providerUrl(p3) === "https://x");

const p4 = { name: "d", pages: [], cards: [] };
check("全无返回空串", actions.providerUrl(p4) === "");

// ---- load(): GET /providers ----
calls.length = 0;
mockFetch(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ providers: [{ name: "e" }] }),
  }),
);
actions.load();
setTimeout(() => {
  check(
    "load GET 路径",
    calls.length === 1 && calls[0].url === "/control-center/api/providers",
  );
  check(
    "load 填充 providers",
    actions.state.providers.value.length === 1 &&
      actions.state.providers.value[0].name === "e",
  );
  check("load 清除 error", actions.state.error.value === "");
  check("load 关闭 loading", actions.state.loading.value === false);

  // ---- load() 失败 → error ----
  calls.length = 0;
  mockFetch(() => Promise.reject(new Error("boom")));
  actions.load();
  setTimeout(() => {
    check("load 失败置 error", actions.state.error.value !== "");

    // ---- openProvider(): iframe 模式——设置 activeUrl 不发 POST ----
    calls.length = 0;
    const p5 = {
      name: "f",
      pages: [{ name: "cfg", configUrl: "/f/view/pages/cfg/index.html" }],
      cards: [],
    };
    actions.openProvider(p5);
    check(
      "open 设 activeUrl(iframe)",
      actions.state.activeUrl.value === "/f/view/pages/cfg/index.html",
    );
    check("open 不发请求", calls.length === 0);
    check("open 清空 opening", actions.state.opening.value === "");

    // ---- closePage(): 清空 activeUrl 回首页 ----
    actions.closePage();
    check("closePage 回首页", actions.state.activeUrl.value === "");

    // ---- openProvider(): 无可打开 url → toast，不发请求 ----
    const toasts = [];
    sandbox.window.UiToast = { show: (m) => toasts.push(m) };
    calls.length = 0;
    actions.openProvider({ name: "g", pages: [], cards: [] });
    check("无 url 不发请求", calls.length === 0);
    check("无 url toast 提示", toasts.length === 1);

    // ---- 重复打开不同页：activeUrl 切换 ----
    actions.openProvider({
      name: "h",
      pages: [{ name: "c", configUrl: "/h/c" }],
    });
    check("切换配置页", actions.state.activeUrl.value === "/h/c");

    console.log(
      "== store.js 功能验证: " + pass + " PASS / " + fail + " FAIL ==",
    );
    process.exit(fail === 0 ? 0 : 1);
  }, 20);
});

// ===== views/pages/settings/store.js —— 设置页状态（provide/inject）=====
// 对齐 Clipboard settings：GET/POST /bingdaily/api/settings；状态/一键执行走 /status /refresh
// /apply-today /random /open-dir /downloads。

const BASE = "/bingdaily/api";
function hsFetch(p, opts) {
  opts = opts || {};
  // POST 无 body 时显式带 Content-Length: 0（hs.httpserver 对无 Content-Length
  // 的 POST 会直接 400 “Method expects request body”）
  if (opts.method === "POST" && !opts.body) {
    opts.headers = Object.assign({ "Content-Length": "0" }, opts.headers || {});
  }
  return fetch(BASE + p, opts).then((r) => {
    if (!r.ok)
      return r.json().then((d) => {
        throw new Error((d && d.err) || "HTTP " + r.status);
      });
    return r.json();
  });
}

const BingSettingsStore = {
  install(app) {
    const state = {
      form: Vue.reactive({
        intervalHours: 3,
        saveDir: "",
        archiveDays: 7,
        autoApply: true,
        notifyEnabled: true,
        applyToScreens: "main",
      }),
      saved: Vue.ref(false),
      status: Vue.ref({ status: "idle", last_pic: "", updated_at: null }),
      busy: Vue.ref(""), // 一键执行中的动作标识（refresh/applyToday/random）
      downloads: Vue.ref([]), // 下载历史
    };

    const actions = {
      load() {
        return Promise.all([
          hsFetch("/settings"),
          hsFetch("/status"),
          hsFetch("/downloads"),
        ]).then((results) => {
          const s = results[0];
          state.form.intervalHours = s.interval_hours;
          state.form.saveDir = s.save_dir;
          state.form.archiveDays = s.archive_days;
          state.form.autoApply = s.auto_apply;
          state.form.notifyEnabled = s.notify_enabled;
          state.form.applyToScreens = s.apply_to_screens;
          state.status.value = results[1] || {};
          state.downloads.value = (results[2] && results[2].rows) || [];
        });
      },
      save() {
        state.saved.value = false;
        return hsFetch("/settings", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            interval_hours: state.form.intervalHours,
            save_dir: state.form.saveDir,
            archive_days: state.form.archiveDays,
            auto_apply: state.form.autoApply,
            notify_enabled: state.form.notifyEnabled,
            apply_to_screens: state.form.applyToScreens,
          }),
        }).then(() => {
          state.saved.value = true;
          setTimeout(() => {
            state.saved.value = false;
          }, 2000);
        });
      },

      // ---- 一键执行 ----
      refresh() {
        state.busy.value = "refresh";
        return hsFetch("/refresh", { method: "POST" })
          .then(() => actions.refreshStatus())
          .catch((e) => {
            alert("刷新失败: " + e.message);
          })
          .finally(() => {
            state.busy.value = "";
          });
      },
      applyToday() {
        state.busy.value = "applyToday";
        return hsFetch("/apply-today", { method: "POST" })
          .then((d) => {
            alert("已应用今日壁纸: " + (d.path || ""));
            return actions.refreshStatus();
          })
          .catch((e) => {
            alert("应用失败: " + e.message);
          })
          .finally(() => {
            state.busy.value = "";
          });
      },
      applyRandom() {
        state.busy.value = "random";
        return hsFetch("/random", { method: "POST" })
          .then((d) => {
            alert("已随机应用壁纸: " + (d.path || ""));
            return actions.refreshStatus();
          })
          .catch((e) => {
            alert("随机应用失败: " + e.message);
          })
          .finally(() => {
            state.busy.value = "";
          });
      },
      openDir() {
        state.busy.value = "openDir";
        return hsFetch("/open-dir", { method: "POST" })
          .then((d) => {
            alert("已打开保存目录: " + (d.dir || ""));
          })
          .catch((e) => {
            alert("打开失败: " + e.message);
          })
          .finally(() => {
            state.busy.value = "";
          });
      },

      refreshStatus() {
        return hsFetch("/status")
          .then((d) => {
            state.status.value = d || {};
          })
          .catch(() => {});
      },
      loadDownloads() {
        return hsFetch("/downloads")
          .then((d) => {
            state.downloads.value = (d && d.rows) || [];
          })
          .catch(() => {});
      },
    };

    app.provide("bingSettingsStore", { state, ...actions });
  },
};

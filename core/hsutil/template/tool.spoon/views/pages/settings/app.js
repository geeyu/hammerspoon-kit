// views/pages/settings/app.js
var { createApp } = Vue;
var app = createApp({
  inject: ['settingsStore'],
  data: function () {
    return {
      fxOn: true,
      hello: {}
    };
  },
  computed: {
    settings: function () { return this.settingsStore.state.settings; }
  },
  mounted: function () {
    var self = this;
    // 页面级特效（glass-fx 已注入）
    if (window.HSUI && window.HSUI.initGlassFX) HSUI.initGlassFX();
    // 演示：hash 导航（<a href="#/home">）交给 ToolNav 处理
    window.addEventListener('hashchange', function () {
      var page = window.location.hash.replace(/^#\//, '');
      if (page) window.ToolNav.open(page);
    });
    // 服务端状态自 /api/tool/hello 而来
    fetch('/api/tool/hello').then(function (r) { return r.json(); })
      .then(function (d) { self.hello = d || {}; });
  },
  methods: {
    save: function () {
      this.settingsStore.save();
      UiToast.show('设置已保存', { type: 'success' });
    }
  }
});
app.use(SettingsStore);   // 页面级 store（store.js 必须在 app.js 之前引入，const 不挂 window）
registerUiComponents(app);
app.mount('#app');

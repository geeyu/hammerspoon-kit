// views/pages/settings/app.js —— 设置页逻辑（UI + 表单），数据层在 store.js
var { createApp } = Vue;
var app = createApp({
  inject: ['settingsStore'],
  data: function () {
    return {
      dayOptions: [
        { label: '3 天',  value: 3 },
        { label: '7 天',  value: 7 },
        { label: '14 天', value: 14 },
        { label: '30 天', value: 30 },
        { label: '90 天', value: 90 },
      ],
    };
  },
  computed: {
    form: function () { return this.settingsStore.state.form; },
  },
  methods: {
    // 返回：launcher 子页面协议优先（parent.closePage），独立打开时回历史页
    goBack: function () {
      if (window.parent && window.parent.closePage) { window.parent.closePage(); return; }
      window.location.href = '/clipboard/view/pages/history/index.html';
    },
    load: function () {
      var self = this;
      this.settingsStore.load()
        .catch(function (e) { console.error('[Clipboard] settings load:', e); });
    },
    save: function () {
      var self = this;
      this.settingsStore.save()
        .then(function (d) {
          UiToast.show('设置已保存', { type: 'success' });
        })
        .catch(function (e) {
          UiToast.show('保存失败: ' + e.message, { type: 'danger' });
        });
    },
  },
  mounted: function () {
    var self = this;
    // Backspace 快速返回 launcher（输入框有内容时正常删字，不拦截）
    window.addEventListener('keydown', function (e) {
      if (e.key !== 'Backspace') return;
      var t = e.target;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA') && t.value) return;
      e.preventDefault();
      self.goBack();
    });
    this.load();
  }
});

app.use(SettingsStore);
registerUiComponents(app);   // ui-hotkey 等公共组件自动注册
app.mount('#app');

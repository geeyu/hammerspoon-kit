// views/pages/home/app.js
var { createApp } = Vue;
var app = createApp({
  data: function () {
    return {
      fxOn: true,
      tab: 'overview',
      formSchema: [
        { key: 'name', label: '名称', type: 'text', placeholder: '输入名称' },
        { key: 'level', label: '级别', type: 'select', options: [{label:'低',value:'low'},{label:'高',value:'high'}] },
        { key: 'enabled', label: '启用', type: 'checkbox' }
      ],
      formValues: {},
      columns: [
        { key: 'id', label: 'ID', width: 60 },
        { key: 'name', label: '名称' },
        { key: 'status', label: '状态' }
      ],
      items: []
    };
  },
  mounted: function () {
    // 页面级特效（glass-fx 已注入）
    if (window.HSUI && window.HSUI.initGlassFX) HSUI.initGlassFX();
    this.loadItems();
  },
  methods: {
    loadItems: function () {
      var self = this;
      fetch('/api/tool/items').then(function (r) { return r.json(); })
        .then(function (d) { self.items = d.items || []; });
    },
    onSubmit: function (model) {
      UiToast.show('已提交: ' + JSON.stringify(model), { type: 'success' });
    },
    save: function () {
      UiToast.show('保存成功', { type: 'success' });
    },
    confirmReset: function () {
      var self = this;
      UiConfirm.show({ title: '确认', message: '确定要重置吗？', danger: true }).then(function (ok) {
        if (ok) { self.formValues = {}; UiToast.show('已重置'); }
      });
    }
  }
});
app.use(HomeStore);                        // 页面级 store（store.js 必须在 app.js 之前引入，const 不挂 window）
app.component('hello-card', HelloCard);    // 模板业务组件（全局变量，不走 registerUiComponents）
registerUiComponents(app);
app.mount('#app');

/* HSUtil UI 组件预览页逻辑。
   依赖：demo.html 占位符注入（vue → 组件 css/tpl/js(defer) → IconPark → glass-fx）。
   结构：Vue app → registerUiComponents → 演示数据 → glass 初始化。 */

var { createApp } = Vue;
var app = createApp({
  data: function () {
    return {
      /* 表单演示 */
      inputVal: 'HSUtil',
      selectVal: 'mid',
      switchVal: true,
      radioVal: 'b',
      selectOpts: [
        { label: '低', value: 'low' },
        { label: '中', value: 'mid' },
        { label: '高', value: 'high' }
      ],
      radioOpts: [
        { label: '选项 A', value: 'a' },
        { label: '选项 B', value: 'b' },
        { label: '选项 C', value: 'c' }
      ],
      formSchema: [
        { key: 'name', label: '名称', type: 'text', placeholder: '输入名称', required: true },
        { key: 'level', label: '级别', type: 'select', options: [{ label: '低', value: 'low' }, { label: '中', value: 'mid' }, { label: '高', value: 'high' }] },
        { key: 'enabled', label: '启用', type: 'checkbox' },
        { key: 'gender', label: '性别', type: 'radio', options: [{ label: '男', value: 'm' }, { label: '女', value: 'f' }] },
        { key: 'age', label: '年龄', type: 'number' },
        { key: 'remark', label: '备注', type: 'textarea' }
      ],
      formValues: { name: 'HSUtil', level: 'mid', enabled: true, gender: 'm', age: 18, remark: '' },

      /* 反馈演示 */
      modalOpen: false,
      drawerOpen: false,

      /* Tabs 演示 */
      tabsVal: 'overview',
      tabsList: [
        { label: '总览', value: 'overview', icon: 'layout-dashboard' },
        { label: '数据', value: 'data', icon: 'database' },
        { label: '设置', value: 'settings', icon: 'settings' }
      ],

      /* CRUD 演示（useCrud 本地数据） */
      page: 1,
      crudCols: [
        { key: 'id', label: 'ID', width: 64 },
        { key: 'name', label: '名称' },
        { key: 'role', label: '角色' },
        { key: 'status', label: '状态' },
        { key: 'actions', label: '操作', width: 80 }
      ],
      crudSeed: [
        { id: 1, name: 'Alpha', role: '管理员', status: 'success' },
        { id: 2, name: 'Beta', role: '编辑', status: 'warning' },
        { id: 3, name: 'Gamma', role: '访客', status: 'offline' },
        { id: 4, name: 'Delta', role: '编辑', status: 'success' }
      ],

      /* 图标演示 */
      iconNames: ['search', 'home', 'setting', 'plus', 'edit', 'refresh', 'inbox', 'check', 'copy', 'download', 'upload', 'folder', 'file-addition', 'save', 'close', 'down', 'right', 'user', 'bell-ring', 'alarm', 'calendar', 'delete', 'attention', 'info']
    };
  },
  computed: {
    crudItems: function () { return this.crud ? this.crud.items.value : []; }
  },
  created: function () {
    var self = this;
    /* useCrud：增删查改 + 内建 Confirm 删除确认 */
    this.crud = useCrud({
      load: function () { return Promise.resolve(self.crudSeed.map(function (r) { return Object.assign({}, r); })); },
      create: function (data) { self.crudSeed.push(data); return Promise.resolve(); },
      remove: function (item) {
        self.crudSeed = self.crudSeed.filter(function (r) { return r.id !== item.id; });
        return Promise.resolve();
      }
    });
    this.crud.load();
  },
  mounted: function () {
    /* 页面级特效（<!-- hsutil:fx glass --> 已注入 anime + glass-fx.js） */
    if (window.HSUI && window.HSUI.initGlassFX) HSUI.initGlassFX();
  },
  methods: {
    toast: function (text, type) {
      UiToast.show(text, { type: type || 'info' });
    },
    confirmDel: function () {
      var self = this;
      UiConfirm.show({
        title: '确认删除',
        message: '确定要删除这条记录吗？此操作不可撤销。',
        danger: true,
        okText: '删除',
        cancelText: '取消'
      }).then(function (ok) {
        if (ok) self.toast('已删除（演示）', 'success');
      });
    },
    onFormSubmit: function (model) {
      this.toast('表单提交：' + JSON.stringify(model), 'success');
    },
    onFormChange: function (key, value) {
      this.toast('字段变化：' + key + ' = ' + JSON.stringify(value), 'info');
    },
    crudAdd: function () {
      var nextId = Math.max.apply(null, this.crudSeed.map(function (r) { return r.id; })) + 1;
      this.crud.add({ id: nextId, name: 'New-' + nextId, role: '访客', status: 'info' }).then(function () {
        UiToast.show('已新增 New-' + nextId, { type: 'success' });
      });
    },
    crudDel: function (row) {
      this.crud.del(row).then(function (confirmed) {
        if (confirmed) UiToast.show('已删除 ' + row.name, { type: 'success' });
      });
    }
  }
});
registerUiComponents(app);
app.mount('#app');

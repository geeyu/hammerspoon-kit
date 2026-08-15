/* HSUtil UI 组件注册表
   用法：registerUiComponents(app) 一键注册所有已加载组件 */

var uiComponents = {
  'ui-button':      typeof UiButton === 'undefined'      ? null      : UiButton,
  'ui-badge':       typeof UiBadge === 'undefined'       ? null       : UiBadge,
  'ui-status-badge': typeof UiStatusBadge === 'undefined' ? null : UiStatusBadge,
  'ui-divider':     typeof UiDivider === 'undefined'     ? null     : UiDivider,
  'ui-avatar':      typeof UiAvatar === 'undefined'      ? null      : UiAvatar,
  'ui-empty':       typeof UiEmpty === 'undefined'       ? null       : UiEmpty,
  'ui-loading':     typeof UiLoading === 'undefined'     ? null     : UiLoading,
  'ui-input':       typeof UiInput === 'undefined'       ? null       : UiInput,
  'ui-hotkey':      typeof UiHotkey === 'undefined'      ? null      : UiHotkey,
  'ui-datetime':    typeof UiDatetime === 'undefined'    ? null    : UiDatetime,
  'ui-select':      typeof UiSelect === 'undefined'      ? null      : UiSelect,
  'ui-switch':      typeof UiSwitch === 'undefined'      ? null      : UiSwitch,
  'ui-radio-group': typeof UiRadio === 'undefined'       ? null       : UiRadio,
  'ui-form-field':  typeof UiFormField === 'undefined'   ? null   : UiFormField,
  'ui-form':        typeof UiForm === 'undefined'        ? null        : UiForm,
  'ui-modal':       typeof UiModal === 'undefined'       ? null       : UiModal,
  'ui-drawer':      typeof UiDrawer === 'undefined'      ? null      : UiDrawer,
  'ui-tabs':        typeof UiTabs === 'undefined'        ? null        : UiTabs,
  'ui-table':       typeof UiTable === 'undefined'       ? null       : UiTable,
  'ui-pagination':  typeof UiPagination === 'undefined'  ? null  : UiPagination,
  'ui-icon':        typeof UiIcon === 'undefined'          ? null        : UiIcon
};

function registerUiComponents(app) {
  for (var name in uiComponents) {
    if (Object.hasOwn(uiComponents, name) && uiComponents[name]) {
      app.component(name, uiComponents[name]);
    }
  }
  /* 命令式 API 挂到 globalProperties：Vue 运行时编译模板默认 prefixIdentifiers:true，
     模板表达式（@click="UiToast.show(...)" 等）中的自由变量会解析为 _ctx.X（组件实例），
     不挂 globalProperties 则 UiToast/UiConfirm 在模板里取不到（实例 has 陷阱命中后 get 为 undefined） */
  if (typeof UiToast !== 'undefined')   app.config.globalProperties.UiToast   = UiToast;
  if (typeof UiConfirm !== 'undefined') app.config.globalProperties.UiConfirm = UiConfirm;
  if (typeof useCrud !== 'undefined')   app.config.globalProperties.useCrud   = useCrud;
}

/* ===== 统一注册（框架级兑底，页面零配置）=====
   页面只需在 index.html 声明 <!-- hsutil:ui ... --> 占位符，本脚本随占位符注入后
   patch Vue.createApp：任何页面创建的 app 自动挂上 ui-* 组件与命令式 API，
   页面无需（也不应）再手动调用 registerUiComponents。
   历史页面中的显式 registerUiComponents(app) 调用保留为幂等兼容（重复注册无害）。
   此前依赖页面手动注册：漏调时组件未注册，Vue 将 <ui-*> 当原生元素静默渲染（无报错、不可交互）。 */
(function autoRegisterUi() {
  if (typeof Vue === 'undefined' || !Vue.createApp || Vue.createApp.__hsuiPatched) return;
  var rawCreateApp = Vue.createApp;
  function patchedCreateApp(rootComponent, rootProps) {
    var app = rawCreateApp(rootComponent, rootProps);
    registerUiComponents(app);
    return app;
  }
  patchedCreateApp.__hsuiPatched = true;
  Vue.createApp = patchedCreateApp;
})();

/* 全局变量暴露（typeof 守卫：仅在未定义时设置） */
if (typeof window.UiButton === 'undefined' && typeof UiButton !== 'undefined') window.UiButton      = UiButton;
if (typeof window.UiBadge === 'undefined' && typeof UiBadge !== 'undefined') window.UiBadge       = UiBadge;
if (typeof window.UiStatusBadge === 'undefined' && typeof UiStatusBadge !== 'undefined') window.UiStatusBadge = UiStatusBadge;
if (typeof window.UiDivider === 'undefined' && typeof UiDivider !== 'undefined') window.UiDivider     = UiDivider;
if (typeof window.UiAvatar === 'undefined' && typeof UiAvatar !== 'undefined') window.UiAvatar      = UiAvatar;
if (typeof window.UiEmpty === 'undefined' && typeof UiEmpty !== 'undefined') window.UiEmpty       = UiEmpty;
if (typeof window.UiLoading === 'undefined' && typeof UiLoading !== 'undefined') window.UiLoading     = UiLoading;
if (typeof window.UiInput === 'undefined' && typeof UiInput !== 'undefined') window.UiInput       = UiInput;
if (typeof window.UiHotkey === 'undefined' && typeof UiHotkey !== 'undefined') window.UiHotkey      = UiHotkey;
if (typeof window.UiDatetime === 'undefined' && typeof UiDatetime !== 'undefined') window.UiDatetime    = UiDatetime;
if (typeof window.UiSelect === 'undefined' && typeof UiSelect !== 'undefined') window.UiSelect      = UiSelect;
if (typeof window.UiSwitch === 'undefined' && typeof UiSwitch !== 'undefined') window.UiSwitch      = UiSwitch;
if (typeof window.UiRadio === 'undefined' && typeof UiRadio !== 'undefined') window.UiRadio       = UiRadio;
if (typeof window.UiFormField === 'undefined' && typeof UiFormField !== 'undefined') window.UiFormField   = UiFormField;
if (typeof window.UiForm === 'undefined' && typeof UiForm !== 'undefined') window.UiForm        = UiForm;
if (typeof window.UiModal === 'undefined' && typeof UiModal !== 'undefined') window.UiModal       = UiModal;
if (typeof window.UiDrawer === 'undefined' && typeof UiDrawer !== 'undefined') window.UiDrawer      = UiDrawer;
if (typeof window.UiConfirm === 'undefined' && typeof UiConfirm !== 'undefined') window.UiConfirm     = UiConfirm;
if (typeof window.UiToast === 'undefined' && typeof UiToast !== 'undefined') window.UiToast       = UiToast;
if (typeof window.UiTabs === 'undefined' && typeof UiTabs !== 'undefined') window.UiTabs        = UiTabs;
if (typeof window.UiTable === 'undefined' && typeof UiTable !== 'undefined') window.UiTable       = UiTable;
if (typeof window.UiPagination === 'undefined' && typeof UiPagination !== 'undefined') window.UiPagination  = UiPagination;
if (typeof window.UiIcon === 'undefined' && typeof UiIcon !== 'undefined') window.UiIcon        = UiIcon;
if (typeof window.useCrud === 'undefined' && typeof useCrud !== 'undefined') window.useCrud       = useCrud;

/* 控制中心 iframe 嵌入检测：聚合面板（parent.__ccPanelShim）内打开的配置页
   在 html 上加 in-iframe 类 → page.css 去玻璃（避免双层玻璃色差）。
   launcher 等其他 iframe 场景不受影响。 */
(function detectCCFrame() {
    try {
        if (window.self !== window.top && window.parent && window.parent.__ccPanelShim) {
            document.documentElement.classList.add('in-iframe');
        }
    } catch (e) {}
})();

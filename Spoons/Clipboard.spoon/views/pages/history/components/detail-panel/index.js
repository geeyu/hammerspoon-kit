// views/pages/history/components/detail-panel/index.js —— 内容详情面板（页面私有组件）
// 模板就近内联在页面 index.html（<template id="tpl-detail-panel">），源文件见 detail-panel.tpl.html
var DetailPanel = Vue.defineComponent({
  name: 'DetailPanel',
  props: {
    item: { type: Object, default: null },
    open: { type: Boolean, default: false },
  },
  emits: ['close'],
  template: '#tpl-detail-panel',
});

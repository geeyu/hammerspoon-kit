// views/components/hello-card/index.js —— 业务共享组件示例（全局变量 HelloCard）
// 模板就近内联在页面 index.html（<template id="tpl-hello-card">），源文件见 hello-card.tpl.html
var HelloCard = Vue.defineComponent({
  name: 'HelloCard',
  props: {
    title: { type: String, default: '你好' }
  },
  template: '#tpl-hello-card'
});

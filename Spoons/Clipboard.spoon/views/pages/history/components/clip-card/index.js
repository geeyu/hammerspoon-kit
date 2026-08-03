// views/pages/history/components/clip-card/index.js —— 剪贴板卡片（页面私有组件）
// 模板就近内联在页面 index.html（<template id="tpl-clip-card">），源文件见 clip-card.tpl.html
var ClipCard = Vue.defineComponent({
  name: 'ClipCard',
  props: {
    item: { type: Object, required: true },
    selected: { type: Boolean, default: false },
    enter: { type: Boolean, default: false },        // 进场动画开关（空→有）
    enterDelay: { type: Number, default: null },     // 进场错峰延迟（ms）
  },
  emits: ['confirm', 'hover', 'remove', 'star'],
  template: '#tpl-clip-card',
});

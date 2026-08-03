var UiLoading = Vue.defineComponent({
  name: 'UiLoading',
  props: {
    text: { type: String, default: 'Loading...' },
    size: { type: [String, Number], default: 14 }
  },
  template: '<div class="ui-loading">' +
    '<span class="ui-loading__spinner" :style="spinnerStyle"></span>' +
    '<span v-if="text" class="ui-loading__text">{{ text }}</span>' +
    '</div>',
  mounted: function () {
    var el = this.$el;
    if (!window.anime || !el) return;
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    // 旋转由 CSS .ui-loading__spinner 的 spin 动画驱动（优先级更高），
    // 这里只做容器入场 scale spring，避免 anime rotate 与 CSS 双驱动
    anime({ targets: el, scale: [0.92, 1], duration: 260, ease: anime.spring({ stiffness: 300, damping: 16 }) });
  },
  computed: {
    spinnerStyle: function () {
      var s = typeof this.size === 'number' ? this.size + 'px' : this.size;
      return { width: s, height: s };
    }
  }
});

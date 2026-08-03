var UiTabs = Vue.defineComponent({
  name: 'UiTabs',
  props: {
    modelValue: { type: [String, Number], default: '' },
    tabs: { type: Array, default: function() { return []; } },
    noKeyboard: { type: Boolean, default: false }
  },
  template: '#tpl-ui-tabs',
  emits: ['update:modelValue'],
  mounted: function () {
    var ind = this.$refs.indicator;
    if (!ind) return;
    if (!window.anime) {
      // 无 anime：指示条位置/宽度无人驱动，隐藏以免首帧 40px 短条错误指向
      ind.style.display = 'none';
      return;
    }
    this.positionIndicator(true);
  },
  watch: {
    modelValue: function () {
      if (!window.anime) return;
      this.positionIndicator();
    }
  },
  methods: {
    positionIndicator: function (immediate) {
      var self = this;
      Vue.nextTick(function () {
        var ind = self.$refs.indicator;
        var tabsEl = self.$el.querySelector('.ui-tabs') || self.$el;
        if (!ind || !tabsEl) return;
        var idx = self.tabs.findIndex(function (t) { return t.value === self.modelValue; });
        if (idx === -1) return;
        var tabEls = tabsEl.querySelectorAll('.ui-tabs__tab');
        var target = tabEls[idx];
        if (!target) return;
        if (ind.style.display === 'none') ind.style.display = '';
        anime({
          targets: ind,
          translateX: target.offsetLeft,
          width: target.offsetWidth,
          opacity: 1,          // 首帧从 0 淡入（配合 style.css 初始 opacity:0），切换时已是 1 无闪烁
          duration: immediate ? 0 : 260,
          ease: anime.spring({ stiffness: 320, damping: 24 })
        });
      });
    }
  },
  setup: function(props, ctx) {
    var emit = ctx.emit;

    function select(value) {
      emit('update:modelValue', value);
    }

    function getActiveIndex() {
      return props.tabs.findIndex(function(t) { return t.value === props.modelValue; });
    }

    function onKeydown(e) {
      if (props.noKeyboard) return;
      var idx = getActiveIndex();
      if (idx === -1) return;
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        idx = idx > 0 ? idx - 1 : props.tabs.length - 1;
        select(props.tabs[idx].value);
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        idx = idx < props.tabs.length - 1 ? idx + 1 : 0;
        select(props.tabs[idx].value);
      }
    }

    return { select: select, onKeydown: onKeydown };
  }
});

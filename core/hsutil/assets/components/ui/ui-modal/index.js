var UiModal = Vue.defineComponent({
  name: 'UiModal',
  props: {
    open: { type: Boolean, default: false },
    title: { type: String, default: '' },
    width: { type: String, default: '480px' },
    closable: { type: Boolean, default: true }
  },
  template: '#tpl-ui-modal',
  emits: ['update:open'],
  setup: function(props, ctx) {
    var emit = ctx.emit;

    function close() {
      if (props.closable) emit('update:open', false);
    }

    // Esc 关闭由弹层栈统一管理（HSUI.overlay：只关最顶层、焦点陷阱、焦点归还、滚动锁定）
    return { close: close };
  },
  methods: {
    /* 入场动效（transition JS 钩子：el 是本实例的元素，天然解决多实例 querySelector 串扰）
       配合 tpl 的 :css="false"——有 anime 时 JS 动画接管，无 anime 时直接 done 无动画 */
    onEnter: function (el, done) {
      if (window.HSUI && HSUI.overlay) HSUI.overlay.push(el, { onEsc: this.close });
      if (!window.anime) { done(); return; }
      var panel = el.querySelector('.ui-modal__panel');
      var pending = 0;
      var finished = function () { if (--pending <= 0) done(); };
      if (panel) { pending++; anime({ targets: panel, scale: [0.92, 1], translateY: [14, 0], duration: 260, ease: anime.spring({ stiffness: 340, damping: 20 }) }).then(finished); }
      pending++; anime({ targets: el, opacity: [0, 1], duration: 200, ease: 'outQuad' }).then(finished);
    },
    onLeave: function (el, done) {
      if (window.HSUI && HSUI.overlay) HSUI.overlay.pop(el);
      if (!window.anime) { done(); return; }
      var panel = el.querySelector('.ui-modal__panel');
      var pending = 0;
      var finished = function () { if (--pending <= 0) done(); };
      if (panel) { pending++; anime({ targets: panel, scale: [1, 0.95], translateY: [0, 8], opacity: [1, 0], duration: 150, ease: 'inQuad' }).then(finished); }
      pending++; anime({ targets: el, opacity: [1, 0], duration: 150, ease: 'inQuad' }).then(finished);
    }
  }
});

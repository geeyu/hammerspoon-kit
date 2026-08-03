var UiDrawer = Vue.defineComponent({
  name: 'UiDrawer',
  props: {
    open: { type: Boolean, default: false },
    title: { type: String, default: '' },
    width: { type: String, default: '320px' },
    closable: { type: Boolean, default: true }
  },
  template: '#tpl-ui-drawer',
  emits: ['update:open'],
  setup: function(props, ctx) {
    var emit = ctx.emit;

    function close() {
      emit('update:open', false);
    }

            return { close: close };
  },
  methods: {
    /* 入场/退场动效（transition JS 钩子：el 是本实例元素，多实例不串扰；配合 :css="false"） */
    onEnter: function (el, done) {
      if (window.HSUI && HSUI.overlay) HSUI.overlay.push(el, { onEsc: this.close });
      if (!window.anime) { done(); return; }
      var panel = el.querySelector('.ui-drawer__panel');
      var pending = 0;
      var finished = function () { if (--pending <= 0) done(); };
      if (panel) { pending++; anime({ targets: panel, translateX: [panel.offsetWidth, 0], duration: 280, ease: anime.spring({ stiffness: 300, damping: 24 }) }).then(finished); }
      pending++; anime({ targets: el, opacity: [0, 1], duration: 200, ease: 'outQuad' }).then(finished);
    },
    onLeave: function (el, done) {
      if (window.HSUI && HSUI.overlay) HSUI.overlay.pop(el);
      if (!window.anime) { done(); return; }
      var panel = el.querySelector('.ui-drawer__panel');
      var pending = 0;
      var finished = function () { if (--pending <= 0) done(); };
      if (panel) { pending++; anime({ targets: panel, translateX: [0, panel.offsetWidth * 0.6], duration: 160, ease: 'inQuad' }).then(finished); }
      pending++; anime({ targets: el, opacity: [1, 0], duration: 160, ease: 'inQuad' }).then(finished);
    }
  }
});

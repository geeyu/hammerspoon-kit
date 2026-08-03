var UiStatusBadge = Vue.defineComponent({
  name: 'UiStatusBadge',
  props: {
    status: { type: String, default: 'info' },
    text: { type: String, default: '' },
    pulse: { type: Boolean, default: false }
  },
  template: '<span class="ui-status-badge" :class="[\'ui-status-badge--\' + status, { \'ui-status-badge--pulse\': pulse }]">' +
    '<span class="ui-status-badge__dot"></span>' +
    '<span class="ui-status-badge__text">{{ text }}</span>' +
    '</span>',
  mounted: function () {
    var el = this.$el;
    if (!window.anime || !el || !this.pulse) return;
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    var dot = el.querySelector('.ui-status-badge__dot');
    if (!dot) return;
    this._pulse = anime({ targets: dot, scale: [1, 1.6], opacity: [1, 0.4], duration: 900, alternate: true, loop: true, ease: 'outQuad' });
  },
  beforeUnmount: function () {
    if (this._pulse) {
      anime.remove(this._pulse.targets);
      this._pulse = null;
    }
  }
});

var UiBadge = Vue.defineComponent({
  name: 'UiBadge',
  props: {
    text: { type: String, default: '' },
    tone: { type: String, default: 'neutral' },
    dot: { type: Boolean, default: false }
  },
  template: '<span class="ui-badge" :class="[\'ui-badge--\' + tone, { \'ui-badge--dot\': dot }]">' +
    '<span v-if="dot" class="ui-badge__dot"></span>' +
    '<span v-else class="ui-badge__text">{{ text }}</span>' +
    '</span>',
  mounted: function () {
    var el = this.$el;
    if (!window.anime || !el || !this.dot) return;
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    var dot = el.querySelector('.ui-badge__dot');
    if (!dot) return;
    this._pulse = anime({ targets: dot, scale: [1, 1.5, 1], opacity: [1, 0.6, 1], duration: 1600, loop: true, ease: 'inOutSine' });
  },
  beforeUnmount: function () {
    if (this._pulse) {
      anime.remove(this._pulse.targets);
      this._pulse = null;
    }
  }
});

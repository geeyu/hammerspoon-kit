var UiEmpty = Vue.defineComponent({
  name: 'UiEmpty',
  props: {
    icon: { type: String, default: 'inbox' },
    text: { type: String, default: 'No data' },
    hint: { type: String, default: '' }
  },
  template: '<div class="ui-empty">' +
    '<div class="ui-empty__icon"><ui-icon :name="icon" :size="28" /></div>' +
    '<div class="ui-empty__text">{{ text }}</div>' +
    '<div v-if="hint" class="ui-empty__hint">{{ hint }}</div>' +
    '<div v-if="$slots.default" class="ui-empty__extra"><slot /></div>' +
    '</div>',
  mounted: function () {
    var el = this.$el;
    if (!window.anime || !el) return;
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    var icon = el.querySelector('.ui-empty__icon');
    if (!icon) return;
    anime({ targets: icon, scale: [0.4, 1.1, 1], duration: 480, ease: anime.spring({ stiffness: 260, damping: 12 }) });
  }
});

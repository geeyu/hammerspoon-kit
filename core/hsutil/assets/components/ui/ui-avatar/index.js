var UiAvatar = Vue.defineComponent({
  name: 'UiAvatar',
  props: {
    text: { type: String, default: '' },
    color: { type: String, default: '' },
    size: { type: [String, Number], default: 32 },
    src: { type: String, default: '' }
  },
  template: '<div class="ui-avatar" :style="avatarStyle">' +
    '<img v-if="src" :src="src" class="ui-avatar__img" alt="" />' +
    '<span v-else class="ui-avatar__text">{{ text.charAt(0) }}</span>' +
    '</div>',
  computed: {
    avatarStyle: function () {
      var s = typeof this.size === 'number' ? this.size + 'px' : this.size;
      var style = { width: s, height: s };
      if (this.color) style.background = this.color;
      return style;
    }
  }
});

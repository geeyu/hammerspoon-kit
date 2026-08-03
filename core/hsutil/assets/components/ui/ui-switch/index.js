var UiSwitch = Vue.defineComponent({
  name: 'UiSwitch',
  props: {
    modelValue: { type: Boolean, default: false },
    disabled: { type: Boolean, default: false }
  },
  template: '<button class="ui-switch" :class="{ \'ui-switch--on\': modelValue, \'ui-switch--disabled\': disabled }" ' +
    'type="button" role="switch" :aria-checked="modelValue" :disabled="disabled" ' +
    '@click="toggle">' +
    '<span ref="thumb" class="ui-switch__thumb"></span>' +
    '</button>',
  emits: ['update:modelValue'],
  setup: function(props, refs) {
    var emit = refs.emit;
    function toggle() {
      if (!props.disabled) {
        emit('update:modelValue', !props.modelValue);
      }
    }
    return { toggle: toggle };
  },
  watch: {
    modelValue: function (val, old) {
      if (!window.anime || val === old) return;
      var thumb = this.$refs.thumb;
      if (!thumb) return;
      anime({
        targets: thumb,
        scale: [1, 0.65, 1],
        duration: 380,
        ease: anime.spring({ stiffness: 350, damping: 14 })
      });
    }
  }
});

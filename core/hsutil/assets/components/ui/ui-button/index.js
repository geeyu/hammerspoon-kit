var UiButton = Vue.defineComponent({
  name: 'UiButton',
  props: {
    variant: { type: String, default: 'default' },
    size: { type: String, default: 'md' },
    disabled: { type: Boolean, default: false },
    loading: { type: Boolean, default: false },
    block: { type: Boolean, default: false },
    icon: { type: String, default: '' }
  },
  template: '#tpl-ui-button',
  emits: ['click'],
  setup: function (props, _a) {
    var emit = _a.emit;
    function handleClick(e) {
      if (!props.disabled && !props.loading) {
        emit('click', e);
      }
    }
    return { handleClick: handleClick };
  }
});

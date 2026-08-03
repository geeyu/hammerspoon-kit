var UiDivider = Vue.defineComponent({
  name: 'UiDivider',
  props: {
    label: { type: String, default: '' }
  },
  template: '<div class="ui-divider" :class="{ \'ui-divider--labeled\': label }">' +
    '<span v-if="label" class="ui-divider__label">{{ label }}</span>' +
    '</div>'
});

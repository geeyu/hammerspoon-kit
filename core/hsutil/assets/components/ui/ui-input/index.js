var UiInput = Vue.defineComponent({
  name: 'UiInput',
  props: {
    modelValue: { type: [String, Number], default: '' },
    placeholder: { type: String, default: '' },
    type: { type: String, default: 'text' },
    disabled: { type: Boolean, default: false },
    monospace: { type: Boolean, default: false }
  },
  template: '<input class="ui-input" :class="{ \'ui-input--mono\': monospace }" ' +
    ':value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" ' +
    ':type="type" :placeholder="placeholder" :disabled="disabled" ' +
    '@keyup.enter="$emit(\'enter\', $event)" />',
  emits: ['update:modelValue', 'enter']
});

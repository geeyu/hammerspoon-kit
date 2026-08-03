var UiFormField = Vue.defineComponent({
  name: 'UiFormField',
  props: {
    label: { type: String, default: '' },
    required: { type: Boolean, default: false },
    hint: { type: String, default: '' },
    focused: { type: Boolean, default: false },
    error: { type: String, default: '' }
  },
  template: '<div class="ui-form-field" :class="{ \'ui-form-field--focused\': focused }" @click="$emit(\'click\')">' +
    '<label v-if="label" class="ui-form-field__label">' +
    '{{ label }}<span v-if="required" class="ui-form-field__required">*</span>' +
    '</label>' +
    '<div class="ui-form-field__control"><slot /></div>' +
    '<div v-if="hint && !error" class="ui-form-field__hint">{{ hint }}</div>' +
    '<div v-if="error" class="ui-form-field__error" role="alert" :aria-invalid="\'true\'">{{ error }}</div>' +
    '</div>',
  emits: ['click']
});

var UiRadio = Vue.defineComponent({
  name: 'UiRadioGroup',
  props: {
    modelValue: { default: '' },
    options: { type: Array, default: function() { return []; } },
    direction: { type: String, default: 'row' },
    /* 原生 radio 分组名：同组方向键切换依赖 name；缺省自动生成唯一组名 */
    name: { type: String, default: '' }
  },
  template: '<div class="ui-radio" role="radiogroup" :class="[\'ui-radio--\' + direction]">' +
    '<label v-for="opt in options" :key="opt.value" class="ui-radio__item" ' +
    ':class="{ \'ui-radio__item--active\': modelValue === opt.value }">' +
    '<input type="radio" class="ui-radio__input" :name="groupName" :value="opt.value" ' +
    ':checked="modelValue === opt.value" @change="$emit(\'update:modelValue\', opt.value)" />' +
    '<span class="ui-radio__dot"></span>' +
    '<span class="ui-radio__label">{{ opt.label }}</span>' +
    '</label>' +
    '</div>',
  emits: ['update:modelValue'],
  computed: {
    groupName: function () {
      if (this.name) return this.name;
      if (!this._autoName) {
        this._autoName = 'ui-radio-' + Math.random().toString(36).slice(2, 8);
      }
      return this._autoName;
    }
  }
});

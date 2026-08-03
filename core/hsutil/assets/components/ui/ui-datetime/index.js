/* ===== UiDatetime（ui/ui-datetime/index.js）=====
   日期时间选择：封装 flatpickr（vendor/flatpickr，dark.css 深色主题 + zh locale）。
   v-model 输出 "yyyy-MM-dd HH:mm:ss"（秒恒为 00）；选择后 emit change。
   依赖 flatpickr 全局（vendor 注入），模板使用 ui-icon（deps 声明）。 */
var UiDatetime = Vue.defineComponent({
  name: 'UiDatetime',
  props: {
    modelValue: { type: String, default: '' },      // "yyyy-MM-dd HH:mm[:ss]"
    placeholder: { type: String, default: '选择日期时间' },
    minDate: { type: String, default: '' },          // "yyyy-MM-dd"，空 = 今天零点
    clearable: { type: Boolean, default: true },
    disabled: { type: Boolean, default: false },
  },
  emits: ['update:modelValue', 'change'],
  template:
    '<div class="ui-datetime" :class="{ \'ui-datetime--disabled\': disabled }">' +
      '<input ref="inputEl" :placeholder="placeholder" :disabled="disabled" readonly>' + +
      '<ui-icon name="calendar" :size="14" class="ui-datetime__icon"></ui-icon>' +
      '<button v-if="modelValue && clearable && !disabled" type="button" class="ui-datetime__clear" @click.stop="onClear" title="清除">✕</button>' +
    '</div>',
  setup: function (props, ctx) {
    var inputEl = Vue.ref(null);
    var fp = Vue.ref(null);

    // 选择结果统一补秒输出
    function toOutput(dateStr) { return dateStr + ':00'; }

    Vue.onMounted(function () {
      if (typeof flatpickr === 'undefined') {
        console.error('[UiDatetime] flatpickr 未加载（vendor 未注入）');
        return;
      }
      var min = new Date();
      min.setHours(0, 0, 0, 0);   // 默认不允许选今天零点之前（后端也会拒绝已过时间）
      fp.value = flatpickr(inputEl.value, {
        enableTime: true,
        time_24hr: true,
        dateFormat: 'Y-m-d H:i',
        minDate: props.minDate || min,
        locale: (flatpickr.l10ns && flatpickr.l10ns.zh) ? flatpickr.l10ns.zh : undefined,
        onChange: [function (selectedDates, dateStr) {
          // 防御：时间输入被删空/非法时 flatpickr 会产出含 NaN 的值，过滤不 emit
          if (String(dateStr).indexOf('NaN') !== -1) return;
          ctx.emit('update:modelValue', toOutput(dateStr));
          ctx.emit('change', toOutput(dateStr));
        }],
      });
      if (props.modelValue) fp.value.setDate(props.modelValue.slice(0, 16));
    });

    // 外部重置/回填同步（如页面启动后清空）
    Vue.watch(function () { return props.modelValue; }, function (v) {
      if (!fp.value) return;
      if (v) fp.value.setDate(String(v).slice(0, 16));
      else fp.value.clear();
    });

    Vue.onBeforeUnmount(function () { if (fp.value) fp.value.destroy(); });

    function onClear() {
      if (fp.value) fp.value.clear();
      ctx.emit('update:modelValue', '');
      ctx.emit('change', '');
    }

    return { inputEl: inputEl, fp: fp, onClear: onClear };
  },
});

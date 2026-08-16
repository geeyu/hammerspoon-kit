/* ===== UiDatetime（ui/ui-datetime/index.js）=====
   日期时间选择：封装 flatpickr（vendor/flatpickr，dark.css 深色主题 + zh locale）。
   v-model 输出 "yyyy-MM-dd HH:mm:ss"（秒恒为 00）；选择后 emit change。
   依赖 flatpickr 全局（vendor 注入），模板使用 ui-icon（deps 声明）。 */
var UiDatetime = Vue.defineComponent({
  name: "UiDatetime",
  props: {
    modelValue: { type: String, default: "" }, // "yyyy-MM-dd HH:mm[:ss]"
    placeholder: { type: String, default: "选择日期时间" },
    minDate: { type: String, default: "" }, // "yyyy-MM-dd"，空 = 今天零点
    clearable: { type: Boolean, default: true },
    disabled: { type: Boolean, default: false },
  },
  emits: ["update:modelValue", "change"],
  template:
    '<div class="ui-datetime" :class="{ \'ui-datetime--disabled\': disabled }">' +
    '<input ref="inputEl" :placeholder="placeholder" :disabled="disabled" readonly>' +
    // 有值时可清：隐藏日历图标避免与 ✕ 重叠（right 8px vs 6px）
    '<ui-icon v-if="!modelValue || !clearable" name="calendar" :size="14" class="ui-datetime__icon"></ui-icon>' +
    '<button v-if="modelValue && clearable && !disabled" type="button" class="ui-datetime__clear" @click.stop="onClear" title="清除">✕</button>' +
    "</div>",
  setup: (props, ctx) => {
    var inputEl = Vue.ref(null);
    var fp = Vue.ref(null);

    // 选择结果统一补秒输出
    function toOutput(dateStr) {
      return dateStr + ":00";
    }

    // "yyyy-MM-dd HH:mm" → Date（本地时区，规避 Safari 对 '-' 分隔符的解析问题）
    function parseLocal(s) {
      var m = String(s).match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/);
      if (!m) return null;
      return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
    }
    function formatLocal(d) {
      var p = (n) => (n < 10 ? "0" : "") + n;
      return (
        d.getFullYear() +
        "-" +
        p(d.getMonth() + 1) +
        "-" +
        p(d.getDate()) +
        " " +
        p(d.getHours()) +
        ":" +
        p(d.getMinutes())
      );
    }

    Vue.onMounted(() => {
      if (typeof flatpickr === "undefined") {
        console.error("[UiDatetime] flatpickr 未加载（vendor 未注入）");
        return;
      }
      var min = new Date();
      min.setHours(0, 0, 0, 0); // 默认不允许选今天零点之前（后端也会拒绝已过时间）
      fp.value = flatpickr(inputEl.value, {
        enableTime: true,
        time_24hr: true,
        // 默认时间从 00:00 起（flatpickr 默认 12:00，选今天时 12:00 显得突兀）
        defaultHour: 0,
        defaultMinute: 0,
        dateFormat: "Y-m-d H:i",
        minDate: props.minDate || min,
        locale:
          flatpickr.l10ns && flatpickr.l10ns.zh
            ? flatpickr.l10ns.zh
            : undefined,
        onChange: [
          (selectedDates, dateStr) => {
            // 防御：清空（fp.clear 触发）或时间输入被删空/非法时
            // flatpickr 产出空串或含 NaN 的值，过滤不 emit（否则 toOutput("") 会回流 ":00"）
            if (!dateStr || String(dateStr).indexOf("NaN") !== -1) return;
            var out = dateStr;
            // 交互兜底：选中时间已过（典型场景＝选「今天」且时间是默认的 00:00）
            // 时自动提升到当前时间，避免提交后被后端 "时间已过" 拒绝
            var dt = parseLocal(dateStr);
            if (dt) {
              var now = new Date();
              now.setSeconds(0, 0);
              if (dt.getTime() <= now.getTime()) {
                out = formatLocal(now);
                fp.value.setDate(now); // 同步输入框显示（不触发 onChange）
              }
            }
            ctx.emit("update:modelValue", toOutput(out));
            ctx.emit("change", toOutput(out));
          },
        ],
      });
      if (props.modelValue) fp.value.setDate(props.modelValue.slice(0, 16));
    });

    // 外部重置/回填同步（如页面启动后清空）
    Vue.watch(
      () => props.modelValue,
      (v) => {
        if (!fp.value) return;
        if (v) fp.value.setDate(String(v).slice(0, 16));
        else fp.value.clear();
      },
    );

    // 动态禁用：input 的 disabled 属性与组件状态同步（如父级禁用后不可再开日历）
    Vue.watch(
      () => props.disabled,
      (v) => {
        if (inputEl.value) inputEl.value.disabled = v;
      },
    );

    Vue.onBeforeUnmount(() => {
      if (fp.value) fp.value.destroy();
    });

    function onClear() {
      // clear(false)：不触发 onChange（否则空串会被 onChange 过滤前处理，且避免 ":00" 回流）
      if (fp.value) fp.value.clear(false);
      ctx.emit("update:modelValue", "");
      ctx.emit("change", "");
    }

    return { inputEl: inputEl, fp: fp, onClear: onClear };
  },
});

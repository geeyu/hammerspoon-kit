var UiForm = Vue.defineComponent({
  name: 'UiForm',
  props: {
    schema: { type: Array, default: function() { return []; } },
    model: { type: Object, default: function() { return {}; } },
    columns: { type: Number, default: 1 }
  },
  template: '#tpl-ui-form',
  emits: ['submit', 'change'],
  setup: function(props, refs) {
    var emit = refs.emit;
    var localModel = Vue.reactive({});
    var focusIndex = Vue.ref(-1);
    var formEl = Vue.ref(null);
    var errors = Vue.reactive({});   // { key: 错误文案 }，required 校验失败时填充

    /* 初始化本地 model：model 已有值优先，其次 schema default，最后按 type 设默认值 */
    function initModel() {
      var m = props.model || {};
      var schema = props.schema || [];
      for (var i = 0; i < schema.length; i++) {
        var field = schema[i];
        if (m.hasOwnProperty && m.hasOwnProperty(field.key)) {
          localModel[field.key] = m[field.key];
        } else if (field.hasOwnProperty && field.hasOwnProperty('default')) {
          localModel[field.key] = field.default;
        } else if (field.type === 'checkbox') {
          localModel[field.key] = false;
        } else if (field.type === 'number') {
          localModel[field.key] = 0;
        } else {
          localModel[field.key] = '';
        }
      }
    }
    initModel();

    /* schema 响应式缩减时钳制 focusIndex，避免键盘导航越界失效 */
    Vue.watch(function() { return props.schema.length; }, function() {
      if (focusIndex.value >= props.schema.length) {
        focusIndex.value = Math.max(0, props.schema.length - 1);
      }
    });

    /* 外部 model prop 变化时同步 */
    Vue.watch(function() { return props.model; }, function(newVal) {
      if (newVal) {
        var keys = Object.keys(newVal);
        for (var i = 0; i < keys.length; i++) {
          localModel[keys[i]] = newVal[keys[i]];
        }
      }
    }, { deep: true });

    function handleFieldChange(key, value) {
      localModel[key] = value;
      if (errors[key]) delete errors[key];   // 修改即清除该字段错误
      emit('change', key, value);
    }

    function handleSubmit() {
      // required 校验：空必填项拦截 + 错误文案 + 聚焦首个错误字段
      var schema = props.schema || [];
      var firstErrorKey = null;
      var hasError = false;
      for (var k in errors) delete errors[k];
      for (var i = 0; i < schema.length; i++) {
        var field = schema[i];
        if (field.required) {
          var v = localModel[field.key];
          if (v === undefined || v === null || v === '') {
            errors[field.key] = (field.label || field.key) + ' 为必填项';
            hasError = true;
            if (!firstErrorKey) firstErrorKey = field.key;
          }
        }
      }
      if (hasError && firstErrorKey) {
        var errIdx = -1;
        for (var j = 0; j < schema.length; j++) {
          if (schema[j].key === firstErrorKey) { errIdx = j; break; }
        }
        if (errIdx >= 0) focusIndex.value = errIdx;
        return;   // 不 emit submit
      }
      var out = {};
      var keys = Object.keys(localModel);
      for (var n = 0; n < keys.length; n++) {
        out[keys[n]] = localModel[keys[n]];
      }
      emit('submit', out);
    }

    function focus() {
      var schema = props.schema;
      if (schema && schema.length > 0) {
        focusIndex.value = 0;
      }
      /* 将 DOM focus 交给 form 容器以便接收键盘事件 */
      var el = formEl.value;
      if (el && el.focus) el.focus();
    }

    function onKeydown(e) {
      /* textarea 内所有键放行（上下键光标移动、Enter 换行） */
      if (e.target.tagName === 'TEXTAREA') {
        return;
      }
      /* input 内：只保留 Enter 提交（触发表单提交），其余键放行（上下左右键光标移动、空格输入字符） */
      if (e.target.tagName === 'INPUT') {
        if (e.key !== 'Enter') return;
      }

      var key = e.key;

      /* Enter 提交不依赖 focusIndex（初始未聚焦字段时也可提交） */
      if (key === 'Enter') {
        e.preventDefault();
        handleSubmit();
        return;
      }

      var idx = focusIndex.value;
      var schema = props.schema || [];
      if (idx < 0 || idx >= schema.length) return;

      var field = schema[idx];

      if (key === 'ArrowUp') {
        e.preventDefault();
        if (idx > 0) focusIndex.value = idx - 1;
      } else if (key === 'ArrowDown') {
        e.preventDefault();
        if (idx < schema.length - 1) focusIndex.value = idx + 1;
      } else if (key === 'ArrowLeft' || key === 'ArrowRight') {
        if (field.type === 'select' || field.type === 'radio') {
          e.preventDefault();
          var opts = field.options || [];
          if (!opts.length) return;
          var curVal = localModel[field.key];
          var curIdx = -1;
          for (var i = 0; i < opts.length; i++) {
            if (opts[i].value === curVal) { curIdx = i; break; }
          }
          var dir = key === 'ArrowRight' ? 1 : -1;
          var newIdx = curIdx + dir;
          if (newIdx < 0) newIdx = opts.length - 1;
          if (newIdx >= opts.length) newIdx = 0;
          if (opts[newIdx]) {
            handleFieldChange(field.key, opts[newIdx].value);
          }
        }
      } else if (key === ' ') {
        if (field.type === 'checkbox') {
          e.preventDefault();
          handleFieldChange(field.key, !localModel[field.key]);
        }
      }
    }

    return {
      localModel: localModel,
      focusIndex: focusIndex,
      formEl: formEl,
      errors: errors,
      handleFieldChange: handleFieldChange,
      handleSubmit: handleSubmit,
      focus: focus,
      onKeydown: onKeydown
    };
  }
});

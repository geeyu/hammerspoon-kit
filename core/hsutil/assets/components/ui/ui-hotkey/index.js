/* ===== UiHotkey（ui/ui-hotkey/index.js）=====
   热键捕获输入：点击聚焦后按下组合键自动识别（Ctrl/Cmd/Alt/Shift + 主键），
   Esc 清空，Backspace/✕ 清除。值格式：mods 小写 + 主键，如 "ctrl+shift+v"。
   remote 模式（如窗口管理配置页）：录制期间由后端 eventtap 吞掉按键
   （屏蔽系统快捷键触发），前端轮询拿结果——需后端提供
   POST <remoteUrl> {action:'start'|'stop'} + GET <remoteUrl>/poll → {result}。 */
var UiHotkey = Vue.defineComponent({
  name: 'UiHotkey',
  props: {
    modelValue: { type: String, default: '' },
    remote: { type: Boolean, default: false },      // 后端吞键录制模式
    remoteUrl: { type: String, default: '' },       // guard API 前缀
    disabled: { type: Boolean, default: false },    // 置灰不可录制
  },
  emits: ['update:modelValue'],
  template: '#tpl-ui-hotkey',
  setup: function (props, ctx) {
    var capturing = Vue.ref(false);
    var display = Vue.ref('');
    var root = Vue.ref(null);
    var pollTimer = null;

    // "ctrl+shift+v" → "Ctrl+Shift+V"
    function formatDisplay(v) {
      if (!v) return '';
      return String(v).split('+').map(function (p) {
        if (!p) return p;
        return p.length === 1 ? p.toUpperCase() : p.charAt(0).toUpperCase() + p.slice(1);
      }).join('+');
    }

    Vue.watch(function () { return props.modelValue; }, function (v) {
      display.value = formatDisplay(v);
    }, { immediate: true });

    function remoteStart() {
      if (!props.remote || !props.remoteUrl) return;
      fetch(props.remoteUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'start' }),
      }).catch(function () {});
      pollTimer = setInterval(function () {
        fetch(props.remoteUrl + '/poll')
          .then(function (r) { return r.json(); })
          .then(function (d) {
            if (d && d.result) {
              var val = d.result;
              display.value = formatDisplay(val);
              ctx.emit('update:modelValue', val);
              stopCapture(true);
            }
          })
          .catch(function () {});
      }, 500);
    }
    function remoteStop() {
      if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
      if (props.remote && props.remoteUrl) {
        fetch(props.remoteUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'stop' }),
        }).catch(function () {});
      }
    }

    function onFocus() {
      if (props.disabled) return;
      capturing.value = true;
      remoteStart();
    }
    function onBlur() {
      if (!capturing.value) return;
      stopCapture(false);
    }
    function stopCapture(keepValue) {
      capturing.value = false;
      remoteStop();
      // 显示与 props 对齐：emit 后父组件可能在同一 tick 内回滚值（如冲突拦截），
      // props 最终值 ≠ 录制值且与旧值相同 → watch 不触发，display 停留在录制值；
      // nextTick 后 props 已 flush，重新同步一次（正常流程下两者一致，无副作用）
      Vue.nextTick(function () { display.value = formatDisplay(props.modelValue); });
      if (!keepValue && root.value) root.value.blur();
    }

    function onKeydown(e) {
      if (!capturing.value) return;
      e.preventDefault();
      e.stopPropagation();

      if (e.key === 'Escape') {
        ctx.emit('update:modelValue', '');
        stopCapture(false);
        return;
      }
      if (e.key === 'Backspace' || e.key === 'Delete') {
        ctx.emit('update:modelValue', '');
        return;
      }

      // remote 模式：按键由后端 eventtap 捕获，前端不直接录
      if (props.remote) return;

      // 纯修饰键按下不完成捕获
      if (e.key === 'Control' || e.key === 'Alt' || e.key === 'Meta' || e.key === 'Shift') return;
      if (e.key === 'Tab') return;

      var mods = [];
      if (e.ctrlKey) mods.push('ctrl');
      if (e.altKey) mods.push('alt');
      if (e.metaKey) mods.push('cmd');
      if (e.shiftKey) mods.push('shift');

      // 主键归一化：单字符转小写，其余（F5/ArrowUp 等）原样
      var mainKey = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      var val = mods.concat([mainKey]).join('+');
      display.value = formatDisplay(val);
      ctx.emit('update:modelValue', val);
      stopCapture(true);
    }

    Vue.onBeforeUnmount(function () { remoteStop(); });

    return { capturing: capturing, display: display, root: root,
             onFocus: onFocus, onBlur: onBlur, onKeydown: onKeydown };
  },
});

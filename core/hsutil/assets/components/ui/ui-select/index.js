var UiSelect = Vue.defineComponent({
  name: 'UiSelect',
  props: {
    modelValue: { default: '' },
    options: { type: Array, default: function() { return []; } },
    placeholder: { type: String, default: 'Select...' },
    disabled: { type: Boolean, default: false }
  },
  template: '#tpl-ui-select',
  emits: ['update:modelValue', 'change'],
  setup: function(props, refs) {
    var emit = refs.emit;
    var open = Vue.ref(false);
    var root = Vue.ref(null);
    var activeIdx = Vue.ref(-1);   // 下拉键盘高亮位（-1 = 无）

    var currentLabel = Vue.computed(function() {
      var opts = props.options || [];
      for (var i = 0; i < opts.length; i++) {
        if (opts[i].value === props.modelValue) return opts[i].label;
      }
      return props.placeholder;
    });

    function currentIndex() {
      var opts = props.options || [];
      for (var i = 0; i < opts.length; i++) {
        if (opts[i].value === props.modelValue) return i;
      }
      return -1;
    }

    function openPanel() {
      open.value = true;
      activeIdx.value = currentIndex();   // 高亮当前值
      if (window.anime) {
        Vue.nextTick(function () {
          var panel = root.value && root.value.querySelector('.ui-select__dropdown');
          if (panel) {
            anime({ targets: panel, translateY: [-6, 0], opacity: [0, 1], duration: 220, ease: anime.spring({ stiffness: 320, damping: 22 }) });
          }
        });
      }
    }

    function toggleOpen() {
      if (props.disabled) return;
      if (open.value) {
        open.value = false;
      } else {
        openPanel();
      }
    }

    function selectOption(opt) {
      if (props.disabled) return;
      emit('update:modelValue', opt.value);
      emit('change', opt.value);
      open.value = false;
    }

    function onKeydown(e) {
      var opts = props.options || [];
      var key = e.key;

      if (key === 'ArrowDown' || key === 'ArrowUp') {
        e.preventDefault();
        if (!opts.length) return;
        if (!open.value) { openPanel(); return; }   // 未打开：先展开
        var dir = key === 'ArrowDown' ? 1 : -1;
        var base = activeIdx.value >= 0 ? activeIdx.value : currentIndex();
        if (base < 0) base = dir > 0 ? -1 : 0;
        var next = base + dir;
        if (next < 0) next = opts.length - 1;
        if (next >= opts.length) next = 0;
        activeIdx.value = next;
      } else if (key === 'Enter') {
        if (open.value && activeIdx.value >= 0 && opts[activeIdx.value]) {
          e.preventDefault();
          selectOption(opts[activeIdx.value]);
        }
      } else if (key === 'Home') {
        if (open.value && opts.length) { e.preventDefault(); activeIdx.value = 0; }
      } else if (key === 'End') {
        if (open.value && opts.length) { e.preventDefault(); activeIdx.value = opts.length - 1; }
      } else if (key === 'ArrowLeft' || key === 'ArrowRight') {
        // 闭合态 ←→ 切换选项（打开态由 ↑↓ 导航接管）
        if (open.value) return;
        e.preventDefault();
        if (!opts.length) return;
        var curIdx = currentIndex();
        var dir = key === 'ArrowRight' ? 1 : -1;
        var newIdx = curIdx + dir;
        if (newIdx < 0) newIdx = opts.length - 1;
        if (newIdx >= opts.length) newIdx = 0;
        if (opts[newIdx]) {
          emit('update:modelValue', opts[newIdx].value);
          emit('change', opts[newIdx].value);
        }
      } else if (key === 'Tab') {
        if (open.value) open.value = false;   // Tab 离开时收起下拉
      } else if (key === 'Escape') {
        open.value = false;
      }
    }

    // 键盘高亮项滚动进视口（下拉 max-height 180px）
    Vue.watch(activeIdx, function (idx) {
      if (idx < 0 || !open.value) return;
      Vue.nextTick(function () {
        var box = root.value;
        if (!box) return;
        var opts = box.querySelectorAll('.ui-select__option');
        var el = opts[idx];
        if (el && el.scrollIntoView) el.scrollIntoView({ block: 'nearest' });
      });
    });

    // 点击外部关闭
    function onDocClick(e) {
      if (!open.value) return;
      if (root.value && root.value.contains(e.target)) return;
      open.value = false;
    }
    Vue.onMounted(function () { document.addEventListener('click', onDocClick); });
    Vue.onBeforeUnmount(function () { document.removeEventListener('click', onDocClick); });

    return {
      open: open,
      root: root,
      activeIdx: activeIdx,
      currentLabel: currentLabel,
      toggleOpen: toggleOpen,
      selectOption: selectOption,
      onKeydown: onKeydown
    };
  }
});

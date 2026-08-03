/* HSUtil 弹层管理（modal/drawer 共享）：
   - 弹层栈：Esc 只关闭最顶层（不再一次关全部堆叠弹层）
   - 焦点陷阱：打开聚焦面板内首个可聚焦元素，Tab/Shift+Tab 在面板内循环
   - 焦点归还：关闭后焦点回到触发元素
   - body 滚动锁定：打开期间背景不可滚动
   用法：HSUI.overlay.push(el, { onEsc }) → 返回 entry；HSUI.overlay.pop(el) */
window.HSUI = window.HSUI || {};

HSUI.overlay = (function () {
  var stack = [];
  var bodyLocked = false;

  function lockBody() {
    if (!bodyLocked) {
      document.body.style.overflow = 'hidden';
      bodyLocked = true;
    }
  }
  function unlockBody() {
    if (stack.length === 0) {
      document.body.style.overflow = '';
      bodyLocked = false;
    }
  }

  function onDocKey(e) {
    if (e.key !== 'Escape') return;
    var top = stack[stack.length - 1];
    if (top && top.opts.onEsc) {
      e.stopPropagation();   // 阻止下层弹层的 Esc 监听
      top.opts.onEsc();
    }
  }

  return {
    push: function (el, opts) {
      opts = opts || {};
      var entry = { el: el, opts: opts, prevActive: document.activeElement, onKeydown: null };
      stack.push(entry);
      lockBody();

      // 初始聚焦：面板内首个可聚焦元素（避免聚焦危险操作）
      var focusable = el.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
      if (focusable) focusable.focus();

      // Esc：全局 capture 监听，只响应栈顶（stopPropagation 阻断下层）
      if (!this._onKey) {
        this._onKey = onDocKey;
        document.addEventListener('keydown', this._onKey, true);
      }

      // 焦点陷阱：Tab/Shift+Tab 在面板内循环
      entry.onKeydown = function (e) {
        if (e.key !== 'Tab') return;
        var focusables = el.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
        if (!focusables.length) { e.preventDefault(); return; }
        var first = focusables[0];
        var last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      };
      el.addEventListener('keydown', entry.onKeydown);
      return entry;
    },

    pop: function (el) {
      for (var i = stack.length - 1; i >= 0; i--) {
        if (stack[i].el === el) {
          var entry = stack.splice(i, 1)[0];
          el.removeEventListener('keydown', entry.onKeydown);
          // 焦点归还触发元素
          if (entry.prevActive && entry.prevActive.focus && document.contains(entry.prevActive)) {
            entry.prevActive.focus();
          }
          unlockBody();
          return;
        }
      }
    }
  };
})();

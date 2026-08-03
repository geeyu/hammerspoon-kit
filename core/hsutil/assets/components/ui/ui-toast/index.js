/* 命令式 Toast：UiToast.show(text, {type, duration})
   动态创建容器 fixed top-center；同文本合并去重；自动滑入滑出 */

var UiToast = (function() {
  var container = null;
  var items = [];
  var nextId = 0;

  function ensureContainer() {
    if (!container) {
      container = document.createElement('div');
      container.className = 'ui-toast-container';
      document.body.appendChild(container);
    }
    return container;
  }

  function removeToast(id) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === id) {
        var item = items[i];
        clearTimeout(item.timer);
        item.el.classList.remove('ui-toast--active');
        item.el.classList.add('ui-toast--exit');
        // 退出动画结束后再移除 DOM；期间保留在 items 中，
        // 以便同文本去重能重新激活退出中的 toast
        item.removalTimer = setTimeout(function() {
          if (item.el.parentNode) item.el.parentNode.removeChild(item.el);
          for (var j = 0; j < items.length; j++) {
            if (items[j].id === id) { items.splice(j, 1); break; }
          }
          // 容器用后即弃，下次 show 时重建
          if (items.length === 0 && container && container.parentNode) {
            container.parentNode.removeChild(container);
            container = null;
          }
        }, 250);
        return;
      }
    }
  }

  return {
    show: function(text, opts) {
      opts = opts || {};
      var type = opts.type || 'info';
      var duration = opts.duration || 2500;

      // 同文本合并去重：重新激活（含退出中的 toast）并重置计时器
      for (var i = 0; i < items.length; i++) {
        if (items[i].text === text) {
          var existing = items[i];
          clearTimeout(existing.timer);
          if (existing.removalTimer) {
            clearTimeout(existing.removalTimer);
            existing.removalTimer = null;
          }
          existing.el.classList.remove('ui-toast--exit');
          existing.el.classList.add('ui-toast--active');
          void existing.el.offsetWidth; // 强制回流，重新触发滑入动画
          existing.timer = setTimeout(function() { removeToast(existing.id); }, duration);
          return;
        }
      }

      // 堆叠上限：超过 3 条挤出最旧的
      while (items.length >= 3) {
        removeToast(items[0].id);
      }

      var id = ++nextId;
      var el = document.createElement('div');
      el.className = 'ui-toast ui-toast--' + type;
      el.textContent = text;
      // 语义：error 用 alert 角色（立即打断），其余 status（温和播报）
      el.setAttribute('role', type === 'error' ? 'alert' : 'status');
      // 点击立即关闭
      el.addEventListener('click', function () { removeToast(id); });

      var ctr = ensureContainer();
      ctr.appendChild(el);

      // 强制回流后触发滑入动画
      el.offsetHeight;
      el.classList.add('ui-toast--active');

      // anime 滑入（渐进增强；退场沿用 CSS .ui-toast--exit）
      if (window.anime) {
        anime({ targets: el, translateY: [-14, 0], opacity: [0, 1], duration: 260, ease: anime.spring({ stiffness: 320, damping: 22 }) });
      }

      var timer = setTimeout(function() {
        removeToast(id);
      }, duration);

      items.push({ id: id, text: text, el: el, timer: timer, removalTimer: null });
    }
  };
})();

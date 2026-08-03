/* 命令式确认框：UiConfirm.show({...}) → Promise<boolean>
   内部动态挂载一个基于 UiModal 的确认实例，用后即焚 */

var UiConfirm = {};

// 模块级活跃实例引用：并发调用时先关闭上一个，避免 modal 叠加
var activeInstance = null;

UiConfirm.show = function(opts) {
  opts = opts || {};
  return new Promise(function(resolve) {
    // 并发保护：已有活跃实例时先 dismiss（resolve(false) + 关闭动画）
    if (activeInstance) {
      activeInstance.dismiss();
      activeInstance = null;
    }

    var div = document.createElement('div');
    document.body.appendChild(div);

    var ConfirmWrapper = {
      template: '#tpl-ui-confirm',
      data: function() {
        return {
          open: true,
          title: opts.title || '确认',
          message: opts.message || '',
          okText: opts.okText || '确定',
          cancelText: opts.cancelText || '取消',
          danger: !!opts.danger
        };
      },
      methods: {
        handleOk: function() {
          this._result = true;
          this.open = false;
        },
        handleCancel: function() {
          this._result = false;
          this.open = false;
        }
      },
      watch: {
        open: function(val) {
          if (!val) {
            var self = this;
            // 等待关闭动画完成（modal leave 0.15s + 50ms 余量）
            setTimeout(function() {
              app.unmount();
              if (div.parentNode) div.parentNode.removeChild(div);
              if (activeInstance && activeInstance.instance === self) {
                activeInstance = null;
              }
              resolve(self._result);
            }, 200);
          }
        }
      }
    };

    var app = Vue.createApp(ConfirmWrapper);
    app.component('ui-modal', UiModal);
    var instance = app.mount(div);

    activeInstance = {
      instance: instance,
      dismiss: function() {
        instance._result = false;
        instance.open = false;
      }
    };
  });
};

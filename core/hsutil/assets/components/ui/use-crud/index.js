/* useCrud 组合式函数 —— 封装增删改查状态与方法
   用法：var crud = useCrud({ load, create, update, remove });
   返回：{ items, loading, error, load, add, edit, del }
   del 内建 UiConfirm 确认（typeof 守卫：未加载时直接删除不确认） */

function useCrud(opts) {
  opts = opts || {};

  var items = Vue.ref([]);
  var loading = Vue.ref(false);
  var error = Vue.ref(null);

  var _load = opts.load || function() { return Promise.resolve([]); };
  var _create = opts.create || function() { return Promise.resolve(); };
  var _update = opts.update || function() { return Promise.resolve(); };
  var _remove = opts.remove || function() { return Promise.resolve(); };

  function load() {
    loading.value = true;
    error.value = null;
    return _load().then(function(data) {
      items.value = data || [];
      return data;
    }).catch(function(err) {
      error.value = err;
      throw err;
    }).finally(function() {
      loading.value = false;
    });
  }

  /* mutation 统一状态管理：开始置 loading，结束清 loading，失败写 error 并重新抛出 */
  function runMutation(fn) {
    loading.value = true;
    error.value = null;
    return fn().then(function(result) {
      loading.value = false;
      return result;
    }).catch(function(err) {
      error.value = (err && err.message !== undefined) ? err.message : String(err);
      loading.value = false;
      // 失败反馈（渐进增强：未加载 toast 时静默，调用方 catch 仍可自行处理）
      if (typeof window.UiToast !== 'undefined' && window.UiToast.show) {
        UiToast.show('操作失败：' + error.value, { type: 'error' });
      }
      throw err;
    });
  }

  function add(data) {
    return runMutation(function() {
      return _create(data).then(function() {
        return load();
      });
    });
  }

  function edit(item) {
    return runMutation(function() {
      return _update(item).then(function() {
        return load();
      });
    });
  }

  function del(item) {
    var doRemove = function() {
      return runMutation(function() {
        return _remove(item).then(function() {
          return load();
        });
      });
    };

    if (typeof window.UiConfirm !== 'undefined' && window.UiConfirm.show) {
      return window.UiConfirm.show({
        title: '确认删除',
        message: '确定要删除吗？',
        danger: true,
        okText: '删除',
        cancelText: '取消'
      }).then(function(confirmed) {
        if (confirmed) return doRemove();
      });
    } else {
      return doRemove();
    }
  }

  return {
    items: items,
    loading: loading,
    error: error,
    load: load,
    add: add,
    edit: edit,
    del: del
  };
}

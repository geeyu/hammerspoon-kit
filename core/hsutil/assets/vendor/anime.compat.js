/* anime v4 → v3 兼容垫片
   v4.5.0 的 UMD 全局 window.anime 是命名空间对象（animate/stagger/spring/...），
   且 v4 的 animate 是双参数签名 animate(targets, parameters)，
   而既有代码（组件动效/glass-fx/消费方）以 v3 风格 anime({targets, ...}) 单对象调用。
   此处包装为可调用函数：拆分 v3 单对象参数 → v4 双参数，并保留全部导出。
   加载顺序：必须紧随 anime.umd.min.js 之后。 */
(function () {
  var ns = window.anime;
  if (!ns || typeof ns === 'function') return;   // 未加载或已是兼容形态
  var callable = function (opts) {
    // v3 风格 anime({targets, ...}) → v4 animate(targets, params)
    if (opts && opts.targets) {
      var params = {};
      for (var k in opts) {
        if (k !== 'targets' && Object.prototype.hasOwnProperty.call(opts, k)) params[k] = opts[k];
      }
      return ns.animate(opts.targets, params);
    }
    return ns.animate(opts, {});
  };
  for (var k in ns) {
    if (Object.prototype.hasOwnProperty.call(ns, k)) callable[k] = ns[k];
  }
  callable.compat = true;
  window.anime = callable;
})();

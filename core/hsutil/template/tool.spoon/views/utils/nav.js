// 多页面 hash 路由骨架：window.ToolNav.open('home')
// current 从 location.pathname 推导（/tool/assets/pages/<page>/index.html），
// 避免硬编码 'home' 导致 settings 页点“回首页”被守卫拦截
var page = (location.pathname.match(/pages\/([\w-]+)\/?/) || [])[1] || 'home';
window.ToolNav = {
  current: page,
  open: function (name) {
    if (name === this.current) return;
    // 跨页面跳转：真实场景由 Lua 层 openPage() 切 webview URL；
    // 单 webview 内多页也可用 iframe/动态加载——模板采用"Lua openPage 切 URL"为主路径，
    // 此处为前端兜底：直接跳转 hash 并 reload 页面。
    window.location.href = '/tool/assets/pages/' + name + '/index.html';
  }
};

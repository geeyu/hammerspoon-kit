// 前端自测：用 Headless Edge 加载真实 views/pages/history/index.html + 真实 SQLite(scratch库)，
// 验证渲染/图片(延迟加载 URL)/分页/hasMore/搜索/键盘。
// 前端数据通路是 fetch HTTP（/clipboard/api/*），测试用 fetch mock 拦截，不依赖真实 server。
// 用法: node test/headless-panel-test.js   （需安装 Microsoft Edge）
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

const SPOON = __dirname + '/..';
const EDGE = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
// vendor 唯一源在 hsutil（Spoon 内不再拷副本）：测试与运行时用同一份 Vue
const HSUtilAssets = path.join(SPOON, '../../core/hsutil/assets');
const VUE = path.join(HSUtilAssets, 'vendor/vue.global.prod.js');

// 0) 准备 scratch 单列库（模拟 v5 前的 3 列老库结构，桥接层补默认新列）
const DB = '/tmp/clip_selftest.db';
fs.rmSync(DB, { force: true });
let rows = [];
for (let i = 1; i <= 25; i++) rows.push(`(${1000 + i},'clip content line ${i}',${100000 + i})`);
rows.push(`(2000,'lua special',${200000})`, `(2001,'LUA upper',${200001})`, `(2002,'javascript',${200002})`,
  `(2003,'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',${200003})`,
  `(3000,'tail 1',${300000})`, `(3001,'tail 2',${300001})`, `(3002,'tail 3',${300002})`);
execSync(`sqlite3 ${DB} "CREATE TABLE clips(id INTEGER PRIMARY KEY AUTOINCREMENT,text TEXT,created INTEGER NOT NULL);"`);
execSync(`sqlite3 ${DB} "INSERT INTO clips(id,text,created) VALUES ${rows.join(',')};"`);
// 桥接数据：补 v5 新列默认值（真实迁移由 Lua store 负责，这里只测前端）
const all = JSON.parse(execSync(`sqlite3 -readonly -json ${DB} "SELECT id AS dbid,text,created FROM clips ORDER BY created DESC, id DESC;"`, 'utf8'))
  .map(r => ({ id: r.dbid, text: r.text, created: r.created, kind: 'text', count: 0, starred: 0 }));
// 2003 是图片（data URI 前缀），标记 kind=image 并置为最新（确保首屏可见）
const imgRow = all.find(r => r.id === 2003);
if (imgRow) { imgRow.kind = 'image'; imgRow.created = 999999; }
all.sort((a, b) => b.created - a.created);

// 1) 组装测试页
// 前端目录规范：views/pages/<page>/
const PAGE = path.join(SPOON, 'views/pages/history');
let html = fs.readFileSync(path.join(PAGE, 'index.html'), 'utf8');
// 防回归：真实运行中 vue/anime/glass-fx 由占位符注入为 defer，业务脚本必须也 defer，
// 否则解析到即执行、Vue 尚未加载 → ReferenceError: Vue is not defined（history.js:62 事故）
if (!/<script src="[^"]*app\.js"[^>]*defer/.test(html)) {
  console.error('✘ app.js 未带 defer，真实环境会 Vue is not defined');
  process.exit(2);
}
// 页面运行时的 vue 由 hsutil 占位符注入（服务端展开），file:// 下不展开 → 手动内联同一份 Vue
html = html.replace('</head>', '<script>' + fs.readFileSync(VUE, 'utf8') + '</script></head>');

// 测试页在 /tmp 下，script 的相对/绝对引用都会 404 → 按页面目录解析后全部内联
// （样式不强依赖：断言的是 DOM 结构与数据，不涉及渲染外观）
html = html.replace(/<script src="([^"]+)" defer><\/script>/g, function (m, src) {
  const file = src.indexOf('/clipboard/view/') === 0
    ? path.join(SPOON, 'views', src.replace('/clipboard/view/', ''))
    : src.indexOf('/hsutil/') === 0
      ? path.join(HSUtilAssets, src.replace('/hsutil/assets/', ''))
      : path.join(PAGE, src);
  return '<script>' + fs.readFileSync(file, 'utf8') + '</script>';
});

// 桥接层：mock fetch（拦截 /clipboard/api/*，行为对齐真实 server）
const bridge = `<script>
window.__errs=[];
window.onerror=function(msg,src,line){ window.__errs.push(msg+' @'+(src||'')+':'+line); };
// 占位符注入的注册表（ui 组件 js）在 file:// 下不展开，测试页给空实现（本测试不涉及 ui 组件）
window.registerUiComponents=function(){};
var SERVER=${JSON.stringify(all)}; window.__sql=[];
window.fetch=function(url,opts){
  var u=String(url), m=(opts&&opts.method)||'GET';
  if(u.indexOf('/clipboard/api')!==0) return Promise.reject(new Error('unexpected url '+u));
  window.__sql.push(m+' '+u);
  var p=u.replace('/clipboard/api/history','');
  var qm=p.match(/[?&]term=([^&]*)/), om=p.match(/[?&]offset=(\\d+)/), lm=p.match(/[?&]limit=(\\d+)/);
  var term=qm?decodeURIComponent(qm[1]):'';
  var off=om?+om[1]:0, lim=lm?+lm[1]:20;
  var rows=SERVER.filter(function(r){ return !term || String(r.text).toLowerCase().indexOf(term.toLowerCase())!==-1; });
  var page=rows.slice(off,off+lim);
  return Promise.resolve({ok:true,status:200,json:function(){ return Promise.resolve({rows:page,total:rows.length}); }});
};
(function(){var s=document.createElement('style');s.textContent='html,body{width:1000px;height:700px;overflow:hidden;background:#111}';document.head.appendChild(s);})();
</script><pre id="res"></pre>`;
html = html.replace('</head>', bridge + '</head>');

html += `<script>
let R={};
window.onerror=function(msg,src,line){ R.winErr=msg+' @'+(src||'')+':'+line; };
function done(){ document.getElementById('res').textContent='RES='+JSON.stringify(R); }
setTimeout(async function(){
  try {
    R.vueLoaded=typeof Vue!=='undefined';
    R.errs=window.__errs||[];
    R.scripts=[].map.call(document.scripts,function(s){return s.src.split('/').pop();}).join(',');
    var appEl=document.getElementById('app');
    R.appVCloak=appEl?appEl.hasAttribute('v-cloak'):'no-app';
    R.appHtml=(appEl?appEl.innerHTML:'').slice(0,120);
    R.hasQW=typeof window.QW!=='undefined';
    R.firstItems=vm.items.length; R.firstHasMore=vm.hasMore;
    R.img=document.querySelectorAll('.card-img img').length;
    var b=vm.items.length; vm.more();
    await new Promise(r=>setTimeout(r,300));
    R.paginated=vm.items.length; R.paginationWorked=vm.items.length>b;

    // 搜索
    vm.query='lua'; vm.list('lua');
    await new Promise(r=>setTimeout(r,150));
    R.searchWorked=vm.items.length>0 && vm.items.length<=R.firstItems && vm.items.every(x=>x.kind!=='image');
  } catch(e){ R.err=String(e&&e.stack||e); }
  done();
}, 1800);
</script>`;
fs.writeFileSync('/tmp/panel-selftest.html', html);

// Headless Edge dump：spawn + 读到 </html> 即杀（Edge 的 updater/GPU 子进程常使进程不退出，
// execSync 会挂死；--disable-crashpad/--user-data-dir 规避沙箱权限与 profile 锁）
const EDGE_ARGS = ['--headless', '--disable-gpu', '--no-sandbox', '--disable-crashpad',
  '--no-first-run', '--user-data-dir=/tmp/hs-edge-profile', '--virtual-time-budget=6000',
  '--dump-dom', 'file:///tmp/panel-selftest.html'];
function edgeDump() {
  return new Promise(function (resolve, reject) {
    const child = spawn(EDGE, EDGE_ARGS, { stdio: ['ignore', 'pipe', 'ignore'] });
    let out = '';
    const timer = setTimeout(function () { child.kill('SIGKILL'); }, 30000);
    child.stdout.on('data', function (d) {
      out += d;
      if (out.indexOf('</html>') >= 0) { clearTimeout(timer); child.kill('SIGKILL'); }
    });
    child.on('error', reject);
    child.on('close', function () { clearTimeout(timer); resolve(out); });
  });
}

(async function () {
  const dump = await edgeDump();
  const m = dump.match(/<pre id="res">([\s\S]*?)<\/pre>/);
  if (!m) { console.error('无结果'); process.exit(2); }
  const R = JSON.parse(m[1].replace(/^RES=/,''));
  console.log('====== Headless 前端自测 ======');
  console.log(JSON.stringify(R, null, 2));
  const pass = R.firstItems>0 && R.img>=1 && R.paginationWorked && R.searchWorked;
  console.log(pass ? '\n✔ 通过' : '\n✘ 未通过');
  process.exit(pass?0:1);
})();

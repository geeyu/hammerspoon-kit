// 前端自测：settings 页（Headless Edge）——验证 panel 尺寸配置的 load/save 编解码。
// 数据通路 mock fetch（/clipboard/api/settings），不依赖真实 server。
// 用法: node test/settings-panel-test.js   （需安装 Microsoft Edge）
'use strict';
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const SPOON = __dirname + '/..';
const EDGE = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
// vendor 唯一源在 hsutil（Spoon 内不再拷副本）：测试与运行时用同一份 Vue
const HSUtilAssets = path.join(SPOON, '../../core/hsutil/assets');
const VUE = path.join(HSUtilAssets, 'vendor/vue.global.prod.js');
const PAGE = path.join(SPOON, 'views/pages/settings');

let html = fs.readFileSync(path.join(PAGE, 'index.html'), 'utf8');
// 页面运行时的 vue 由 hsutil 占位符注入（服务端展开），file:// 下不展开 → 手动内联同一份 Vue
html = html.replace('</head>', '<script>' + fs.readFileSync(VUE, 'utf8') + '</script></head>');
// ui 组件 js 由占位符注入（本测试不渲染 ui 组件，只验 store 逻辑）：空实现注册表
html = html.replace('</head>', '<script>window.registerUiComponents=function(){};</script></head>');
// 页面私有脚本（相对/绝对引用都 404 → 内联）
html = html.replace(/<script src="([^"]+)" defer><\/script>/g, function (m, src) {
  return '<script>' + fs.readFileSync(path.join(PAGE, src), 'utf8') + '</script>';
});

// mock fetch：GET 返回服务端配置（含 panel 比例），POST 捕获 payload
const bridge = `<script>
window.__errs=[];
window.onerror=function(msg,src,line){ window.__errs.push(msg+' @'+(src||'')+':'+line); };
window.__posted=[];
window.fetch=function(url,opts){
  var u=String(url), m=(opts&&opts.method)||'GET';
  if(u.indexOf('/clipboard/api')!==0) return Promise.reject(new Error('unexpected url '+u));
  if(m==='GET') return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve({
    hotkey_show:[['ctrl'],'v'], retain_days:7, max_entries:300, text_only:false,
    panel:{widthRatio:0.52,heightRatio:0.62,yRatio:0.22}
  });}});
  window.__posted.push(JSON.parse(opts.body));
  return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve({ok:true});}});
};
</script><pre id="res"></pre>`;
html = html.replace('</head>', bridge + '</head>');

html += `<script>
let R={};
window.onerror=function(msg,src,line){ R.winErr=msg+' @'+(src||'')+':'+line; };
function done(){ document.getElementById('res').textContent='RES='+JSON.stringify(R); }
setTimeout(async function(){
  try {
    await new Promise(r=>setTimeout(r,300));   // 等 load() 完成
    R.errs=window.__errs||[];
    R.form=JSON.stringify(window.__form);
    // 改动一个值再保存，验证 save 编码
    window.__form.panelWidth=70; window.__form.panelHeight=80; window.__form.panelPos=40;
    window.__save();
    await new Promise(r=>setTimeout(r,200));
    R.posted=JSON.stringify(window.__posted);
  } catch(e){ R.err=String(e&&e.stack||e); }
  done();
}, 500);
</script>`;

// 注入钩子：app.mount 后拿实例（form/save）
html = html.replace(
  "app.mount('#app');",
  "window.__vm=app.mount('#app');\nwindow.__form=window.__vm.form;\nwindow.__save=window.__vm.save.bind(window.__vm);\n"
);

fs.writeFileSync('/tmp/settings-panel-test.html', html);

// Headless Edge dump：spawn + 读到 </html> 即杀（同 headless-panel-test.js 的形态）
const EDGE_ARGS = ['--headless', '--disable-gpu', '--no-sandbox', '--disable-crashpad',
  '--no-first-run', '--user-data-dir=/tmp/hs-edge-profile', '--virtual-time-budget=6000',
  '--dump-dom', 'file:///tmp/settings-panel-test.html'];
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
  const R = JSON.parse(m[1].replace(/^RES=/, ''));
  console.log('====== Headless settings 前端自测 ======');
  console.log(JSON.stringify(R, null, 2));
  // load 填充 panel 百分比字段（52/62/22）+ save 编码回比例（0.70/0.80/0.40）
  let pass = R.errs && R.errs.length === 0;
  const form = R.form && JSON.parse(R.form);
  pass = pass && form && form.panelWidth === 52 && form.panelHeight === 62 && form.panelPos === 22;
  const posted = R.posted && JSON.parse(R.posted)[0];
  pass = pass && posted && posted.panel
    && Math.abs(posted.panel.widthRatio - 0.7) < 1e-9
    && Math.abs(posted.panel.heightRatio - 0.8) < 1e-9
    && Math.abs(posted.panel.yRatio - 0.4) < 1e-9
    && posted.text_only === false;
  console.log(pass ? '\n✔ 通过' : '\n✘ 未通过');
  process.exit(pass ? 0 : 1);
})();

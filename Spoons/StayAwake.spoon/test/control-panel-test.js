// 前端自测：用 Headless Edge 加载真实 views/pages/control/index.html，
// 验证 ui 组件真实注册渲染（含 ui-datetime/flatpickr 日历）、状态卡（激活/终止时间）、
// 先选后启流程（小时/分钟/永久/直到 互斥选择 → 底部动态启动/停止 → 启动后重置）、
// 未选配置点启动的提示拦截（fetch mock 拦截，行为对齐真实 server）。
// 用法: node test/control-panel-test.js   （需安装 Microsoft Edge）
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SPOON = __dirname + '/..';
const EDGE = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
// vendor 唯一源在 hsutil（Spoon 内不再拷副本）：测试与运行时用同一份 Vue
const HSUtilAssets = path.join(SPOON, '../../core/hsutil/assets');
const VUE = path.join(HSUtilAssets, 'vendor/vue.global.prod.js');

// 1) 组装测试页
// 前端目录规范：views/pages/<page>/
const PAGE = path.join(SPOON, 'views/pages/control');
let html = fs.readFileSync(path.join(PAGE, 'index.html'), 'utf8');
// 防回归：真实运行中占位符注入的组件 js 是 defer，业务脚本必须也 defer（保持文档序）
if (!/<script src="[^"]*app\.js"[^>]*defer/.test(html)) {
  console.error('✘ app.js 未带 defer，真实环境会 Vue is not defined');
  process.exit(2);
}
// 页面运行时的 vue + ui 组件 js 由 hsutil 占位符注入（服务端展开），file:// 下不展开 → 手动内联同一份
html = html.replace('</head>', '<script>' + fs.readFileSync(VUE, 'utf8') + '</script></head>');
// 移除页面 css link：file:// 下跨源 stylesheet 会让 flatpickr 的 cssRules 检测抛 SecurityError（http 同源无此问题）
html = html.replace(/<link rel="stylesheet"[^>]*>/g, '');
// 按占位符声明内联 ui 组件 js（与 hsutil ui.lua 拓扑序一致：依赖/vendor 在前，注册表最后）
const UI_JS = [
  'vendor/flatpickr/flatpickr.min.js',   // ui-datetime vendor
  'vendor/flatpickr/zh.js',
  'components/ui/ui-icon/index.js',      // ui-select / ui-datetime 依赖
  'components/ui/ui-button/index.js',
  'components/ui/ui-radio/index.js',
  'components/ui/ui-select/index.js',
  'components/ui/ui-datetime/index.js',
  'components/ui/ui-toast/index.js',
  'components/ui/index.js',              // 注册表：registerUiComponents
];
html = html.replace('</head>', UI_JS.map(function (f) {
  return '<script>' + fs.readFileSync(path.join(HSUtilAssets, f), 'utf8') + '</script>';
}).join('\n') + '</head>');
// 组件 tpl（ui-button/ui-select 用 #tpl-ui-* 模板引用，服务端同样内联）
html = html.replace('</head>', [
  'components/ui/ui-button/ui-button.tpl.html',
  'components/ui/ui-select/ui-select.tpl.html',
].map(function (f) {
  return fs.readFileSync(path.join(HSUtilAssets, f), 'utf8');
}).join('\n') + '</head>');
html = html.replace(/<script src="([^"]+)" defer><\/script>/g, function (m, src) {
  const file = src.indexOf('/stayawake/view/') === 0
    ? path.join(SPOON, 'views', src.replace('/stayawake/view/', ''))
    : src.indexOf('/hsutil/') === 0
      ? path.join(HSUtilAssets, src.replace('/hsutil/assets/', ''))
      : path.join(PAGE, src);
  return '<script>' + fs.readFileSync(file, 'utf8') + '</script>';
});

// 桥接层：mock fetch（拦截 /stayawake/api/*，行为对齐真实 server：action 后状态变化）
// 注意：/stayawake/api/state 必须返回深拷贝——真实 server 每次返回新对象，同一引用赋值不触发 Vue ref 更新
const bridge = `<script>
window.__errs=[]; window.__calls=[];
window.onerror=function(msg,src,line){ window.__errs.push(msg+' @'+(src||'')+':'+line); };
var STATE={active:false,type:'',mode:'system',remaining:0,endsAt:null};
window.fetch=function(url,opts){
  var u=String(url), o=opts||{};
  if(u==='/stayawake/api/state'){
    window.__calls.push('STATE');
    return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve(JSON.parse(JSON.stringify(STATE)));}});
  }
  if(u==='/stayawake/api/action'){
    var body=JSON.parse(o.body||'{}');
    window.__calls.push(body.action+(body.minutes!=null?':'+body.minutes:'')+(body.mode?':'+body.mode:'')+(body.endsAt?':'+body.endsAt:''));
    if(body.action==='mode') STATE.mode=body.mode;
    if(body.action==='close'){ STATE.active=false; STATE.type=''; STATE.remaining=0; STATE.endsAt=null; }
    if(body.action==='timer'||body.action==='until'){
      STATE.active=true; STATE.type=body.action; STATE.remaining=7200; STATE.endsAt='2026-08-02 18:30:00';
    }
    if(body.action==='permanent'){ STATE.active=true; STATE.type='permanent'; STATE.remaining=null; STATE.endsAt='2026-08-02 18:30:00'; }
    return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve({ok:true,msg:'ok'});}});
  }
  return Promise.reject(new Error('unexpected url '+u));
};
(function(){var s=document.createElement('style');s.textContent='html,body{width:900px;height:760px;overflow:hidden;background:#111}';document.head.appendChild(s);})();
</script><pre id="res"></pre>`;
html = html.replace('</head>', bridge + '</head>');

html += `<script>
let R={};
function done(){ document.getElementById('res').textContent='RES='+JSON.stringify(R); }
function selBtns(){ return [].slice.call(document.querySelectorAll('.ui-btn')); }
function btnByText(t){ var f=selBtns().filter(function(b){return b.textContent.indexOf(t)!==-1;}); return f[0]; }
function openSelect(i){
  document.querySelectorAll('.ui-select__btn')[i].click();
  return new Promise(function(r){ setTimeout(r,120); });
}
function pickOption(text){
  var opts=[].slice.call(document.querySelectorAll('.ui-select__option'));
  var o=opts.filter(function(x){return x.textContent.indexOf(text)!==-1;})[0];
  o.click();
  return new Promise(function(r){ setTimeout(r,120); });
}
function actions(){ return window.__calls.filter(function(c){return c!=='STATE';}); }
function wait(ms){ return new Promise(function(r){ setTimeout(r,ms); }); }
setTimeout(async function(){
  try {
    R.errs=window.__errs||[];
    // ── 1) 组件真实注册渲染 ──
    R.hasBtn=document.querySelectorAll('.ui-btn').length;
    R.hasRadio=document.querySelectorAll('.ui-radio__item').length;
    R.hasSelect=document.querySelectorAll('.ui-select__btn').length;   // 小时/分钟/永久
    R.hasDatetime=document.querySelectorAll('.ui-datetime input').length;
    R.nativeLeftover=document.querySelectorAll('ui-button,ui-radio-group,ui-select,ui-datetime').length;

    // ── 2) 初始（未激活）：状态卡 + 绿色启动按钮 ──
    var main=document.querySelector('.status-main');
    R.statusIdle=main && main.textContent==='系统正常睡眠';
    R.linesIdle=document.querySelectorAll('.status-line').length;   // 仅模式行，无终止时间
    R.hasLaunchBtn=!!btnByText('▶ 启动') && !btnByText('■ 停止');
    R.launchIsSuccess=btnByText('▶ 启动') && btnByText('▶ 启动').className.indexOf('ui-btn--success')!==-1;

    // ── 3) 未选配置点启动 → 拦截提示，无 action 调用 ──
    btnByText('▶ 启动').click();
    await wait(120);
    R.noConfigBlocked=actions().length===0;

    // ── 4) 小时：选 3 小时 → 启动 → timer:180 → 状态卡激活 + 下拉重置 ──
    await openSelect(0); await pickOption('3 小时');
    btnByText('▶ 启动').click();
    await wait(200);
    R.hourWorked=actions().indexOf('timer:180')!==-1;
    R.stopBtnShown=!!btnByText('■ 停止') && !btnByText('▶ 启动');
    R.statusActive=main.textContent.indexOf('保持清醒中')!==-1;
    R.endsAtShown=document.querySelectorAll('.status-line').length===2
      && document.querySelectorAll('.status-line')[1].textContent.indexOf('终止时间：2026-08-02 18:30:00')!==-1;
    R.hourReset=document.querySelectorAll('.ui-select__btn')[0].textContent.indexOf('选择小时')!==-1;

    // ── 5) 互斥：选小时再选分钟 → 小时清空；启动 → timer:30 ──
    btnByText('■ 停止').click();
    await wait(200);
    await openSelect(0); await pickOption('8 小时');
    await openSelect(1); await pickOption('30 分钟');
    R.exclusive=document.querySelectorAll('.ui-select__btn')[0].textContent.indexOf('选择小时')!==-1
      && document.querySelectorAll('.ui-select__btn')[1].textContent.indexOf('30 分钟')!==-1;
    btnByText('▶ 启动').click();
    await wait(200);
    R.minuteWorked=actions().indexOf('timer:30')!==-1;

    // ── 6) 激活中修改配置 → 黄色「重置」→ 点击 → permanent + 配置重置 + 回停止 ──
    await openSelect(2); await pickOption('永久保持清醒');
    R.resetBtnShown=!!btnByText('⟳ 重置')
      && btnByText('⟳ 重置').className.indexOf('ui-btn--warning')!==-1
      && !btnByText('■ 停止') && !btnByText('▶ 启动');
    btnByText('⟳ 重置').click();
    await wait(200);
    R.foreverWorked=actions().indexOf('permanent')!==-1;
    R.afterResetBackToStop=!!btnByText('■ 停止') && !btnByText('⟳ 重置');
    R.foreverReset=document.querySelectorAll('.ui-select__btn')[2].textContent.indexOf('选择永久')!==-1;

    // ── 7) 直到：flatpickr 日历选今天 → 确定 → 启动 → until:<今天 HH:mm:00> ──
    btnByText('■ 停止').click();
    await wait(200);
    var di=document.querySelector('.ui-datetime input');
    di.focus(); di.click();   // headless 下 click() 不触发 focus，flatpickr 靠 focus 打开
    await wait(300);
    R.calOpen=document.querySelectorAll('.flatpickr-calendar.open').length>0;
    var day=document.querySelector('.flatpickr-day.today:not(.flatpickr-disabled)');
    R.todayFound=!!day;
    day.click();
    await wait(200);
    R.noConfirmBtn=!btnByText('确定');   // 体验一致性：与其他配置一样选完即选中
    btnByText('▶ 启动').click();
    await wait(250);
    var hasUntil=actions().some(function(c){ return /^until:\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:00$/.test(c); });
    R.untilWorked=hasUntil;
  } catch(e){ R.err=String(e&&e.stack||e); }
  done();
}, 1500);
</script>`;
fs.writeFileSync('/tmp/stayawake-ctrl-test.html', html);

const dump = execSync(
  `${JSON.stringify(EDGE)} --headless --disable-gpu --no-sandbox --virtual-time-budget=8000 --dump-dom file:///tmp/stayawake-ctrl-test.html 2>/dev/null`,
  { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
const m = dump.match(/<pre id="res">([\s\S]*?)<\/pre>/);
if (!m) { console.error('无结果'); process.exit(2); }
const R = JSON.parse(m[1].replace(/^RES=/,''));
console.log('====== Headless 前端自测（control 页）======');
console.log(JSON.stringify(R, null, 2));
const pass = R.hasBtn>0 && R.hasRadio===2 && R.hasSelect===3 && R.hasDatetime===1 && R.nativeLeftover===0
  && R.statusIdle && R.linesIdle===1 && R.hasLaunchBtn && R.launchIsSuccess
  && R.noConfigBlocked && R.hourWorked && R.stopBtnShown && R.statusActive && R.endsAtShown && R.hourReset
  && R.exclusive && R.minuteWorked
  && R.resetBtnShown && R.foreverWorked && R.afterResetBackToStop && R.foreverReset
  && R.calOpen && R.todayFound && R.noConfirmBtn && R.untilWorked && (R.errs||[]).length===0;
console.log(pass ? '\n✔ 通过' : '\n✘ 未通过');
process.exit(pass?0:1);

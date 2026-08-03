// 前端自测：用 Headless Edge 加载真实 views/pages/settings/index.html，
// 验证 ui 组件真实注册渲染（ui-switch/ui-hotkey/ui-button）、10 个功能行（防睡眠设置页风格：
// 每行左标签右控件）、拨开关改动即保存（fetch mock 拦截，行为对齐真实 server）、
// 热键录制全链路（focus → remote guard start → poll 拿结果 → 自动保存）、
// 关闭的功能热键置灰、快捷键冲突拦截并回滚。
// 用法: node test/settings-panel-test.js   （需安装 Microsoft Edge）
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
const PAGE = path.join(SPOON, 'views/pages/settings');
let html = fs.readFileSync(path.join(PAGE, 'index.html'), 'utf8');
// 防回归：真实运行中占位符注入的组件 js 是 defer，业务脚本必须也 defer（保持文档序）
if (!/<script src="[^"]*app\.js"[^>]*defer/.test(html)) {
  console.error('✘ app.js 未带 defer，真实环境会 Vue is not defined');
  process.exit(2);
}
// 页面运行时的 vue + ui 组件 js 由 hsutil 占位符注入（服务端展开），file:// 下不展开 → 手动内联同一份
html = html.replace('</head>', '<script>' + fs.readFileSync(VUE, 'utf8') + '</script></head>');
// 移除页面 css link：file:// 下跨源 stylesheet 的 cssRules 检测会抛 SecurityError（http 同源无此问题）
html = html.replace(/<link rel="stylesheet"[^>]*>/g, '');
// 按占位符声明内联 ui 组件 js（与 hsutil ui.lua 拓扑序一致：依赖/vendor 在前，注册表最后）
const UI_JS = [
  'components/ui/ui-button/index.js',      // 页头返回按钮
  'components/ui/ui-switch/index.js',      // 启用开关
  'components/ui/ui-hotkey/index.js',      // 热键录制（remote 模式）
  'components/ui/ui-toast/index.js',
  'components/ui/index.js',                // 注册表：registerUiComponents
];
html = html.replace('</head>', UI_JS.map(function (f) {
  return '<script>' + fs.readFileSync(path.join(HSUtilAssets, f), 'utf8') + '</script>';
}).join('\n') + '</head>');
// 组件 tpl（ui-button/ui-hotkey 用 #tpl-ui-* 模板引用，服务端同样内联）
html = html.replace('</head>', [
  'components/ui/ui-button/ui-button.tpl.html',
  'components/ui/ui-hotkey/ui-hotkey.tpl.html',
].map(function (f) {
  return fs.readFileSync(path.join(HSUtilAssets, f), 'utf8');
}).join('\n') + '</head>');
html = html.replace(/<script src="([^"]+)" defer><\/script>/g, function (m, src) {
  const file = src.indexOf('/quantumwindow/view/') === 0
    ? path.join(SPOON, 'views', src.replace('/quantumwindow/view/', ''))
    : src.indexOf('/hsutil/') === 0
      ? path.join(HSUtilAssets, src.replace('/hsutil/assets/', ''))
      : path.join(PAGE, src);
  return '<script>' + fs.readFileSync(file, 'utf8') + '</script>';
});

// 桥接层：mock fetch（拦截 /quantumwindow/api/*，行为对齐真实 server）。
// config 初始：10 个动作默认启用；POST 后按 payload 更新内存（深拷贝——真实 server 每次返回新对象）。
const bridge = `<script>
window.__errs=[]; window.__calls=[];
window.onerror=function(msg,src,line){ window.__errs.push(msg+' @'+(src||'')+':'+line); };
var ACTIONS=['left_half','right_half','top_half','bottom_half','space_left','space_right','screen_north','screen_south','toggleFullscreen','centerAbsolute'];
var LABELS={left_half:'左半屏',right_half:'右半屏',top_half:'上半屏',bottom_half:'下半屏',space_left:'上一个 Space',space_right:'下一个 Space',screen_north:'上方屏幕',screen_south:'下方屏幕',toggleFullscreen:'铺满窗口',centerAbsolute:'居中窗口'};
var DESCS={left_half:'窗口贴到左半屏',right_half:'窗口贴到右半屏',top_half:'窗口贴到上半屏',bottom_half:'窗口贴到下半屏',space_left:'窗口移到上一个 Space',space_right:'窗口移到下一个 Space',screen_north:'窗口移到上方显示器',screen_south:'窗口移到下方显示器',toggleFullscreen:'当前 Space 内铺满，可还原',centerAbsolute:'居中并调整到绝对尺寸'};
var DEFAULTS={left_half:'ctrl+alt+cmd+Left',right_half:'ctrl+alt+cmd+Right',top_half:'ctrl+alt+cmd+Up',bottom_half:'ctrl+alt+cmd+Down',space_left:'ctrl+cmd+Left',space_right:'ctrl+cmd+Right',screen_north:'ctrl+cmd+Up',screen_south:'ctrl+cmd+Down',toggleFullscreen:'ctrl+alt+cmd+M',centerAbsolute:'ctrl+alt+cmd+C'};
var STORE={};   // {key:{enabled,hotkey}} 覆盖
var recording=false;
window.fetch=function(url,opts){
  var u=String(url), o=opts||{};
  if(u==='/quantumwindow/api/config' && (!o.method||o.method==='GET')){
    window.__calls.push('GET');
    var list=ACTIONS.map(function(k){
      var ov=STORE[k]||{};
      return {key:k,group:'',label:LABELS[k],desc:DESCS[k],
        enabled: ov.enabled!==false, hotkey: (ov.hotkey||DEFAULTS[k])};
    });
    return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve({actions:list});}});
  }
  if(u==='/quantumwindow/api/config' && o.method==='POST'){
    var body=JSON.parse(o.body||'{}');
    var acts=body.actions||{};
    window.__calls.push('POST:'+Object.keys(acts).filter(function(k){return acts[k].enabled===false;}).join(',')
      +':'+Object.keys(acts).filter(function(k){return acts[k].hotkey!==DEFAULTS[k];}).map(function(k){return k+'='+acts[k].hotkey;}).join(','));
    Object.keys(acts).forEach(function(k){ STORE[k]={enabled:acts[k].enabled,hotkey:acts[k].hotkey}; });
    return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve({ok:true});}});
  }
  if(u==='/quantumwindow/api/hotkey-guard'){
    var b=JSON.parse(o.body||'{}');
    window.__calls.push('GUARD:'+b.action);
    recording=(b.action==='start');
    return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve({ok:true});}});
  }
  if(u==='/quantumwindow/api/hotkey-guard/poll'){
    window.__calls.push('POLL');
    return Promise.resolve({ok:true,status:200,json:function(){
      return Promise.resolve({result: recording ? window.__recordResult || null : null});
    }});
  }
  return Promise.reject(new Error('unexpected url '+u));
};
(function(){var s=document.createElement('style');s.textContent='html,body{width:900px;height:820px;overflow:hidden;background:#111}';document.head.appendChild(s);})();
</script><pre id="res"></pre>`;
html = html.replace('</head>', bridge + '</head>');

html += `<script>
let R={};
function done(){ document.getElementById('res').textContent='RES='+JSON.stringify(R); }
function wait(ms){ return new Promise(function(r){ setTimeout(r,ms); }); }
function switches(){ return [].slice.call(document.querySelectorAll('.ui-switch')); }
function hotkeyInputs(){ return [].slice.call(document.querySelectorAll('.ui-hotkey input')); }
function rows(){ return [].slice.call(document.querySelectorAll('.setting-row')); }
function posts(){ return window.__calls.filter(function(c){return c.indexOf('POST:')===0;}); }
function toasts(){ return [].slice.call(document.querySelectorAll('.ui-toast, .ui-toast__item')); }
setTimeout(async function(){
  try {
    R.errs=window.__errs||[];
    R.calls=window.__calls.slice(0, 60);
    // ── 1) 组件真实注册渲染：10 行，每行 switch + hotkey ──
    await wait(400);
    R.rowCount=rows().length;
    R.switchCount=switches().length;
    R.hotkeyCount=hotkeyInputs().length;
    R.nativeLeftover=document.querySelectorAll('ui-switch,ui-hotkey,ui-button').length;
    R.firstLabel=rows()[0] && rows()[0].querySelector('.setting-name').textContent;
    R.lastLabel=rows()[9] && rows()[9].querySelector('.setting-name').textContent;
    R.firstHotkey=hotkeyInputs()[0] && hotkeyInputs()[0].value;
    R.returnBtn=!!document.querySelector('.ui-btn') && document.querySelector('.ui-btn').textContent.indexOf('返回')!==-1;

    // ── 2) 拨开关（第 1 行 左半屏 关闭）→ 改动即保存 POST ──
    switches()[0].click();
    await wait(250);
    var p0=posts()[posts().length-1];
    R.toggleSaved=p0 && p0.indexOf('left_half')!==-1;
    R.hotkeyDisabledAfterOff=hotkeyInputs()[0].disabled;
    // 再拨回开
    switches()[0].click();
    await wait(250);

    // ── 3) 热键录制全链路：focus → guard start → poll 拿结果 → 值更新 + 自动保存 ──
    window.__recordResult='ctrl+alt+cmd+Q';
    hotkeyInputs()[2].focus();     // top_half
    await wait(900);               // 覆盖 500ms poll 周期
    R.recordedValue=hotkeyInputs()[2].value;
    R.guardStarted=window.__calls.indexOf('GUARD:start')!==-1;
    R.guardStopped=window.__calls.indexOf('GUARD:stop')!==-1;
    R.recordSaved=posts().some(function(c){return c.indexOf('top_half=ctrl+alt+cmd+Q')!==-1;});
    // 结束后 input 失焦（capturing 结束）
    R.captureEnded=hotkeyInputs()[2].value==='Ctrl+Alt+Cmd+Q' && !document.querySelectorAll('.ui-hotkey--capturing').length;

    // ── 4) 冲突：把 right_half 也录成 ctrl+alt+cmd+Q → 拦截 + 回滚 + 错误提示 ──
    var before=posts().length;
    window.__recordResult='ctrl+alt+cmd+Q';
    hotkeyInputs()[1].focus();     // right_half
    await wait(900);
    R.conflictBlocked=posts().length===before;
    R.conflictRolledBack=hotkeyInputs()[1].value==='Ctrl+Alt+Cmd+Right';   // 回滚到上次保存值
    R.conflictToast=!!document.querySelector('.ui-toast--error') || (toasts().length>0);

    // ── 5) Esc 清空语义（remote 下由 guard 处理，前端 clear 按钮点击清空 → 保存空热键）──
    var clearBtn=document.querySelectorAll('.ui-hotkey__clear')[2];
    R.clearShown=!!clearBtn;
    if(clearBtn){ clearBtn.click(); await wait(250); }
    R.clearSaved=posts().some(function(c){return c.indexOf('top_half=')!==-1 && c.indexOf('top_half=ctrl')===-1;});
  } catch(e){ R.err=String(e&&e.stack||e); }
  done();
}, 1000);
</script>`;
fs.writeFileSync('/tmp/qw-settings-test.html', html);

const dump = execSync(
  `${JSON.stringify(EDGE)} --headless --disable-gpu --no-sandbox --virtual-time-budget=12000 --dump-dom file:///tmp/qw-settings-test.html 2>/dev/null`,
  { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
const m = dump.match(/<pre id="res">([\s\S]*?)<\/pre>/);
if (!m) { console.error('无结果'); process.exit(2); }
const R = JSON.parse(m[1].replace(/^RES=/,''));
console.log('====== Headless 前端自测（settings 页）======');
console.log(JSON.stringify(R, null, 2));
const pass = R.rowCount===10 && R.switchCount===10 && R.hotkeyCount===10 && R.nativeLeftover===0
  && R.firstLabel==='左半屏' && R.lastLabel==='居中窗口' && R.firstHotkey==='Ctrl+Alt+Cmd+Left' && R.returnBtn
  && R.toggleSaved && R.hotkeyDisabledAfterOff
  && R.recordedValue==='Ctrl+Alt+Cmd+Q' && R.guardStarted && R.guardStopped && R.recordSaved && R.captureEnded
  && R.conflictBlocked && R.conflictRolledBack && R.conflictToast
  && R.clearShown && R.clearSaved
  && !R.err && (R.errs||[]).length===0;
console.log(pass ? '\n✔ 通过' : '\n✘ 未通过');
process.exit(pass?0:1);

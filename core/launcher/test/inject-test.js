// launcher 应用搜索注入（Tab Inject）headless 自测：
// 验证 pages 候选带 searchUrl、Tab 注入 chip/iframe、query/key 转发、移除注入。
// 用法: node core/launcher/test/inject-test.js   （需安装 Microsoft Edge）
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(__dirname, '../../..');   // ~/.hammerspoon
const EDGE = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
const HSUtilAssets = path.join(ROOT, 'core/hsutil/assets');
const PAGE = path.join(ROOT, 'core/launcher/views/pages/launcher');

let html = fs.readFileSync(path.join(PAGE, 'index.html'), 'utf8');
// 内联 vue + 组件 + store/app（file:// 下占位符不展开）
html = html.replace('</head>', '<script>' + fs.readFileSync(path.join(HSUtilAssets, 'vendor/vue.global.prod.js'), 'utf8') + '</script></head>');
html = html.replace(/<link rel="stylesheet"[^>]*>/g, '');
const UI_JS = [
  'components/ui/ui-icon/index.js',
  'components/ui/ui-toast/index.js',
  'components/ui/index.js',
];
html = html.replace('</head>', UI_JS.map(f => '<script>' + fs.readFileSync(path.join(HSUtilAssets, f), 'utf8') + '</script>').join('\n') + '</head>');
html = html.replace(/<script src="([^"]+)" defer><\/script>/g, (m, src) => {
  const file = src.indexOf('/launcher/view/') === 0
    ? path.join(ROOT, 'core/launcher/views', src.replace('/launcher/view/', ''))
    : src.indexOf('/hsutil/') === 0 ? path.join(HSUtilAssets, src.replace('/hsutil/assets/', ''))
    : path.join(PAGE, src);
  return '<script>' + fs.readFileSync(file, 'utf8') + '</script>';
});

// mock fetch：/launcher/api/*（query 返回带 searchUrl 的候选 + 全局行）
const bridge = `<script>
window.__errs = []; window.__msgs = [];
window.onerror = function (m, s, l) { window.__errs.push(m); };
window.fetch = function (url, opts) {
  var u = String(url), o = opts || {};
  if (u.indexOf('/launcher/api/query') === 0) {
    var text = decodeURIComponent((u.match(/text=([^&]*)/) || [])[1] || '');
    var rows = [];
    if (!text) {
      rows = [
        { text: '文件搜索', subText: '文件搜索配置', icon: '🔍', type: 'cardPage', pageUrl: '/filesearch/view/pages/settings/index.html', searchUrl: '/filesearch/view/pages/search/index.html', plugin: 'cards' },
        { text: '剪贴板', subText: '剪贴板设置', icon: '📋', type: 'cardPage', pageUrl: '/clipboard/view/pages/settings/index.html', searchUrl: '/clipboard/view/pages/history/index.html', plugin: 'cards' },
      ];
    } else if (text === '剪') {
      rows = [{ text: '剪贴板', subText: '剪贴板设置', icon: '📋', type: 'cardPage', pageUrl: '/clipboard/view/pages/settings/index.html', searchUrl: '/clipboard/view/pages/history/index.html', plugin: 'cards' }];
    } else {
      rows = [{ text: 'Chrome', subText: '应用', icon: 'x', type: 'launchOrFocus', plugin: 'apps' }];
    }
    return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve({ rows: rows }); } });
  }
  if (u.indexOf('/launcher/api/run') === 0 || u.indexOf('/launcher/api/close') === 0) {
    return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve({ ok: true }); } });
  }
  return Promise.reject(new Error('unexpected ' + u));
};
</script><pre id="res"></pre>`;
html = html.replace('</head>', bridge + '</head>');

html += `<script>
let R = {};
function done() { document.getElementById('res').textContent = 'RES=' + JSON.stringify(R); }
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
function input(el, v) { el.value = v; el.dispatchEvent(new Event('input', { bubbles: true })); }
function key(el, k) { el.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); }
setTimeout(async function () {
  try {
    const q = document.querySelector('.ut-inputbar input');
    R.inputFound = !!q;
    await wait(300);

    // 1) 搜索「剪」→ 列表出现「剪贴板」候选（带 searchUrl）
    input(q, '剪');
    await wait(500);
    var row = [].slice.call(document.querySelectorAll('.ut-row')).find(r => r.textContent.indexOf('剪贴板') !== -1);
    R.candFound = !!row;
    R.candSelected = row && row.className.indexOf('selected') !== -1;

    // 2) Tab 注入 → chip 出现 + iframe 出现（src 带 embed=1）
    key(q, 'Tab');
    await wait(400);
    R.keyLog = window.__kd || '';
    R.chipShown = !!document.querySelector('.ut-chip');
    R.chipText = document.querySelector('.ut-chip') ? document.querySelector('.ut-chip').textContent : '';
    R.frameShown = !!document.getElementById('app-search-frame');
    R.frameSrc = document.getElementById('app-search-frame') ? document.getElementById('app-search-frame').src : '';
    R.frameEmbed = R.frameSrc.indexOf('embed=1') !== -1;

    // 3) 注入后输入 → postMessage 转发（hook window.postMessage？iframe contentWindow 需要真实 iframe；
    //    注入后输入框输入 → 无 /query 请求（被转发），检查 fetch 调用计数）
    var fetchCount = 0;
    var origFetch = window.fetch;
    window.fetch = function (u, o) { if (String(u).indexOf('/query') !== -1) fetchCount++; return origFetch(u, o); };
    input(q, 'abc');
    await wait(400);
    R.noGlobalQueryWhileInjected = fetchCount === 0;
    window.fetch = origFetch;

    // 4) Esc 移除注入 → chip 消失 + 列表回来
    key(q, 'Escape');
    await wait(300);
    R.chipGone = !document.querySelector('.ut-chip');
    R.frameGone = !document.getElementById('app-search-frame');

    // 5) 无 searchUrl 的卡（Chrome）Tab → 不注入（toast 提示）
    input(q, 'chrome');
    await wait(500);
    key(q, 'Tab');
    await wait(300);
    R.noInjectForPlainApp = !document.querySelector('.ut-chip');

    // 6) 列表模式 Enter：cardPage 卡 → 打开子页面 iframe（pageOpen）
    input(q, '剪');
    await wait(500);
    key(q, 'Enter');
    await wait(400);
    R.enterOpensPage = !!document.querySelector('.page-frame') && document.querySelector('.page-frame').style.display !== 'none';
    R.pageSrc = document.querySelector('.page-frame') ? document.querySelector('.page-frame').src : '';
    R.errs = window.__errs;
  } catch (e) { R.err = String(e && e.stack || e); }
  done();
}, 1200);
</script>`;
fs.writeFileSync('/tmp/launcher-inject-test.html', html);

const dump = execSync(
  `${JSON.stringify(EDGE)} --headless --disable-gpu --no-sandbox --virtual-time-budget=10000 --dump-dom file:///tmp/launcher-inject-test.html 2>/dev/null`,
  { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
const m = dump.match(/<pre id="res">([\s\S]*?)<\/pre>/);
if (!m) { console.error('无结果'); process.exit(2); }
const R = JSON.parse(m[1].replace(/^RES=/, ''));
console.log('====== Headless 注入流程自测 ======');
console.log(JSON.stringify(R, null, 2));
const pass = R.inputFound && R.candFound && R.candSelected
  && R.chipShown && R.chipText.indexOf('剪贴板') !== -1 && R.frameShown && R.frameEmbed
  && R.noGlobalQueryWhileInjected && R.chipGone && R.frameGone
  && R.noInjectForPlainApp && R.enterOpensPage && R.pageSrc.indexOf('settings') !== -1
  && (R.errs || []).length === 0;
console.log(pass ? '\n✔ 通过' : '\n✘ 未通过');
process.exit(pass ? 0 : 1);

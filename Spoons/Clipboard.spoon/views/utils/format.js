// views/utils/format.js —— 剪贴板条目格式化纯函数（无 DOM 依赖，页面共享）
// 暴露全局 ClipFormat；加载顺序在 store.js 之前（defer）
var ClipFormat = (function () {
  // 相对时间文本：今天/昨天用相对日期，更早显示 MM-DD，跨年带年份
  function timeText(created) {
    if (!created || created <= 0) return '';
    var d = new Date((created || 0) * 1000);
    if (isNaN(d.getTime())) return '';
    var now = new Date();
    var p = function (n) { return (n < 10 ? '0' : '') + n; };
    var hm = p(d.getHours()) + ':' + p(d.getMinutes());
    var startOfDay = function (t) {
      var x = new Date(t);
      x.setHours(0, 0, 0, 0);
      return x.getTime();
    };
    // Math.round 规避夏令时切换导致的整日偏差
    var dayDiff = Math.round((startOfDay(now) - startOfDay(d)) / 86400000);
    if (dayDiff === 0) return '今天 ' + hm;
    if (dayDiff === 1) return '昨天 ' + hm;
    if (d.getFullYear() === now.getFullYear()) {
      return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + hm;
    }
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + hm;
  }

  // 检测内容类型（kind 后端已存 image/text；文本细分 link/code 由前端判）
  function detectSubKind(text, kind) {
    if (kind === 'image') return 'image';
    if (!text) return 'text';
    if (/^https?:\/\/\S+$/i.test(text.trim())) return 'link';
    var codeSignals = [
      /[{};]\s*$/, /=>/,
      /^\s*(def |class |import |from |export |const |let |var |function )/m,
      /<\/\w+>/, /^\s*#(include|define|pragma)/m,
      /\b(return|if|else|for|while)\b.*[{(]/, /^\s*\$\s+/m
    ];
    var score = 0;
    for (var i = 0; i < codeSignals.length; i++) if (codeSignals[i].test(text)) score++;
    if (score >= 2) return 'code';
    if (text.indexOf('\n') >= 0 && /[{}();]/.test(text)) return 'code';
    return 'text';
  }

  return { timeText: timeText, detectSubKind: detectSubKind };
})();

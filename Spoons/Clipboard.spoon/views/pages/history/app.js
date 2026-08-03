// views/pages/history/app.js —— 页面逻辑（UI/键盘/动画），数据层在 store.js
var { createApp } = Vue;
var app = createApp({
  inject: ['clipStore'],
  data: function () {
    return {
      query: '',          // 输入框实时内容（防抖后才是搜索词）
      selected: 0,        // 选中下标
      detailOpen: false,  // 详情面板
      animateCards: true, // 进场动画开关（仅空→有播放）
      // Tab 注入 embed 模式（launcher iframe?embed=1）：隐藏搜索栏，输入/键盘由 launcher 转发
      isEmbed: new URLSearchParams(location.search).get('embed') === '1',
      _debounce: null,
      _scrollRAF: null,
      _scrollSelRAF: null,
    };
  },
  computed: {
    items: function () { return this.clipStore.state.items; },
    total: function () { return this.clipStore.state.total; },
    hasMore: function () { return this.clipStore.state.hasMore; },
    loading: function () { return this.clipStore.state.loading; },
    term: function () { return this.clipStore.state.term; },
    current: function () { return this.items[this.selected] || null; },
  },
  methods: {
    // ===== 数据（store 代理：UI 状态 + 动画在此）=====
    list: function (term) {
      var wasEmpty = this.items.length === 0;
      this.animateCards = wasEmpty;   // 仅空→有时播进场动画（搜索不重播全量进场）
      this.selected = 0;
      var self = this;
      return this.clipStore.list(term, wasEmpty).then(function () {
        self.$nextTick(function () { self.scrollToSelected(); });
      });
    },
    more: function () {
      var self = this;
      if (this.loading || !this.hasMore) return;
      this.animateCards = false;   // 翻页追加：不重播进场动画
      var oldLen = this.items.length;
      this.clipStore.more().then(function () {
        self.$nextTick(function () {
          // 新翻出的卡片用 anime 错峰进场（首次加载走 CSS .card-enter）
          if (!window.anime || !self.$refs.list) return;
          var fresh = [].slice.call(self.$refs.list.querySelectorAll('.card')).slice(oldLen);
          if (!fresh.length) return;
          fresh.forEach(function (el) { el.style.transition = 'none'; });
          anime({
            targets: fresh,
            opacity: [0, 1], translateY: [16, 0],
            duration: 380, ease: 'outCubic',
            delay: anime.stagger(28),
            onComplete: function (anim) {
              anim.targets.forEach(function (t) {
                t.style.transform = ''; t.style.transition = '';
              });
            }
          });
        });
      });
    },
    silentRefresh: function () {
      var self = this;
      this.clipStore.silentRefresh().then(function () {
        // 复制后条目已置顶：选择框跟随回顶部（列表重排后顶部即最新）
        self.selected = 0;
        self.scrollToSelected();
      });
    },

    // ===== 输入 =====
    onQuery: function () {
      if (this._debounce) clearTimeout(this._debounce);
      var self = this;
      this._debounce = setTimeout(function () {
        self._debounce = null;
        var cur = (self.query || '').trim();
        // 限流去重：相同 term 不重复搜索。
        // 输入法组合期间 v-model 不更新 query，cur 恒等于上次搜索词→天然跳过打字时的无效触发。
        if (cur === self.term) return;
        self.list(cur);
      }, 250);
    },

    // ===== 滚动 =====
    onScroll: function () {
      // 节流：滚动事件高频，requestAnimationFrame 合并
      if (this._scrollRAF) return;
      var self = this;
      this._scrollRAF = requestAnimationFrame(function () {
        self._scrollRAF = null;
        var el = self.$refs.list;
        if (!el) return;
        if (el.scrollTop + el.clientHeight >= el.scrollHeight - 200) self.more();
      });
    },
    scrollToSelected: function () {
      // 节流：键盘连按时合并滚动
      if (this._scrollSelRAF) cancelAnimationFrame(this._scrollSelRAF);
      var self = this;
      this._scrollSelRAF = requestAnimationFrame(function () {
        var el = self.$refs.list;
        if (!el) return;
        var sel = el.querySelector('.card.selected');
        if (sel) sel.scrollIntoView({ block: 'center' });
      });
    },

    // ===== 选择 / 键盘 =====
    select: function (i) { this.selected = i; },
    // hover：设定选中 + anime 高光扫过卡面
    onHover: function (e, i) { this.selected = i; HSUI.cardSheen(e.currentTarget); },
    // 键盘切换选中后：新选中卡片的类型图标弹性跳动一下
    pulseSelected: function () {
      var self = this;
      this.$nextTick(function () {
        if (!window.anime || !self.$refs.list) return;
        var card = self.$refs.list.querySelector('.card.selected');
        var icon = card && card.querySelector('.kind-icon');
        if (!icon) return;
        anime({
          targets: icon,
          scale: [
            { value: 1.3, duration: 150, ease: 'outQuad' },
            { value: 1, duration: 340, ease: 'outElastic' }
          ],
          onComplete: function (anim) { anim.targets[0].style.transform = ''; }
        });
      });
    },
    move: function (delta) {
      var n = this.items.length;
      if (!n) return;
      // 不循环：到顶/底就停
      var next = this.selected + delta;
      if (next < 0) next = 0;
      if (next >= n) next = n - 1;
      if (next === this.selected) return;
      this.selected = next;
      this.scrollToSelected();
      this.pulseSelected();
    },
    onKey: function (e) {
      // embed 模式：Esc 归 launcher（移除注入），不在此关闭面板
      if (this.isEmbed && e.key === 'Escape') return;
      switch (e.key) {
        case 'ArrowDown': e.preventDefault(); this.move(1); break;
        case 'ArrowUp':   e.preventDefault(); this.move(-1); break;
        case 'ArrowRight':
          e.preventDefault();
          if (this.current) this.detailOpen = true;
          break;
        case 'ArrowLeft':
          e.preventDefault();
          this.detailOpen = false;
          break;
        case 'Enter':     e.preventDefault(); this.confirm(); break;
        case 'Escape':
          e.preventDefault();
          if (this.detailOpen) { this.detailOpen = false; }
          else { this.clipStore.close(); }
          break;
      }
    },

    // ===== 条目动作 =====
    confirmItem: function (i) { this.selected = i; this.confirm(); },
    confirm: function () {
      var it = this.items[this.selected];
      if (!it) return;
      this.clipStore.confirm(it.id).catch(function (e) { console.error('confirm:', e); });
    },
    remove: function (i) {
      var it = this.items[i];
      if (!it) return;
      var self = this;
      var card = this.$refs.list ? this.$refs.list.querySelectorAll('.card')[i] : null;
      if (card && card.classList.contains('card--removing')) return;   // 防连点
      this.clipStore.remove(it.id).then(function () {
        var done = function () {
          self.clipStore.removeLocal(i);
          if (self.selected >= self.items.length) self.selected = Math.max(0, self.items.length - 1);
        };
        // anime 退场：右滑 + 淡出 + 折叠高度，完成后才从 Vue 数据移除
        if (card && window.anime) {
          card.classList.add('card--removing');
          card.style.transition = 'none';
          anime({
            targets: card,
            opacity: [1, 0],
            translateX: [0, 56],
            height: [card.offsetHeight, 0],
            marginBottom: 0, paddingTop: 0, paddingBottom: 0,
            duration: 300,
            ease: 'inQuad',
            onComplete: done
          });
        } else done();
      }).catch(function (e) { console.error('delete:', e); });
    },
    toggleStar: function (it, i) {
      var self = this;
      var nv = it.starred ? 0 : 1;
      it.starred = nv;   // 先本地翻转，星标即时反馈
      this.clipStore.toggleStar(it.id, nv).then(function (d) {
        if (d && d.ok) { self.selected = 0; self.list(self.term); }   // 星标改变排序（置顶），重拉反映新顺序
      }).catch(function (e) {
        it.starred = nv ? 0 : 1;   // 失败回滚
        console.error('[Clipboard] star:', e);
      });
    },
  },
  mounted: function () {
    window.vm = this;
    var self = this;
    var el = this.$refs.list;
    if (el) el.addEventListener('scroll', function () { self.onScroll(); }, { passive: true });
    // Tab 注入：launcher 转发输入与键盘
    window.addEventListener('message', function (e) {
      var msg = e.data;
      if (!msg || typeof msg !== 'object') return;
      if (msg.type === 'query') {
        if (self.query !== msg.text) {
          self.query = msg.text;
          self.onQuery();
        }
        return;
      }
      if (msg.type === 'key') {
        if (msg.key === 'ArrowDown') self.move(1);
        else if (msg.key === 'ArrowUp') self.move(-1);
        else if (msg.key === 'Enter') self.confirm();
      }
    });
    var q = this.$refs.q;
    if (q && !this.isEmbed) q.focus();
    window.addEventListener('keydown', this.onKey, true);
    // 页面同源加载，直接拉数据
    this.list('');
  }
});

// ===== 语法高亮指令 =====
// 配合 v-text 使用；缓存上次高亮的源文本，内容未变不重跑 hljs。
// 背景：搜索会整体替换 items 数组触发 v-for 重渲染，updated 钩子在每个代码卡片上都会触发；
// hljs.highlightElement 是 CPU 重操作，若不缓存，内容未变也会全量重高亮——打字卡顿的主因。
app.directive('highlight', {
  mounted: function (el) {
    el._hlSrc = el.textContent;
    if (window.hljs) hljs.highlightElement(el);
  },
  updated: function (el) {
    var src = el.textContent;
    if (src === el._hlSrc) return;   // 内容未变：跳过（v-text 未变时是 no-op，高亮 span 保留）
    el._hlSrc = src;
    if (window.hljs) {
      // 同一元素复用（详情面板切换条目/列表刷新）时，hljs 会拒绝重复高亮：先清除标记
      delete el.dataset.highlighted;
      hljs.highlightElement(el);
    }
  }
});

// ===== 截断渐隐指令 =====
// 内容被 line-clamp 截断时加 .is-clamped（CSS 用 mask 做底部高斯渐隐）。
// 短内容未被截断则不加，避免无故发虚。
// 批量测量：待测元素入队，单个 rAF 内「先批量读、后批量写」——
// 避免逐卡 read(scrollHeight)→write(class) 交替触发的布局抖动（layout thrashing，呼出卡顿元凶之一）。
var fadeQueue = [];
var fadeRAF = 0;
function scheduleFade(el) {
  if (fadeQueue.indexOf(el) < 0) fadeQueue.push(el);
  if (fadeRAF) return;
  fadeRAF = requestAnimationFrame(function () {
    fadeRAF = 0;
    var els = fadeQueue; fadeQueue = [];
    var clamped = els.map(function (e) { return e.scrollHeight > e.clientHeight + 1; });  // 批量读：只一次布局
    for (var k = 0; k < els.length; k++) els[k].classList.toggle('is-clamped', clamped[k]);  // 批量写
  });
}
app.directive('fade', {
  mounted: function (el) { scheduleFade(el); },
  updated: function (el) { scheduleFade(el); }
});

app.use(ClipStore);
app.component('clip-card', ClipCard);
app.component('detail-panel', DetailPanel);
registerUiComponents(app);
var vm = app.mount('#app');

// ===== 面板重开时 Lua 调用（静默刷新 + 重置搜索 + 聚焦）=====
window.QW = { reload: function () {
  vm.query = '';
  vm.clipStore.state.term = '';
  vm.silentRefresh();
  vm.$nextTick(function () {
    var q = document.getElementById('q');
    if (q) q.focus();
  });
}};

// ===== 玻璃光尘（anime.js SVG 路径动画，由占位符 fx glass 注入）=====
// 特效故障不应阻断面板使用，包 try/catch 兜底
try {
  if (window.HSUI && HSUI.initGlassFX) HSUI.initGlassFX();
} catch (e) {
  console.error('initGlassFX 失败', e);
}

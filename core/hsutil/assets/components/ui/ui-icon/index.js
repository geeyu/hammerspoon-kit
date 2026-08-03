/* UiIcon —— IconPark 图标渲染组件
   用法：<ui-icon name="search" :size="14" />
   调用 window.IconPark[name]（工厂函数）生成 SVG 字符串（stroke=currentColor 随主题色）。
   依赖：vendor/iconpark/iconpark.umd.min.js（经注册表 vendor="icons" 自动注入）。
   注意：
   1. IconPark 导出为 PascalCase（'Add'/'BellRing'），icons.json 名称为 kebab-case（'add'/'bell-ring'），
      本组件对 kebab-case 输入做归一化。
   2. colors 四槽位全部 currentColor/transparent：单色跟随主题；48x48 网格，默认 strokeWidth 4（可调）。 */

var UiIcon = Vue.defineComponent({
  name: 'UiIcon',
  props: {
    name: { type: String, required: true },
    size: { type: [String, Number], default: 16 },
    strokeWidth: { type: Number, default: 4 }
  },
  template: '<span ref="box" class="ui-icon" :style="iconStyle"></span>',
  computed: {
    iconStyle: function () {
      var s = typeof this.size === 'number' ? this.size + 'px' : this.size;
      return { width: s, height: s };
    }
  },
  mounted: function () { this.build(); },
  watch: {
    name: function () { this.build(); }
  },
  methods: {
    resolveIcon: function () {
      var ip = window.IconPark;
      if (!ip) return null;
      if (ip[this.name]) return ip[this.name];   // PascalCase 直给
      // kebab-case 归一化：'bell-ring' → 'BellRing'、'a-cane' → 'ACane'
      var pascal = this.name.replace(/(^|-)([a-z])/g, function (m, p, c) { return c.toUpperCase(); });
      return ip[pascal] || null;
    },
    build: function () {
      var box = this.$refs.box;
      if (!box) return;
      box.innerHTML = '';
      var icon = this.resolveIcon();
      if (!icon) return;
      box.innerHTML = icon({
        size: '100%',
        colors: ['currentColor', 'transparent', 'currentColor', 'transparent'],
        strokeWidth: this.strokeWidth
      });
    }
  }
});

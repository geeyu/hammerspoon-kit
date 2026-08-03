var UiPagination = Vue.defineComponent({
  name: 'UiPagination',
  props: {
    modelValue: { type: Number, default: 1 },
    total: { type: Number, default: 0 },
    pageSize: { type: Number, default: 20 }
  },
  emits: ['update:modelValue'],
  computed: {
    totalPages: function() {
      return Math.max(1, Math.ceil(this.total / this.pageSize));
    },
    pageNumbers: function() {
      /* 钳制到合法范围，避免 modelValue 越界时产生空区间 */
      var current = Math.min(Math.max(this.modelValue, 1), this.totalPages || 1);
      var total = this.totalPages;
      if (total <= 7) {
        var pages = [];
        for (var i = 1; i <= total; i++) { pages.push(i); }
        return pages;
      }
      var pages = [1];
      if (current > 3) pages.push('…');
      var start = Math.max(2, current - 1);
      var end = Math.min(total - 1, current + 1);
      for (var j = start; j <= end; j++) { pages.push(j); }
      if (current < total - 2) pages.push('…');
      pages.push(total);
      return pages;
    }
  },
  methods: {
    go: function(page) {
      if (typeof page !== 'number') return;
      if (page < 1 || page > this.totalPages || page === this.modelValue) return;
      this.$emit('update:modelValue', page);
      var self = this;
      Vue.nextTick(function () {
        if (!window.anime || !self.$el) return;
        var active = self.$el.querySelector('.ui-pagination__btn--active');
        if (active) anime({ targets: active, scale: [1, 0.85, 1], duration: 260, ease: anime.spring({ stiffness: 380, damping: 15 }) });
      });
    },
    prev: function() {
      this.go(this.modelValue - 1);
    },
    next: function() {
      this.go(this.modelValue + 1);
    }
  },
  template: '<div class="ui-pagination" v-if="totalPages > 1">' +
    '<button class="ui-pagination__btn" @click="prev" :disabled="modelValue <= 1" type="button" aria-label="上一页">←</button>' +
    '<template v-for="(p, pi) in pageNumbers" :key="pi">' +
      '<span v-if="p === \'…\'" class="ui-pagination__ellipsis">…</span>' +
      '<button v-else class="ui-pagination__btn" :class="{ \'ui-pagination__btn--active\': p === modelValue }" ' +
        '@click="go(p)" type="button">{{ p }}</button>' +
    '</template>' +
    '<button class="ui-pagination__btn" @click="next" :disabled="modelValue >= totalPages" type="button" aria-label="下一页">→</button>' +
    '</div>'
});

var UiTable = Vue.defineComponent({
  name: 'UiTable',
  props: {
    columns: { type: Array, default: function() { return []; } },
    items: { type: Array, default: function() { return []; } },
    emptyText: { type: String, default: 'No data' },
    loading: { type: Boolean, default: false },
    loadingText: { type: String, default: '加载中…' },
    striped: { type: Boolean, default: false }
  },
  /* 字符串模板（不用 tpl.html）：transition-group 作 tbody 在 HTML 解析器里会被 foster-parenting
     移出 table（table 内只认 caption/colgroup/thead/tbody/tfoot/tr），字符串模板绕开该问题。
     行动画：进入淡入下移、离开淡出；key 用 item.id（无 id 退回索引），删除时其余行不重播。 */
  template: '<div class="ui-table-wrapper thin-scroll">' +
    '<table class="ui-table" :class="{ \'ui-table--striped\': striped }">' +
      '<thead><tr>' +
        '<th v-for="col in columns" :key="col.key" :style="{ width: col.width, textAlign: col.align || \'left\' }" class="ui-table__th">{{ col.label }}</th>' +
      '</tr></thead>' +
      '<tbody v-if="loading"><tr><td :colspan="columns.length" class="ui-table__loading"><ui-loading :text="loadingText"></ui-loading></td></tr></tbody>' +
      '<transition-group v-else-if="items && items.length" tag="tbody" name="row">' +
        '<tr v-for="(item, idx) in items" :key="item.id != null ? item.id : idx" class="ui-table__tr">' +
          '<td v-for="col in columns" :key="col.key" :style="{ textAlign: col.align || \'left\' }" class="ui-table__td">' +
            '<slot :name="\'cell-\' + col.key" :row="item" :col="col">{{ item[col.key] }}</slot>' +
          '</td>' +
        '</tr>' +
      '</transition-group>' +
      '<tbody v-else><tr><td :colspan="columns.length" class="ui-table__empty">' +
        '<ui-empty :text="emptyText || \'No data\'" icon="inbox"></ui-empty>' +
      '</td></tr></tbody>' +
    '</table>' +
  '</div>'
});

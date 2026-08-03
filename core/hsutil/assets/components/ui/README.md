# HSUtil UI 组件（assets/components/ui/）

Vue 3 组件库，每组件一个目录（`index.js` + `style.css`，带模板的另有 `*.tpl.html`）。
服务端注册表在 `core/hsutil/internal/ui.lua`：占位符展开 + 依赖拓扑 + 模板内联。

## 组件清单

| 组件 | 注册名 | 说明 |
|---|---|---|
| Button | `ui-button` | 按钮（variant: default/primary/danger/ghost；loading / icon / block） |
| Badge | `ui-badge` | 徽标（text / tone / dot） |
| StatusBadge | `ui-status-badge` | 状态徽标 |
| Divider | `ui-divider` | 分隔线（可带 label） |
| Avatar | `ui-avatar` | 头像（text / src / size / color） |
| Empty | `ui-empty` | 空态（icon / text / hint） |
| Loading | `ui-loading` | 加载态（text / size） |
| Input | `ui-input` | 输入框（v-model） |
| Select | `ui-select` | 下拉（v-model + options: {value,label}） |
| Switch | `ui-switch` | 开关（v-model） |
| Radio | `ui-radio-group` | 单选组（v-model + options + direction） |
| FormField | `ui-form-field` | 表单项包装（label / required / hint / focused） |
| Form | `ui-form` | 表单（schema 数组 + model + columns；submit / change 事件） |
| Modal | `ui-modal` | 模态框（open v-model） |
| Confirm | `ui-confirm` | 命令式确认框：`UiConfirm.show({...}) → Promise<boolean>` |
| Toast | `ui-toast` | 命令式提示：`UiToast.show(text, {type, duration})` |
| Drawer | `ui-drawer` | 抽屉（open v-model） |
| Tabs | `ui-tabs` | 选项卡（v-model + tabs: {value,label}） |
| Table | `ui-table` | 表格（columns: {key,label,width?,align?} + items + striped） |
| Pagination | `ui-pagination` | 分页（v-model + total + page-size） |
| Icon | `ui-icon` | IconPark 图标（name / size / stroke-width，kebab-case 自动归一化，currentColor 随主题） |
| useCrud | `use-crud` | CRUD 组合函数（依赖 ui-confirm） |

## 注册说明

1. 页面经占位符声明组件：`<!-- hsutil:ui button,form,table … -->`（全名或短名均可），服务端按依赖拓扑序注入 js（defer）+ css + 模板。
2. 引入 `components/ui/index.js`，调用 `registerUiComponents(app)` 一键注册所有已加载组件；该文件底部用 `typeof` 守卫暴露全局变量（`UiToast` / `UiConfirm` / `useCrud` 等），供命令式调用。
3. 组件的 js/css 加载顺序由占位符展开保证（在页面脚本 `defer` 之前），页面脚本直接使用即可。

命令式组件（ui-confirm / ui-toast）不注册为标签组件，直接用全局 API；其余均为标签组件。

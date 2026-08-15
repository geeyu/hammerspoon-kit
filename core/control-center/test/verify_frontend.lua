-- 验证 core/control-center/views/pages/control-center/index.html 占位符展开
-- 直接复用 core/hsutil/internal/ui.lua 的 expand（与 server transform 同一实现）
package.path = "core/hsutil/internal/?.lua;" .. package.path
local ui = require("ui")
ui.init("core/hsutil/assets")

local f = io.open("core/control-center/views/pages/control-center/index.html", "rb")
assert(f, "index.html 不存在")
local html = f:read("*a")
f:close()

-- 与 server transform 相同：先展开再校验
local expanded = ui.expand(html)
assert(not expanded:find("hsutil:"), "占位符未展开干净")
local html = expanded

local checks = {
  { "vue vendor",          'src="/hsutil/assets/vendor/vue.global.prod.js"' },
  { "theme.css",           'href="/hsutil/assets/styles/theme.css"' },
  { "base.css",            'href="/hsutil/assets/styles/base.css"' },
  { "glass fx css",        'href="/hsutil/assets/effects/glass-fx/style.css"' },
  { "glass fx js",         'src="/hsutil/assets/effects/glass-fx/index.js"' },
  { "ui-toast js",         'src="/hsutil/assets/components/ui/ui-toast/index.js"' },
  { "ui-empty js",         'src="/hsutil/assets/components/ui/ui-empty/index.js"' },
  { "ui-loading js",       'src="/hsutil/assets/components/ui/ui-loading/index.js"' },
  { "ui-button js",        'src="/hsutil/assets/components/ui/ui-button/index.js"' },
  { "ui-icon js (依赖)",   'src="/hsutil/assets/components/ui/ui-icon/index.js"' },
  { "iconpark vendor",     'vendor/iconpark/iconpark.umd.min.js' },
  { "组件注册表",           'src="/hsutil/assets/components/ui/index.js"' },
}

local pass, fail = 0, 0
for _, c in ipairs(checks) do
  if html:find(c[2], 1, true) then
    print("  [PASS] " .. c[1]); pass = pass + 1
  else
    print("  [FAIL] " .. c[1] .. " 缺少 " .. c[2]); fail = fail + 1
  end
end

-- 业务脚本顺序：store.js 在 app.js 之前（defer 文档序）
local si = html:find('src="store.js"', 1, true)
local ai = html:find('src="app.js"', 1, true)
if si and ai and si < ai then
  print("  [PASS] 脚本顺序 store.js → app.js"); pass = pass + 1
else
  print("  [FAIL] store.js/app.js 缺失或顺序错误"); fail = fail + 1
end

-- 页面私有样式链接指向 /control-center/view 静态挂载
if html:find('href="/control-center/view/pages/control-center/style.css"', 1, true) then
  print("  [PASS] 私有样式链接"); pass = pass + 1
else
  print("  [FAIL] 私有样式链接"); fail = fail + 1
end

print(string.format("== 占位符展开: %d PASS / %d FAIL ==", pass, fail))
os.exit(fail == 0 and 0 or 1)

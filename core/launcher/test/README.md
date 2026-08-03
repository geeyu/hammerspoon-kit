# Launcher 测试

## 纯 Lua 单元测试（推荐）
mock 掉 hs.* 的 IO 部分，快速验证 registry 关键词解析 / calc / custom 源 / runner 分发：
```bash
luajit Spoons/Launcher.spoon/test/unit_test.lua
# 或用 lua5.4 / lua
lua5.4 Spoons/Launcher.spoon/test/unit_test.lua
```
预期：`结果: 16 通过, 0 失败`（全 PASS，退出码 0）。

## 集成自测（需在 Hammerspoon console）
`require("Launcher.internal._test").run()` — 会起共享 server 并 curl 打 `/launcher/api/*`。

# BingDaily.spoon

Bing 每日壁纸（v3.0）。自动轮询今日壁纸 + 一键执行 + 历史归档浏览 + 下载历史。

## 能力

| 功能 | 说明 |
| ------ | ------ |
| 自动轮询 | 每 N 小时（1/3/6/12/24 可选）检查今日壁纸，启动后 5 秒首次拉取 |
| 自动应用 | 轮询到新壁纸后自动设为桌面壁纸（可关） |
| 一键执行 | 立即刷新今日 / 立即应用今日 / 随机应用归档一张 / 打开保存目录 |
| 归档浏览 | 搜索页展示最近 N 天壁纸（1~30），点击/Enter 直接切换；支持 Launcher Tab 注入 |
| 默认保存位置 | 可配置（支持 `~` 缩写，自动创建）；状态卡显示展开后实际路径 |
| 应用范围 | 仅主屏 / 全部屏幕 |
| 系统通知 | 壁纸切换成功后系统通知（可关） |
| 下载历史 | 每次下载记录（文件名/日期/版权/是否已应用），设置页展示最近 8 条 |

## 使用

```lua
hs.loadSpoon("BingDaily"):start()
```

管理页面：Launcher → "Bing 壁纸" 卡片（设置页）。

## 一键执行（设置页按钮）

| 按钮 | 行为 |
| ------ | ------ |
| 立即刷新今日 | 拉取今日壁纸；是否应用按「自动应用」配置 |
| 应用今日壁纸 | 下载今日并立即设壁纸（无视自动应用开关）；已下载过则直接用本地文件 |
| 随机一张 | 从归档随机选一张下载并应用（避开当前壁纸） |
| 打开保存目录 | Finder 打开保存目录（自动创建） |

## 配置存储

SQLite（`~/.hammerspoon/data/bingdaily/bingdaily.db`）：

- `settings` 表：配置项（interval_hours / save_dir / auto_apply / archive_days / notify_enabled / apply_to_screens）
- `downloads` 表：下载历史
- 旧 `settings.json` 首次启动自动迁移进 SQLite 后删除

## 编程式 API

```lua
local bd = hs.loadSpoon("BingDaily")
bd:start()
bd:applyToday()          -- 一键应用今日
bd:applyRandom()         -- 随机应用归档一张
bd:refreshNow()          -- 立即刷新
bd:openSaveDir()         -- 打开保存目录
bd:getStatus()           -- 状态
bd:recentDownloads()     -- 下载历史
```

## 前端页面

| 页面 | 路由 | 说明 |
|------|------|------|
| 设置 | `/bingdaily/view/pages/settings/` | 状态卡 + 一键执行 + 配置项 + 下载历史 |
| 搜索 | `/bingdaily/view/pages/search/` | 归档壁纸浏览，点击应用（Launcher Tab 注入）|

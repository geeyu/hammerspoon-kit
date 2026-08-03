# 五分钟上手

## 1. 安装

1. 安装 [Hammerspoon](https://www.hammerspoon.org/)（`brew install --cask hammerspoon` 或官网下载）
2. 首次启动 Hammerspoon，授予「辅助功能」权限（系统设置 → 隐私与安全性 → 辅助功能）
3. 克隆本仓库到配置目录：

```bash
git clone <本仓库地址> ~/.hammerspoon
```

4. 点击菜单栏 Hammerspoon 图标 → **Reload Config**

## 2. 立即试试

| 操作 | 效果 |
|------|------|
| `Ctrl+Opt+Cmd+←` | 当前窗口左半屏 |
| `Ctrl+V` | 呼出剪贴板历史，输入关键字过滤，Enter 粘贴 |
| `Option+Space` | 命令中枢：输入应用名回车启动；输入 `sc` 截屏 |
| `Option+Space` → 点「防睡眠」卡片 | 打开防睡眠控制台，选 30 分钟保持清醒 |

## 3. 常用配置入口

| 想改什么 | 去哪改 |
|----------|--------|
| 窗口居中尺寸（默认 800×600） | `Spoons/QuantumWindow.spoon/internal/config.lua` |
| Launcher 热键、URL 模板、书签 | `core/launcher/internal/config.lua` |
| 剪贴板保留天数 | `Spoons/Clipboard.spoon/internal/config.lua` |
| 防睡眠默认模式 | `Spoons/StayAwake.spoon/internal/config.lua` |

改完执行 `Cmd+Opt+Ctrl+R` 重载生效。

## 4. 下一步

- 想了解每个包的详细用法 → 各 `Spoons/*.spoon/docs/README.md`
- 想开发自己的工具 → [二次开发指南](development.md)

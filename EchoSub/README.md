# EchoSub

EchoSub 是一个原生 macOS YouTube 双语字幕学习工具，界面基于项目中的 `youtube-player/` 原型实现。

## 当前能力

- 粘贴常见格式的 YouTube 链接并使用官方 IFrame Player 播放。
- 本地持久化播放列表和观看进度。
- 通过三级降级链路读取字幕：内置 YouTube 页面解析 → 本机 `yt-dlp` → Supadata API。
- 将碎字幕组合为 2～8 秒的语义短句。
- 使用 OpenAI 兼容接口逐批翻译，并按稳定 ID 对齐结果。
- 原文、中文、双语三种显示方式。
- 点击字幕跳转，播放时自动跟随。
- 独立悬浮字幕窗和支持鼠标穿透的桌面歌词。
- API Key 仅保存到 macOS Keychain。

## 字幕来源

EchoSub 默认不需要 YouTube 登录。它会先直接读取公开视频自带的字幕；失败后自动调用本机 `yt-dlp`（推荐用 `brew install yt-dlp` 安装）；两者都失败时，才会使用“设置 → 字幕来源”中配置的 Supadata API Key。Supadata 请求固定使用 `mode=native`，不会自动触发 AI 转写。

## 本地开发

```bash
swift build
swift test
swift run EchoSub
```

当前开发环境只需要 macOS Command Line Tools。安装完整 Xcode 后也可以直接打开 `Package.swift`。

## 生成应用包

```bash
chmod +x Scripts/package-app.sh
Scripts/package-app.sh release
open dist/EchoSub.app
```

脚本会生成经过临时本地签名的 `dist/EchoSub.app`。正式分发前需要使用 Developer ID 签名并完成 Apple 公证。

# EchoSub

EchoSub 是一款面向英语学习者的 macOS YouTube 双语字幕工具。

## 仓库结构

- `EchoSub/`：AppKit macOS 应用源码
- `youtube-player/`：早期交互原型，用于保留产品与界面设计过程

## 构建

需要 macOS 13 或更高版本，以及 Swift 6 工具链。

```bash
cd EchoSub
swift test
./Scripts/package-app.sh release
```

打包后的应用位于 `EchoSub/dist/EchoSub.app`。

## 本地数据

应用会把播放列表、字幕、翻译结果和视频背景卡保存在：

```text
~/Library/Application Support/EchoSub/library.json
```

翻译 API Key 与 Supadata API Key 按产品设计以明文保存在同目录的 `credentials.json`。请勿将该文件提交到 Git。

## 原型

直接在浏览器中打开 `youtube-player/index.html`，即可查看无需构建工具的离线原型。

## 产品与设计文档

- `docs/youtube-bilingual-player-product-brief.zh-CN.md`：产品与 UI 设计说明
- `docs/EchoSub-v0.1.2-UI-implementation-handoff.zh-CN.md`：实际 UI 实现交接
- `docs/EchoSub-vocab-lookup-feature.zh-CN.md`：选词讲解与译文编辑功能说明
- `docs/youtube-subtitle-translation-github-research.md`：字幕翻译开源方案研究

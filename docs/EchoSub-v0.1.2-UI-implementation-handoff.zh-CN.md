# EchoSub v0.1.2 UI 实际实现与原型改版说明

> 文档用途：把 `youtube-player/` 原型初稿更新为与 EchoSub v0.1.2（Build 7）一致的产品原型，并补齐开发过程中新增的页面、状态和交互。
>
> 基准代码：`EchoSub/`，版本 `0.1.2 (7)`；基准提交：`362c57f Improve long-video translation reliability`。
>
> 原型目录：`youtube-player/`。本文以实际 AppKit 产品为事实来源，不要求 UI 稿逐像素复制当前实现，但所有功能状态与交互边界必须被表达。

## 1. 改版结论

初稿已经定义了产品的核心结构：YouTube 播放器、播放列表、右侧双语字幕、悬浮字幕、桌面歌词和设置。实际产品在此基础上发生的主要变化，不是简单的视觉调整，而是从“播放器概念稿”发展成了一个有完整任务状态和多窗口行为的桌面工具。

新原型需要重点表达以下变化：

1. 主窗口成为真正可折叠、可拖动、会记忆尺寸的三栏工作区。
2. 字幕不再只有“完成 / 翻译中”，而是增加全文理解、局部缺失、逐句重试、补全、全部重翻等状态。
3. 新增“视频背景卡”，在翻译前阅读全文，并允许查看、编辑、复制和重新生成。
4. 播放列表增加隐藏列表、恢复、永久删除、列表循环和单首循环。
5. 悬浮字幕和桌面歌词成为真正的 macOS 独立窗口，支持置顶、跨桌面、透明背景、自适应换行和自动高度。
6. 外观设置由复杂的“描边 / 填充”简化为英文、中文两种字体颜色，并提供常用预设。
7. 设置新增字幕来源页，展示 YouTube、yt-dlp、Supadata 的回退顺序；密钥改为本机明文文件存储。
8. 长视频翻译支持多个视频任务并行存在、批次重试和失败跳过，界面需要清楚区分“还在工作”和“已完成但有漏翻”。

## 2. 当前产品的信息架构

```text
EchoSub
├─ 主窗口
│  ├─ 顶部：YouTube URL 输入 / 剪贴板 / 添加 / 设置
│  ├─ 左栏：播放列表 / 已隐藏列表
│  ├─ 中栏：YouTube 播放器 / 视频信息 / 播放控制 / 分栏控制
│  └─ 右栏：字幕列表 / 视频背景卡
├─ 悬浮字幕窗口
├─ 桌面歌词窗口
├─ 设置窗口
│  ├─ 字幕与语言
│  ├─ 字幕来源
│  ├─ 翻译服务
│  ├─ 外观
│  └─ 缓存与隐私
└─ macOS 菜单
   ├─ 打开诊断日志
   ├─ 显示本地数据文件夹
   └─ 悬浮字幕 / 桌面歌词快捷操作
```

## 3. 主窗口：从静态三栏变为可管理工作区

### 3.1 窗口与分栏规则

| 项目 | 原型初稿 | 当前实际产品 | 新原型要求 |
| --- | --- | --- | --- |
| 默认窗口 | 1180 × 720 展示稿 | 1180 × 720，最小 900 × 600 | 至少提供默认尺寸与最小尺寸两张响应式状态 |
| 左栏 | 可折叠示意 | 可折叠、可拖动，宽度 180–360，记忆上次宽度 | 画出展开、折叠、拖动 hover 三种状态 |
| 右栏 | 固定字幕栏 | 可折叠、可拖动，最小 280，建议范围至 520，记忆宽度 | 折叠按钮必须位于中栏底部最右侧 |
| 中栏 | 固定播放器 | 保证至少 360 宽，左右栏变化时播放器自适应 | 画出双栏展开、仅左栏、仅右栏、视频专注四种组合 |
| 分隔线 | 视觉细线 | 视觉 1 px，但鼠标命中区约 7 pt | hover 时必须让用户感知“可以拖动”，不要增加粗重常驻线 |

当前实现使用 `NSSplitView`，关键约束如下：

```swift
// MainWindowController.swift
let centerMinimum = center.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)

// DesignSystem.swift
final class EchoSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 7 }
    // 7 pt 命中区中只绘制 1 pt 分隔线
}

// MainWindowController.swift
let left = min(360, max(180, savedLeftWidth))
let right = min(520, max(280, savedRightWidth))
```

设计注意：折叠后该侧必须完全消失，不能残留一条空白栏或无法拖动的透明区域。再次展开时恢复折叠前宽度，而不是回到硬编码默认值。

### 3.2 顶部 URL 添加区

当前顶部栏高度为 52 pt，输入组件集中在右侧。结构为：

```text
[link 图标 | 粘贴 YouTube 链接开始… | 剪贴板按钮] [＋ 添加] [设置]
```

视觉规格：

- 输入框容器高 28 pt，圆角 9 pt，暗色半透明底，1 px 弱边框。
- 输入区建议宽 320 pt，可在 300–380 pt 内自适应。
- “添加”为 76 × 28 pt 的蓝色主按钮。
- 剪贴板按钮是明确可点的独立控件；输入框也必须支持 `⌘V`、右键粘贴。
- 顶栏使用 macOS `headerView` 材质，与主内容有 1 px 分隔线。

实际代码：

```swift
linkField.placeholderString = "粘贴 YouTube 链接开始…"
let paste = EchoStyle.iconButton(
    "clipboard",
    help: "从剪贴板粘贴",
    target: self,
    action: #selector(pasteYouTubeURL)
)
let add = EchoStyle.button("添加", symbol: "plus", primary: true)
```

原型需要补充：正常、聚焦、已粘贴、无法识别链接四种状态。错误以 macOS sheet / inline alert 表达，文案为“无法识别这个 YouTube 链接”。

## 4. 左侧播放列表

### 4.1 列表项

当前每项高度约 64 pt，包含：

- 74 × 44 pt 缩略图；
- 最多两行标题；
- 频道名；
- 状态圆点与文本；
- 当前项左侧 3 pt 蓝色竖条和弱蓝灰背景。

状态颜色：

| 状态 | 文案 | 颜色 |
| --- | --- | --- |
| idle | 待获取 | 三级灰 |
| loading | 获取中 | 蓝 |
| translating | 翻译中 | 蓝 |
| ready | 双语 | 绿 |
| noSubtitles | 无字幕 | 橙 |
| failed | 失败 | 红 |

长视频翻译时，可以同时有多个视频显示“翻译中”。切换视频不意味着前一个任务停止，因此原型不要把列表状态设计成全局唯一 loading。

### 4.2 隐藏与删除

播放列表右键菜单：

```text
正常列表：隐藏
          ─────
          删除…

已隐藏列表：恢复到播放列表
            ─────
            删除…
```

“隐藏”只从当前列表收纳，不删除任何视频、字幕或翻译数据。顶部出现“已隐藏 N”入口；进入后标题变为“已隐藏”，入口变为“返回”。

“删除”是不可逆操作，必须二次确认。确认弹窗明确说明会删除：视频信息、原字幕、翻译结果、视频背景卡。

新原型至少需要：

1. 正常播放列表；
2. 有隐藏项目时的入口；
3. 已隐藏列表；
4. 正常项目右键菜单；
5. 隐藏项目右键菜单；
6. 永久删除确认 sheet。

## 5. 中央播放器与播放控制

### 5.1 播放器区域

- 播放器保持 16:9，圆角 8 pt。
- 默认在中栏顶部留出约 64 pt 呼吸空间，最大高度不超过中栏约 68%。
- YouTube 禁止嵌入时，播放器替换为状态卡；字幕仍然可以阅读。
- 空状态显示 EchoSub 图形、产品名和“粘贴一个 YouTube 链接开始”。
- 无字幕 / 获取失败状态提供“重新检测”和“在 YouTube 打开”。

禁止嵌入状态的主要文案：

```text
该视频不允许在第三方播放器中播放
可以在 YouTube 中打开；已获取的字幕仍可继续阅读。
[在 YouTube 打开]
```

### 5.2 播放器下方控制条

结构：

```text
[标题 / 频道·时长] [后退5秒] [播放/暂停] [前进5秒]
[循环] [悬浮字幕] [桌面歌词] [播放器窗口全屏] [YouTube 打开]
```

循环按钮按一次在以下状态中轮换：

```text
关闭（灰色 repeat） → 列表循环（蓝色 repeat）
→ 单首循环（蓝色 repeat.1） → 关闭
```

### 5.3 “播放器窗口全屏”不是系统全屏

这里必须在原型中表达准确：点击后，视频在 **EchoSub 当前窗口内部** 覆盖所有应用内容；不会让 macOS 窗口进入独立全屏空间，也不会隐藏系统桌面。

- 当前窗口内容变为黑色背景；
- 视频按 16:9 等比最大化，必要时左右或上下留黑；
- 右下角有 48 × 48 pt 的退出按钮；
- `Esc` 也可以退出；
- 不应因为点击该控件触发视频暂停。

实现结构：

```swift
// 将同一个 YouTubePlayerView 临时移动到覆盖层，而不是切换 NSWindow 全屏状态
let overlay = PlayerWindowOverlay(playerView: playerView) { exitPlayerFullscreen() }
content.addSubview(overlay, positioned: .above, relativeTo: nil)
overlay.pinEdges(to: content)
```

## 6. 右侧字幕面板

### 6.1 头部

```text
字幕 [原文 | 中文 | 双语]          [✨ 背景卡] [自动跟随] […更多]
```

- 所有按钮处在同一水平基线。
- “背景卡”有四种状态：禁用、默认灰、理解中蓝、失败橙色警告。
- 自动跟随开启为蓝色，手动滚动后关闭为灰色；点击恢复后立刻滚回当前句。
- 更多菜单不直接触发危险操作。

更多菜单：

```text
补全翻译（N 句）
全部重新翻译…
────────────
重新获取原字幕
```

“全部重新翻译”必须再出现确认 sheet，说明会清空中文翻译，但不改变英文原字幕。

### 6.2 字幕行排版

这是当前 UI 与旧原型差异最明显的部分之一：

- 时间戳、英文、中文都使用统一的左对齐逻辑。
- 时间列约 38 pt，正文从统一的左边缘开始。
- 英文 13 pt medium；中文 12 pt regular。
- 英文和中文都允许多行自动换行，不能居中，也不能根据短句长度漂移。
- 双语间距约 5 pt，行内上下边距约 9 pt。
- 当前行使用弱蓝背景和左侧 3 pt 蓝色竖条。
- 点击任意字幕行跳转视频时间。
- 右键显示“补翻此句”或“重新翻译此句”。

实际文本样式统一由以下函数保证：

```swift
static func applySubtitleText(
    _ field: NSTextField,
    text: String,
    font: NSFont,
    color: NSColor,
    alpha: CGFloat = 1
) {
    field.stringValue = text
    field.font = font
    field.textColor = color.withAlphaComponent(alpha)
    field.alignment = .left
    field.lineBreakMode = .byWordWrapping
    field.cell?.alignment = .left
    field.cell?.wraps = true
    field.cell?.usesSingleLineMode = false
}
```

原型应使用真实长句测试至少三种情况：英文一行 / 中文一行、英文三行 / 中文两行、英文五行 / 中文三行。行高必须由内容决定，不能固定。

### 6.3 底部进度文案

右侧面板底部不是单一进度条，而是完整的任务反馈区域。需要覆盖：

| 状态 | 文案示例 |
| --- | --- |
| 获取原字幕 | 正在获取字幕… |
| 全文分析 | 正在理解完整视频内容… |
| 批量翻译 | 正在翻译 168 / 1333 句 |
| 完成 | YouTube · YouTube 人工字幕 |
| 有漏翻 | YouTube · YouTube 自动字幕 · 待补全 12 句 |
| 无字幕 | 这个视频没有可用字幕。 |
| 失败 | 字幕或翻译失败，可点击右上角重试。 |

当前翻译机制每批 12 句；每批最多尝试 3 次，失败后跳过并继续后面的批次。翻译完成但仍有缺失时，视频状态回到“ready / 双语”，底部显示“待补全 N 句”，用户再使用补全或单句重试。

## 7. 视频背景卡：原型需要新增的完整页面

背景卡覆盖右侧字幕面板，而不是打开新的主窗口。出现和关闭使用轻微淡入淡出。

### 7.1 四个主状态

1. **未生成**：说明用途，主按钮“开始分析”。
2. **生成中**：spinner + “正在理解视频内容”；说明视频仍可正常播放。
3. **失败**：橙色警告 + 错误信息 + “重新生成”。同时说明字幕翻译仍可使用局部上下文。
4. **完成**：阅读模式 / 编辑模式。

### 7.2 完成态内容

```text
视频背景                                      [编辑] […] [关闭]
全文分析完成 · 1:48:40 · 1333 句 · 已编辑

[全文概括]
[章节概览]  每章可点击跳转视频
[领域与表达风格]  可折叠
[人物与机构]      可折叠，显示数量
[术语表]          可折叠，显示数量
[疑似识别问题]    可折叠，橙色提示

背景卡仅用于帮助模型理解全局语境；原句与相邻字幕始终具有更高优先级。
```

编辑模式允许修改全文概括、领域、语气、章节标题、人物译名和术语译名。编辑后显示“已编辑”。

“…”菜单：

```text
重新生成背景卡…
复制背景卡
```

重新生成确认有两种情况：

- 未编辑过：重新生成 / 取消；
- 用户编辑过：保留术语并重新生成 / 全部覆盖 / 取消。

### 7.3 背景卡与翻译的关系

界面文案应避免让用户误以为背景卡是“视频摘要功能”而与翻译无关。实际流程是：

```text
完整字幕 → 全文背景卡 → 分批逐句翻译
                       ↘ 原句 + 前后邻句始终优先
```

背景卡包含全文概括、章节、领域、表达风格、实体、术语和疑似识别问题。它作为每批翻译的静态全局背景；不会用摘要替换原句，也不会允许模型依据摘要添加字幕中不存在的信息。

## 8. 悬浮字幕窗口

### 8.1 窗口行为

- macOS `NSPanel`，默认 470 × 320，最小 320 × 200。
- 可从窗口边缘正常缩放；宽度改变后所有字幕重新计算换行和行高。
- Pin 开启时使用最高层级置顶，切换其他 App 仍可见。
- 可设置在所有桌面空间显示。
- 关闭背景到 0 时是真正透明；系统窗口阴影关闭，避免滚动时残留旧字形重影。

### 8.2 顶部控件

第一行：

```text
[Pin] [字号小] [字号大] [原文 | 中文 | 双语]      [自动跟随] [桌面歌词]
```

第二行右侧：

```text
[半圆透明度图标] [背景透明度滑杆 0…100%]
```

### 8.3 字幕列表规则

- 英文、中文全部左对齐；宽度不足自动换行。
- 当前句弱蓝高亮，英文使用 semibold；其他句 regular 且约 72% 透明度。
- 每行高度按“当前句半粗体的最坏情况”统一计算，避免高亮移动时中文被裁切或列表跳动。
- 字号范围 12–36 pt；中文默认比英文小 3 pt。
- 点击字幕跳转；右键可补翻 / 重试。
- 自动跟随时，当前句滚动到视口顶部以下约 20% 的位置，而不是只保证“勉强可见”。
- 用户主动滚动时暂停自动跟随；点击 scope 按钮恢复。

关键尺寸计算：

```swift
static func rowHeight(
    for segment: SubtitleSegment,
    mode: SubtitleDisplayMode,
    availableWidth: CGFloat,
    fontSize: CGFloat
) -> CGFloat {
    let originalFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let translatedFont = NSFont.systemFont(ofSize: max(11, fontSize - 3))
    // 计算英文与中文 boundingRect，再加 16 pt 上下留白和 5 pt 双语间距
}
```

UI 原型不能继续用固定高度窗口内截取几条字幕来模拟，必须展示“窄窗长句自动换行”“当前句自动滚到靠上位置”“完全透明背景”三张关键状态。

## 9. 桌面歌词窗口

桌面歌词一次只显示当前一句，属于屏幕级 overlay，而不是字幕列表。

### 9.1 编辑态

顶部浮动控制条：

```text
[A−] [A+] [中−] [中+] [透明度] [锁定] [关闭]
```

- 英文和中文字号分别调节，范围 12–48 pt。
- 默认英文 27 pt bold，中文 18 pt regular。
- 两行统一左对齐，间距约 8 pt。
- 背景是 `hudWindow` 毛玻璃，圆角约 13 pt，透明度可以拖到完全透明。
- 可拖动整个窗口，也可从边缘调整宽度。
- 宽度变化引起换行后，窗口高度自动撑开；保持顶部位置不跳动。
- 默认宽 570、高约 158；最小 320 × 100，最大高度 500，最大宽约当前屏幕可见宽度的 82%。

### 9.2 锁定态

- 控制条隐藏；
- 窗口穿透鼠标，不影响下面的 App；
- 背景边框隐藏；
- 通过 `⌘⇧L` 或应用菜单解锁。

设计上需要同时提供：带底板、半透明、全透明、锁定四种状态。全透明时字幕依然要借助颜色和适当字体权重保持可读，但当前实现不再提供描边 / 填充双层配置。

## 10. 字幕颜色体系

旧方案中的“填充颜色 / 边缘颜色”已取消。当前只有两个全局字体颜色：

- 英文字体颜色；
- 中文字体颜色。

它们同时应用于右侧字幕、悬浮字幕和桌面歌词。

预设：

| 名称 | 英文 | 中文 |
| --- | --- | --- |
| 经典白 / 黄 | `#FFFFFF` | `#FFD54F` |
| 统一高对比白 | `#FFFFFF` | `#FFFFFF` |
| 柔和白 / 青 | `#F7F7F7` | `#7FDBFF` |
| 暖白 / 橙 | `#FFF8E7` | `#FFB74D` |

原型建议把预设显示为“双圆点 / 双色条 + 名称”，而不是只显示一个颜色块。选择“自定义”后显示两个 macOS color well。

## 11. 设置窗口

设置窗口当前为 640 × 600，左侧导航宽约 172。与初稿相比新增“字幕来源”，并调整了密钥与外观设置。

### 11.1 字幕与语言

- 首选原字幕语言：英语；
- 目标翻译语言：简体中文；
- 默认字幕模式：原文 / 中文 / 双语；
- 自动跟随播放。

### 11.2 字幕来源（新增）

明确展示优先级：

```text
内置 YouTube → 本机 yt-dlp → Supadata
```

- 显示 yt-dlp 已检测 / 未安装；未安装时提示 `brew install yt-dlp`。
- Supadata API Key 仅在前两种方式失败后使用。
- Supadata 使用 `mode=native`，只读取已有字幕，避免自动触发 AI 转写费用。
- 公开视频不要求 YouTube 登录。

### 11.3 翻译服务

- OpenAI 兼容接口；
- API Base URL；
- 模型名称；
- API Key；
- 测试连接与连接状态。

输入框必须支持粘贴。当前常用模型包括 DeepSeek V4 Flash、Qwen3 系列；普通字幕翻译关闭显式思考，全文背景分析开启思考。

### 11.4 外观

- 悬浮字幕字号；
- 桌面歌词英文 / 中文独立字号；
- 悬浮字幕背景透明度；
- 桌面歌词背景透明度；
- 配色预设；
- 英文字体颜色；
- 中文字体颜色；
- 悬浮窗默认 Pin；
- 在所有桌面空间显示。

### 11.5 缓存与隐私

- 清除字幕缓存；
- 清除全部播放记录；
- 恢复默认；
- 说明本机数据位置和隐私边界。

当前密钥不再使用钥匙串。它与字幕资料位于同一目录：

```text
~/Library/Application Support/EchoSub/
├─ library.json
├─ credentials.json
├─ diagnostics.jsonl
└─ diagnostics.previous.jsonl
```

`credentials.json` 为明文，但文件权限设置为 `0600`。新原型中的隐私说明必须同步修改，不能继续写“仅存储在 macOS Keychain”。

## 12. 翻译任务状态如何影响 UI

设计人员不需要表现底层 API 参数，但必须理解这些规则，否则进度与操作会画错。

### 12.1 当前流程

```text
添加视频
  → 获取字幕（YouTube / yt-dlp / Supadata）
  → 语义分句
  → 生成完整视频背景卡
  → 每 12 句翻译一批，携带前后邻句和背景卡
  → 每批失败最多重试 3 次（约 5 秒、15 秒退避）
  → 仍失败则跳过该批，继续后续批次
  → 全部队列结束后显示“待补全 N 句”
```

### 12.2 并行与切换视频

- 翻译任务以 `videoID` 为单位登记；不同视频可以各自保持运行。
- 同一视频再次发起任务时，新任务替换旧任务，旧响应到达后被忽略。
- 用户切换视频时，当前右侧面板只显示所选视频的进度，但左侧列表继续显示其他视频的“翻译中”。
- App 重启后，残留的“翻译中”会恢复成可继续操作的 ready / idle，避免永久卡死。

### 12.3 普通翻译与全文分析的思考模式

```swift
static func thinkingMode(model: String, purpose: TranslationRequestPurpose) -> Bool? {
    let supports = model.lowercased().contains("qwen3")
        || model.lowercased().contains("deepseek-v4")
    guard supports else { return nil }
    return purpose == .backgroundCard   // 翻译 false，背景分析 true
}
```

UI 不需要展示“思考中 token”，只需用两个明确阶段表达：

1. “正在理解完整视频内容…”；
2. “正在翻译 X / Y 句”。

## 13. macOS 菜单与诊断入口

原型初稿没有覆盖菜单栏，但当前产品已有：

```text
EchoSub
├─ 关于 EchoSub
├─ 打开诊断日志
├─ 显示本地数据文件夹
├─ 设置…                  ⌘,
└─ 退出 EchoSub            ⌘Q

播放
├─ 显示 / 隐藏悬浮字幕     ⇧⌘F
├─ 显示 / 隐藏桌面歌词     ⇧⌘D
└─ 锁定 / 解锁桌面歌词     ⇧⌘L
```

建议 UI 稿增加一张菜单栏说明页，至少表达诊断日志、本地文件夹和桌面歌词解锁入口。诊断日志是排查长视频翻译进度的主要途径。

## 14. 当前视觉系统

实际 App 当前固定为深色外观，主色使用系统蓝。原型初稿的深浅色切换是设计展示功能，不代表当前产品已经提供主题切换。

```css
:root {
  --echo-window: #222222;                 /* calibratedWhite 0.135 */
  --echo-sidebar: rgba(20, 20, 20, .62);
  --echo-panel: rgba(255, 255, 255, .035);
  --echo-separator: rgba(255, 255, 255, .08);
  --echo-text-primary: rgba(255, 255, 255, .92);
  --echo-text-secondary: rgba(255, 255, 255, .56);
  --echo-text-tertiary: rgba(255, 255, 255, .34);
  --echo-highlight: color-mix(in srgb, #0A84FF 16%, transparent);
  --echo-accent: #0A84FF;                 /* macOS system blue */
}
```

设计方向：

- 保留 macOS 原生、克制、低饱和的工具感；
- 用层级、透明度、间距建立结构，不依赖大量描边；
- 蓝色只用于当前项、开启态、主要操作和进度；
- 状态色只服务于语义，不做装饰性彩色渐变；
- 所有文字控件使用系统字体，优先保证中英混排和长句可读性。

## 15. 给 `youtube-player/` 的状态模型建议

原型当前主要通过 `variant` 切换少量静态页面。建议改成可组合状态，以便覆盖真实产品：

```jsx
const prototypeState = {
  layout: {
    playlist: "expanded",       // expanded | collapsed
    subtitles: "expanded",      // expanded | collapsed
    playlistWidth: 236,
    subtitleWidth: 348,
    playerWindowFocus: false,
  },
  playlist: {
    view: "active",             // active | hidden
    selectedVideoID: "video-1",
    loopMode: "none",           // none | list | single
  },
  subtitle: {
    mode: "bilingual",          // original | translated | bilingual
    autoFollow: true,
    phase: "translating",       // fetching | analyzing | translating | ready | partial | failed | noSubtitles
    translatedCount: 168,
    totalCount: 1333,
    missingCount: 0,
  },
  backgroundCard: {
    visible: false,
    phase: "ready",             // empty | generating | ready | editing | error
    edited: false,
  },
  floating: {
    pinned: true,
    opacity: 0.96,
    fontSize: 20,
    mode: "bilingual",
    autoFollow: true,
  },
  lyrics: {
    locked: false,
    opacity: 0.72,
    englishFontSize: 27,
    chineseFontSize: 18,
  },
};
```

组件拆分建议：

```jsx
<MainWindow>
  <URLToolbar />
  <ResizableWorkspace>
    <PlaylistPanel view="active|hidden" />
    <PlayerPanel focusMode={false} />
    <SubtitlePanel phase="translating|partial|..." />
  </ResizableWorkspace>
</MainWindow>

<BackgroundCardPanel phase="empty|generating|ready|editing|error" />
<FloatingSubtitleWindow pinned opacity fontSize autoFollow />
<DesktopLyricsWindow locked opacity englishSize chineseSize />
<SettingsWindow tab="subtitles|sources|translation|appearance|data" />
```

## 16. UI 人员需要补齐的原型画面清单

### P0：必须补齐

1. 主窗口默认三栏与长句双语字幕；
2. 左栏折叠、右栏折叠、左右均折叠；
3. 分栏拖动 hover 与最小宽度；
4. 隐藏列表、恢复、删除确认；
5. 循环关闭 / 列表循环 / 单首循环；
6. 播放器窗口内全屏与退出状态；
7. 右侧字幕逐句右键菜单；
8. 翻译更多菜单与“全部重新翻译”二次确认；
9. 获取字幕、全文理解、翻译、待补全、失败、无字幕状态；
10. 背景卡未生成、生成中、完成、编辑、失败；
11. 悬浮字幕窄宽换行、自动跟随、Pin、完全透明；
12. 桌面歌词编辑、锁定、窄宽自动增高、完全透明；
13. 设置新增“字幕来源”；
14. 设置外观页的双语配色与独立字号；
15. 设置隐私文案改为本机明文 `credentials.json`。

### P1：建议补齐

1. URL 输入聚焦、粘贴、错误；
2. 播放列表同时存在多个翻译任务；
3. 背景卡重新生成三按钮确认；
4. App 菜单与诊断日志入口；
5. 窗口最小尺寸 900 × 600 下的响应式排版；
6. 禁止嵌入但字幕可读状态；
7. App 重启后翻译状态恢复提示。

## 17. 验收标准

更新后的原型可按以下标准验收：

- 任意一个危险操作都不会由单击省略号直接触发。
- 左右侧栏都能完整折叠、完整展开、拖动并恢复宽度。
- 所有英文和中文正文统一左对齐，任何宽度下都不会互相覆盖。
- 当前字幕的半粗体不会导致中文被裁切。
- 悬浮字幕当前行能够自动滚动到视口靠上位置。
- 背景透明度为 0 时没有旧字幕重影，且设计稿明确表达“无底板”。
- 桌面歌词宽度改变后高度随换行自动变化。
- “播放器窗口全屏”没有被画成 macOS 系统全屏。
- 翻译进度能区分全文理解、逐批翻译和待补全。
- 隐藏与删除在语义、入口和确认文案上有明显区别。
- 设置中不存在钥匙串文案，Supadata 只作为最后回退来源。

## 18. 代码索引

| 模块 | 当前实现文件 | UI 关注点 |
| --- | --- | --- |
| 主窗口与三栏 | `EchoSub/Sources/EchoSub/MainWindowController.swift` | 顶栏、播放列表、播放器、字幕、折叠、拖动、菜单、窗口内全屏 |
| 悬浮字幕 / 桌面歌词 | `EchoSub/Sources/EchoSub/OverlayWindowControllers.swift` | Pin、透明度、换行、自动高度、自动跟随、锁定 |
| 背景卡 | `EchoSub/Sources/EchoSub/BackgroundCardPanel.swift` | 四种状态、阅读、编辑、重新生成 |
| 设置 | `EchoSub/Sources/EchoSub/SettingsWindowController.swift` | 五个设置页与表单状态 |
| 视觉 token | `EchoSub/Sources/EchoSub/DesignSystem.swift` | 颜色、文字、按钮、卡片、分隔线 |
| 产品状态模型 | `EchoSub/Sources/EchoSub/Models.swift` | 字幕模式、循环模式、视频状态、背景卡、配色 |
| 任务状态 | `EchoSub/Sources/EchoSub/AppState.swift` | 多视频任务、进度、补全、重试、隐藏、删除 |
| 翻译请求 | `EchoSub/Sources/EchoSub/TranslationService.swift` | 背景上下文、思考开关、批次和超时 |
| 本地存储 | `EchoSub/Sources/EchoSub/Persistence.swift` | 数据目录、明文密钥、窗口与外观偏好 |
| App 菜单 | `EchoSub/Sources/EchoSub/EchoSubApp.swift` | 诊断、数据目录、快捷键 |
| 初稿主窗口 | `youtube-player/screens-main.jsx` | 需要按本文扩展组合状态 |
| 初稿浮窗 | `youtube-player/screens-floating.jsx` | 需要补透明度、自动高度和真实窗口行为 |
| 初稿设置 | `youtube-player/screens-settings.jsx` | 需要新增字幕来源并更新存储文案 |

---

这份文档描述的是 v0.1.2 的真实产品行为。UI 可以优化视觉表现，但若要改变本文中的交互逻辑、数据语义或状态流程，应先与产品 / 开发确认，避免原型再次与实际产品分叉。

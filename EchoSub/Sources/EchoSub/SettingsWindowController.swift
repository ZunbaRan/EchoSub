import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum Tab: Int, CaseIterable {
        case subtitles
        case sources
        case translation
        case appearance
        case data

        var title: String {
            switch self {
            case .subtitles: return "字幕与语言"
            case .sources: return "字幕来源"
            case .translation: return "翻译服务"
            case .appearance: return "外观"
            case .data: return "缓存与隐私"
            }
        }

        var symbol: String {
            switch self {
            case .subtitles: return "captions.bubble"
            case .sources: return "point.3.connected.trianglepath.dotted"
            case .translation: return "character.bubble"
            case .appearance: return "display"
            case .data: return "key"
            }
        }
    }

    private let settings = AppSettings.shared
    private let state = AppState.shared
    private let supadataProvider = SupadataTranscriptProvider()
    private let table = NSTableView()
    private let content = NSView()
    private var selectedTab: Tab = .subtitles
    private var baseURLField: NSTextField?
    private var modelField: NSTextField?
    private var keyField: NSSecureTextField?
    private var connectionLabel: NSTextField?
    private var supadataKeyField: NSSecureTextField?
    private var sourceConnectionLabel: NSTextField?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "EchoSub 设置"
        window.backgroundColor = EchoStyle.windowBackground
        window.setFrameAutosaveName("EchoSub.settings")
        super.init(window: window)
        window.delegate = self
        buildInterface()
        showTab(.subtitles)
    }

    required init?(coder: NSCoder) { nil }

    func showTranslationSettings() {
        let row = Tab.translation.rawValue
        if table.selectedRow != row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        if selectedTab != .translation {
            showTab(.translation)
        }
    }

    private func buildInterface() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = EchoStyle.windowBackground.cgColor
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(split)
        split.pinEdges(to: root)

        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = EchoStyle.sidebarBackground.cgColor
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings-tab"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 34
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scroll)
        scroll.pinEdges(to: sidebar, insets: NSEdgeInsets(top: 16, left: 8, bottom: 12, right: 8))

        content.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(content)
        sidebar.widthAnchor.constraint(equalToConstant: 172).isActive = true
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Tab.allCases.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tab = Tab(rawValue: row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("settings-tab-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = EchoStyle.label("", size: 12, weight: .medium)
            cell.textField = label
            cell.addSubview(label)
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 28).isActive = true
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
            let image = NSImageView()
            image.identifier = NSUserInterfaceItemIdentifier("tab-icon")
            image.translatesAutoresizingMaskIntoConstraints = false
            image.contentTintColor = EchoStyle.accent
            cell.addSubview(image)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 14),
                image.heightAnchor.constraint(equalToConstant: 14),
            ])
        }
        cell.textField?.stringValue = tab.title
        (cell.subviews.first(where: { $0.identifier?.rawValue == "tab-icon" }) as? NSImageView)?.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tab = Tab(rawValue: table.selectedRow) else { return }
        showTab(tab)
    }

    private func showTab(_ tab: Tab) {
        if selectedTab == .translation { saveTranslationFields() }
        if selectedTab == .sources { saveSourceFields() }
        selectedTab = tab
        content.removeAllSubviews()
        let page = NSView()
        page.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(page)
        page.pinEdges(to: content, insets: NSEdgeInsets(top: 18, left: 22, bottom: 24, right: 22))
        let title = EchoStyle.label(tab.title, size: 16, weight: .bold)
        let body: NSView
        switch tab {
        case .subtitles: body = makeSubtitleSettings()
        case .sources: body = makeSourceSettings()
        case .translation: body = makeTranslationSettings()
        case .appearance: body = makeAppearanceSettings()
        case .data: body = makeDataSettings()
        }
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor),
        ])
    }

    private func makeSourceSettings() -> NSView {
        let direct = EchoStyle.label("① 内置读取", size: 11.5, weight: .semibold)
        let executable = YTDLPTranscriptProvider.executableURL
        let ytDLPStatus = EchoStyle.label(executable == nil ? "○ 未安装" : "● 已检测", size: 11.5, weight: .semibold)
        ytDLPStatus.textColor = executable == nil ? .systemOrange : .systemGreen

        let key = NSSecureTextField(string: PlaintextCredentialStore.shared.loadSupadataAPIKey())
        key.placeholderString = "Supadata API Key"
        styleInput(key, width: 178)
        supadataKeyField = key
        let test = EchoStyle.button("测试", target: self, action: #selector(testSupadata))
        let keyStack = NSStackView(views: [key, test])
        keyStack.orientation = .horizontal
        keyStack.spacing = 8

        let status = EchoStyle.label("", size: 10.5, color: EchoStyle.textTertiary, lines: 2)
        sourceConnectionLabel = status
        let pathDetail = executable?.path ?? "推荐运行 brew install yt-dlp；未安装时自动跳过"
        return form([
            row("来源优先级", detail: "内置 YouTube → 本机 yt-dlp → Supadata", control: direct),
            row("yt-dlp", detail: pathDetail, control: ytDLPStatus),
            row("Supadata API Key", detail: "仅当前两种方式失败后使用", control: keyStack),
            row("Supadata 状态", control: status),
            note("Supadata 使用 mode=native，只读取已有字幕，避免自动触发 AI 转写费用。API Key 以明文保存在本机 Application Support/EchoSub/credentials.json；公开视频不需要 YouTube 登录。"),
        ])
    }

    private func makeSubtitleSettings() -> NSView {
        let language = NSPopUpButton()
        language.addItems(withTitles: ["英语"])
        let target = NSPopUpButton()
        target.addItems(withTitles: ["简体中文"])
        let mode = NSSegmentedControl(labels: ["原文", "中文", "双语"], trackingMode: .selectOne, target: self, action: #selector(defaultModeChanged(_:)))
        mode.selectedSegment = settings.subtitleMode.rawValue
        let follow = NSButton(checkboxWithTitle: "自动跟随播放", target: self, action: #selector(autoFollowChanged(_:)))
        follow.state = settings.autoFollow ? .on : .off
        return form([
            row("首选原字幕语言", detail: "优先人工字幕，其次自动生成字幕", control: language),
            row("目标翻译语言", detail: "第一版支持简体中文", control: target),
            row("默认字幕模式", control: mode),
            row("自动跟随", detail: "字幕随视频时间自动滚动", control: follow),
            note("碎片化的机器字幕会按完整语义合并为 2～8 秒短句；英文原文为第一阅读层级。"),
        ])
    }

    private func makeTranslationSettings() -> NSView {
        let provider = NSPopUpButton()
        provider.addItems(withTitles: ["OpenAI 兼容接口"])
        let base = NSTextField(string: settings.translationBaseURL)
        base.placeholderString = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        styleInput(base)
        baseURLField = base
        let model = NSTextField(string: settings.translationModel)
        model.placeholderString = "qwen3.7-plus"
        styleInput(model)
        modelField = model
        let key = NSSecureTextField(string: PlaintextCredentialStore.shared.loadTranslationAPIKey())
        key.placeholderString = "sk-…"
        styleInput(key)
        keyField = key
        let test = EchoStyle.button("测试连接", target: self, action: #selector(testTranslation))
        let status = EchoStyle.label("", size: 11, color: EchoStyle.textTertiary)
        connectionLabel = status
        let keyStack = NSStackView(views: [key, test])
        keyStack.orientation = .horizontal
        keyStack.spacing = 8
        return form([
            row("翻译服务", detail: "使用你自己的 API Key", control: provider),
            row("API Base URL", detail: "可指向兼容接口或代理服务", control: base),
            row("模型名称", control: model),
            row("API Key", detail: "本机明文 credentials.json", control: keyStack),
            row("连接状态", control: status),
            note("翻译按小批量逐句生成并缓存，不阻塞视频播放；视频标题与字幕文本会发送给你配置的服务。"),
        ])
    }

    private func makeAppearanceSettings() -> NSView {
        let slider = NSSlider(value: settings.overlayFontSize, minValue: 12, maxValue: 36, target: self, action: #selector(fontSizeChanged(_:)))
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let englishSize = NSSlider(value: settings.desktopEnglishFontSize, minValue: 12, maxValue: 48, target: self, action: #selector(desktopEnglishFontChanged(_:)))
        let chineseSize = NSSlider(value: settings.desktopChineseFontSize, minValue: 12, maxValue: 48, target: self, action: #selector(desktopChineseFontChanged(_:)))
        englishSize.widthAnchor.constraint(equalToConstant: 96).isActive = true
        chineseSize.widthAnchor.constraint(equalToConstant: 96).isActive = true
        let sizes = labeledControls([("英", englishSize), ("中", chineseSize)])

        let floatingOpacity = NSSlider(value: settings.floatingBackgroundOpacity, minValue: 0, maxValue: 1, target: self, action: #selector(floatingOpacityChanged(_:)))
        floatingOpacity.isContinuous = true
        floatingOpacity.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let lyricsOpacity = NSSlider(value: settings.desktopLyricsBackgroundOpacity, minValue: 0, maxValue: 1, target: self, action: #selector(lyricsOpacityChanged(_:)))
        lyricsOpacity.isContinuous = true
        lyricsOpacity.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let palette = NSPopUpButton()
        palette.addItems(withTitles: SubtitlePalette.presets.map(\.name) + ["自定义"])
        if let index = SubtitlePalette.presets.firstIndex(where: { $0.id == settings.subtitlePaletteID }) {
            palette.selectItem(at: index)
        } else {
            palette.selectItem(at: SubtitlePalette.presets.count)
        }
        palette.target = self
        palette.action = #selector(paletteChanged(_:))

        let englishColor = colorControl(color: settings.englishSubtitleColor, action: #selector(englishColorChanged(_:)))
        let chineseColor = colorControl(color: settings.chineseSubtitleColor, action: #selector(chineseColorChanged(_:)))
        let pin = NSButton(checkboxWithTitle: "悬浮窗默认 Pin 置顶", target: self, action: #selector(pinChanged(_:)))
        pin.state = settings.floatPinned ? .on : .off
        let spaces = NSButton(checkboxWithTitle: "在所有桌面空间显示", target: self, action: #selector(spacesChanged(_:)))
        spaces.state = settings.showsOnAllSpaces ? .on : .off
        return form([
            row("悬浮字幕字号", control: slider),
            row("桌面歌词字号", detail: "英文与中文分别调节", control: sizes),
            row("悬浮字幕背景", detail: "最左为完全透明", control: floatingOpacity),
            row("桌面歌词背景", detail: "最左为完全透明", control: lyricsOpacity),
            row("字幕配色预设", control: palette),
            row("英文字体颜色", control: englishColor),
            row("中文字体颜色", control: chineseColor),
            row("默认 Pin 置顶", control: pin),
            row("跨桌面显示", control: spaces),
            note("字体颜色会同时应用到右侧字幕、悬浮字幕和桌面歌词。"),
        ])
    }

    private func labeledControls(_ controls: [(String, NSView)]) -> NSView {
        let views = controls.flatMap { title, control -> [NSView] in
            [EchoStyle.label(title, size: 10.5, color: EchoStyle.textSecondary), control]
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        return stack
    }

    private func colorControl(color: NSColor, action: Selector) -> NSView {
        let well = NSColorWell()
        well.color = color
        well.target = self
        well.action = action
        well.widthAnchor.constraint(equalToConstant: 96).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return well
    }

    private func makeDataSettings() -> NSView {
        let clearCache = EchoStyle.button("清除字幕缓存", target: self, action: #selector(clearCache))
        let clearHistory = EchoStyle.button("清除全部播放记录", target: self, action: #selector(clearHistory))
        let reset = EchoStyle.button("恢复默认…", target: self, action: #selector(resetSettings))
        return form([
            row("字幕与翻译缓存", detail: "保存在本机，离线可继续阅读", control: clearCache),
            row("播放记录", detail: "播放列表、观看进度与窗口位置", control: clearHistory),
            row("恢复默认设置", control: reset),
            note("EchoSub 不要求登录 Google 或 YouTube，也不上传播放列表、观看历史或窗口设置。API Key 以明文保存在 Application Support/EchoSub/credentials.json，与字幕资料位于同一文件夹。"),
        ])
    }

    private func form(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 412).isActive = true
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 9
        stack.layer?.borderWidth = 0.5
        stack.layer?.borderColor = EchoStyle.separator.cgColor
        stack.layer?.backgroundColor = EchoStyle.panelBackground.cgColor
        return stack
    }

    private func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let titleLabel = EchoStyle.label(title, size: 12.5, weight: .medium)
        var labels = [titleLabel]
        if let detail { labels.append(EchoStyle.label(detail, size: 10.5, color: EchoStyle.textTertiary, lines: 2)) }
        let labelStack = NSStackView(views: labels)
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        let spacer = NSView()
        let stack = NSStackView(views: [labelStack, spacer, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 412).isActive = true
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: detail == nil ? 42 : 52).isActive = true
        return stack
    }

    private func styleInput(_ field: NSTextField, width: CGFloat = 235) {
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 12.5)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.72)
        field.textColor = EchoStyle.textPrimary
        field.focusRingType = .exterior
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func note(_ text: String) -> NSView {
        let label = EchoStyle.label(text, size: 10.5, color: EchoStyle.textTertiary, lines: 5)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(equalToConstant: 412),
        ])
        return container
    }

    private func saveTranslationFields() {
        if let value = baseURLField?.stringValue, !value.isEmpty { settings.translationBaseURL = value }
        if let value = modelField?.stringValue, !value.isEmpty { settings.translationModel = value }
        if let value = keyField?.stringValue { PlaintextCredentialStore.shared.saveTranslationAPIKey(value) }
    }

    private func saveSourceFields() {
        if let value = supadataKeyField?.stringValue {
            PlaintextCredentialStore.shared.saveSupadataAPIKey(value)
        }
    }

    @objc private func defaultModeChanged(_ sender: NSSegmentedControl) { settings.subtitleMode = SubtitleDisplayMode(rawValue: sender.selectedSegment) ?? .bilingual }
    @objc private func autoFollowChanged(_ sender: NSButton) { settings.autoFollow = sender.state == .on }
    @objc private func fontSizeChanged(_ sender: NSSlider) { settings.overlayFontSize = sender.doubleValue }
    @objc private func desktopEnglishFontChanged(_ sender: NSSlider) { settings.desktopEnglishFontSize = sender.doubleValue }
    @objc private func desktopChineseFontChanged(_ sender: NSSlider) { settings.desktopChineseFontSize = sender.doubleValue }
    @objc private func floatingOpacityChanged(_ sender: NSSlider) { settings.floatingBackgroundOpacity = sender.doubleValue }
    @objc private func lyricsOpacityChanged(_ sender: NSSlider) { settings.desktopLyricsBackgroundOpacity = sender.doubleValue }
    @objc private func paletteChanged(_ sender: NSPopUpButton) {
        guard let palette = SubtitlePalette.presets[safeSettings: sender.indexOfSelectedItem] else {
            settings.subtitlePaletteID = "custom"
            return
        }
        settings.applySubtitlePalette(palette)
        showTab(.appearance)
    }
    @objc private func englishColorChanged(_ sender: NSColorWell) { settings.subtitlePaletteID = "custom"; settings.englishColorHex = sender.color.echoHex }
    @objc private func chineseColorChanged(_ sender: NSColorWell) { settings.subtitlePaletteID = "custom"; settings.chineseColorHex = sender.color.echoHex }
    @objc private func pinChanged(_ sender: NSButton) { settings.floatPinned = sender.state == .on }
    @objc private func spacesChanged(_ sender: NSButton) { settings.showsOnAllSpaces = sender.state == .on }

    @objc private func testTranslation() {
        saveTranslationFields()
        connectionLabel?.stringValue = "正在测试…"
        connectionLabel?.textColor = EchoStyle.textSecondary
        TranslationService().testConnection(configuration: settings.translationConfiguration) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.connectionLabel?.stringValue = "● 连接成功"
                    self?.connectionLabel?.textColor = .systemGreen
                case .failure(let error):
                    self?.connectionLabel?.stringValue = error.localizedDescription
                    self?.connectionLabel?.textColor = .systemRed
                }
            }
        }
    }

    @objc private func testSupadata() {
        saveSourceFields()
        sourceConnectionLabel?.stringValue = "正在测试…"
        sourceConnectionLabel?.textColor = EchoStyle.textSecondary
        supadataProvider.test(apiKey: AppSettings.shared.supadataAPIKey) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.sourceConnectionLabel?.stringValue = "● 连接成功"
                    self?.sourceConnectionLabel?.textColor = .systemGreen
                case .failure(let error):
                    self?.sourceConnectionLabel?.stringValue = error.localizedDescription
                    self?.sourceConnectionLabel?.textColor = .systemRed
                }
            }
        }
    }

    @objc private func clearCache() { confirm(title: "清除字幕缓存？", message: "播放列表会保留，原字幕和翻译结果将被删除。") { self.state.clearTranscriptCache() } }
    @objc private func clearHistory() { confirm(title: "清除全部播放记录？", message: "播放列表、观看进度、字幕和翻译缓存都会被删除。") { self.state.clearAllHistory() } }
    @objc private func resetSettings() { confirm(title: "恢复默认设置？", message: "窗口中的外观和字幕偏好将恢复默认值。") { self.settings.reset(); self.showTab(self.selectedTab) } }

    private func confirm(title: String, message: String, action: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { action() } }
    }

    func windowWillClose(_ notification: Notification) {
        saveTranslationFields()
        saveSourceFields()
    }
}

private extension Array {
    subscript(safeSettings index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

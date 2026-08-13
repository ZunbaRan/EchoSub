import AppKit

final class BackgroundCardPanel: NSView {
    var onClose: (() -> Void)?
    var onGenerate: (() -> Void)?
    var onRegenerate: ((Bool) -> Void)?
    var onSave: ((VideoBackgroundCard) -> Void)?
    var onSeek: ((Double) -> Void)?

    private var video: VideoItem?
    private var backgroundCard: VideoBackgroundCard?
    private var isGenerating = false
    private var errorMessage: String?
    private var isEditing = false
    private var expandedSections: Set<String> = ["chapters"]

    private var overviewEditor: NSTextView?
    private var domainField: NSTextField?
    private var toneField: NSTextField?
    private var chapterTitleFields: [NSTextField] = []
    private var entityTranslationFields: [NSTextField] = []
    private var termTranslationFields: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = EchoStyle.windowBackground.cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }

    func render(
        video: VideoItem?,
        card: VideoBackgroundCard?,
        generating: Bool,
        error: String?
    ) {
        let videoChanged = self.video?.id != video?.id
        self.video = video
        backgroundCard = card
        isGenerating = generating
        errorMessage = error
        if videoChanged { isEditing = false }
        rebuild()
    }

    private func rebuild() {
        removeAllSubviews()
        resetEditControls()
        let header = makeHeader()
        addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 54),
        ])

        if isGenerating {
            addStateBody(
                symbol: "sparkles",
                title: "正在理解视频内容",
                detail: "正在阅读完整字幕并整理全文概括、章节、人物与术语。视频仍可正常播放。",
                spinning: true,
                actionTitle: nil
            )
        } else if let backgroundCard {
            addCardBody(backgroundCard)
        } else if let errorMessage {
            addStateBody(
                symbol: "exclamationmark.triangle",
                title: "背景分析未完成",
                detail: errorMessage + "\n字幕翻译仍可使用局部上下文继续。",
                spinning: false,
                actionTitle: "重新生成"
            )
        } else {
            addStateBody(
                symbol: "sparkles",
                title: "生成视频背景卡",
                detail: "模型会先阅读完整字幕，生成全文概括、章节、人物和术语，再作为后续翻译的全局背景。",
                spinning: false,
                actionTitle: "开始分析"
            )
        }
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!)
        icon.contentTintColor = EchoStyle.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = EchoStyle.label("视频背景", size: 14, weight: .semibold)
        var controls: [NSView] = [icon, title, NSView()]
        if backgroundCard != nil, !isGenerating {
            let edit = EchoStyle.button(isEditing ? "完成编辑" : "编辑", symbol: isEditing ? "checkmark" : "pencil", target: self, action: #selector(toggleEditing))
            edit.isBordered = false
            controls.append(edit)
            controls.append(EchoStyle.iconButton("ellipsis", help: "背景卡操作", target: self, action: #selector(showCardMenu(_:))))
        }
        controls.append(EchoStyle.iconButton("xmark", help: "关闭背景卡", target: self, action: #selector(closePanel)))
        let stack = NSStackView(views: controls)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        let separator = SeparatorView()
        header.addSubview(separator)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        return header
    }

    private func addStateBody(
        symbol: String,
        title: String,
        detail: String,
        spinning: Bool,
        actionTitle: String?
    ) {
        let body = FlippedView()
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        let icon: NSView
        if spinning {
            let progress = LoadingIndicator(small: false)
            progress.startAnimation(nil)
            icon = progress
        } else {
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
            image.contentTintColor = errorMessage == nil ? EchoStyle.accent : NSColor.systemOrange
            image.translatesAutoresizingMaskIntoConstraints = false
            icon = image
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
        ])
        let titleLabel = EchoStyle.label(title, size: 15, weight: .semibold)
        let detailLabel = EchoStyle.label(detail, size: 12, color: EchoStyle.textSecondary, lines: 0)
        detailLabel.alignment = .center
        detailLabel.cell?.alignment = .center
        var views: [NSView] = [icon, titleLabel, detailLabel]
        if let actionTitle {
            views.append(EchoStyle.button(actionTitle, symbol: "arrow.clockwise", target: self, action: #selector(generateCard), primary: true))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(stack)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: topAnchor, constant: 54),
            body.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: body.centerYAnchor, constant: -18),
            detailLabel.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor, constant: -44),
        ])
    }

    private func addCardBody(_ card: VideoBackgroundCard) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 54),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
        ])

        let metadata = metadataText(for: card)
        stack.addArrangedSubview(EchoStyle.label(metadata, size: 11, color: EchoStyle.textTertiary, lines: 0))
        if isEditing {
            addEditingSections(card, to: stack)
        } else {
            addReadingSections(card, to: stack)
        }
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func addReadingSections(_ card: VideoBackgroundCard, to stack: NSStackView) {
        let overview = EchoStyle.label(card.overview, size: 13, color: EchoStyle.textPrimary, lines: 0)
        stack.addArrangedSubview(makeSection(title: "全文概括", symbol: "text.alignleft", content: [overview]))

        let chapters = card.chapters.map { chapter -> NSView in
            let button = NSButton(title: "\(formattedTime(chapter.start))   \(chapter.title)", target: self, action: #selector(seekChapter(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(String(chapter.start))
            button.bezelStyle = .inline
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = EchoStyle.textPrimary
            button.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
            return button
        }
        stack.addArrangedSubview(makeSection(title: "章节概览", symbol: "list.bullet.rectangle", content: chapters.isEmpty ? [emptyLabel("没有识别出清晰章节")] : chapters))

        let infoRows: [NSView] = [
            makeKeyValueRow(key: "领域", value: card.domain),
            makeKeyValueRow(key: "表达", value: card.tone),
        ]
        stack.addArrangedSubview(makeDisclosureSection(key: "style", title: "领域与表达风格", symbol: "quote.bubble", count: nil, content: infoRows))

        let entityRows = card.entities.map { makeKeyValueRow(key: $0.source, value: $0.preferredTranslation) }
        stack.addArrangedSubview(makeDisclosureSection(key: "entities", title: "人物与机构", symbol: "person.2", count: card.entities.count, content: entityRows))

        let termRows = card.terminology.map { makeKeyValueRow(key: $0.source, value: $0.preferredTranslation) }
        stack.addArrangedSubview(makeDisclosureSection(key: "terms", title: "术语表", symbol: "character.book.closed", count: card.terminology.count, content: termRows))

        let uncertaintyRows = card.uncertainties.map {
            makeKeyValueRow(key: $0.cueID, value: $0.note, valueColor: NSColor.systemOrange)
        }
        stack.addArrangedSubview(makeDisclosureSection(key: "uncertainties", title: "疑似识别问题", symbol: "exclamationmark.bubble", count: card.uncertainties.count, content: uncertaintyRows))

        let hint = EchoStyle.label("背景卡仅用于帮助模型理解全局语境；原句与相邻字幕始终具有更高优先级。", size: 10, color: EchoStyle.textTertiary, lines: 0)
        stack.addArrangedSubview(hint)
    }

    private func addEditingSections(_ card: VideoBackgroundCard, to stack: NSStackView) {
        let overview = makeMultilineEditor(card.overview, height: 150)
        overviewEditor = overview.textView
        stack.addArrangedSubview(makeSection(title: "全文概括", symbol: "text.alignleft", content: [overview.scroll]))

        let domain = makeTextField(card.domain)
        domainField = domain
        let tone = makeTextField(card.tone)
        toneField = tone
        stack.addArrangedSubview(makeSection(title: "领域与表达风格", symbol: "quote.bubble", content: [
            makeLabeledEditor(label: "领域", field: domain),
            makeLabeledEditor(label: "表达", field: tone),
        ]))

        chapterTitleFields = card.chapters.map { makeTextField($0.title) }
        let chapterRows = zip(card.chapters, chapterTitleFields).map { chapter, field -> NSView in
            let row = NSStackView(views: [fixedLabel(formattedTime(chapter.start), width: 52), field])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        stack.addArrangedSubview(makeSection(title: "章节标题", symbol: "list.bullet.rectangle", content: chapterRows))

        entityTranslationFields = card.entities.map { makeTextField($0.preferredTranslation) }
        let entityRows = zip(card.entities, entityTranslationFields).map { item, field in
            makeLabeledEditor(label: item.source, field: field)
        }
        stack.addArrangedSubview(makeSection(title: "人物与机构", symbol: "person.2", content: entityRows.isEmpty ? [emptyLabel("暂无人物或机构")] : entityRows))

        termTranslationFields = card.terminology.map { makeTextField($0.preferredTranslation) }
        let termRows = zip(card.terminology, termTranslationFields).map { item, field in
            makeLabeledEditor(label: item.source, field: field)
        }
        stack.addArrangedSubview(makeSection(title: "术语表", symbol: "character.book.closed", content: termRows.isEmpty ? [emptyLabel("暂无术语")] : termRows))

        let cancel = EchoStyle.button("取消", target: self, action: #selector(cancelEditing))
        let save = EchoStyle.button("保存并应用", symbol: "checkmark", target: self, action: #selector(saveEdits), primary: true)
        let actions = NSStackView(views: [NSView(), cancel, save])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(actions)
    }

    private func makeSection(title: String, symbol: String, content: [NSView]) -> NSView {
        let container = EchoStyle.card()
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = EchoStyle.textSecondary
        icon.translatesAutoresizingMaskIntoConstraints = false
        let heading = EchoStyle.label(title, size: 12, weight: .semibold)
        let header = NSStackView(views: [icon, heading, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        let stack = NSStackView(views: [header] + content)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        stack.pinEdges(to: container, insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for view in content { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return container
    }

    private func makeDisclosureSection(key: String, title: String, symbol: String, count: Int?, content: [NSView]) -> NSView {
        let expanded = expandedSections.contains(key)
        let suffix = count.map { "  ·  \($0)" } ?? ""
        let button = NSButton(title: title + suffix, target: self, action: #selector(toggleDisclosure(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.alignment = .left
        button.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = EchoStyle.textPrimary
        button.translatesAutoresizingMaskIntoConstraints = false
        let container = EchoStyle.card()
        let visibleContent = expanded ? (content.isEmpty ? [emptyLabel("暂无内容")] : content) : []
        let stack = NSStackView(views: [button] + visibleContent)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        stack.pinEdges(to: container, insets: NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
        button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for view in visibleContent { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return container
    }

    private func makeKeyValueRow(key: String, value: String, valueColor: NSColor = EchoStyle.textPrimary) -> NSView {
        let keyLabel = EchoStyle.label(key.isEmpty ? "—" : key, size: 11, weight: .medium, color: EchoStyle.textSecondary, lines: 0)
        let valueLabel = EchoStyle.label(value.isEmpty ? "—" : value, size: 12, color: valueColor, lines: 0)
        let stack = NSStackView(views: [keyLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeLabeledEditor(label: String, field: NSTextField) -> NSView {
        let labelView = EchoStyle.label(label, size: 10, weight: .medium, color: EchoStyle.textSecondary, lines: 0)
        let stack = NSStackView(views: [labelView, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeTextField(_ value: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = .systemFont(ofSize: 12)
        field.textColor = EchoStyle.textPrimary
        field.backgroundColor = NSColor.black.withAlphaComponent(0.18)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return field
    }

    private func makeMultilineEditor(_ value: String, height: CGFloat) -> (scroll: NSScrollView, textView: NSTextView) {
        let textView = NSTextView()
        textView.string = value
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = EchoStyle.textPrimary
        textView.backgroundColor = NSColor.black.withAlphaComponent(0.18)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 7, height: 7)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return (scroll, textView)
    }

    private func fixedLabel(_ text: String, width: CGFloat) -> NSTextField {
        let label = EchoStyle.label(text, size: 11, color: EchoStyle.textTertiary)
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        EchoStyle.label(text, size: 11, color: EchoStyle.textTertiary, lines: 0)
    }

    private func metadataText(for card: VideoBackgroundCard) -> String {
        let duration = video?.duration.map(formattedTime) ?? "时长未知"
        let edited = card.wasEdited ? " · 已编辑" : ""
        return "全文分析完成 · \(duration) · \(card.sourceSegmentCount) 句\(edited)"
    }

    private func resetEditControls() {
        overviewEditor = nil
        domainField = nil
        toneField = nil
        chapterTitleFields = []
        entityTranslationFields = []
        termTranslationFields = []
    }

    @objc private func closePanel() { onClose?() }

    @objc private func generateCard() { onGenerate?() }

    @objc private func toggleEditing() {
        if isEditing {
            saveEdits()
        } else {
            isEditing = true
            rebuild()
        }
    }

    @objc private func cancelEditing() {
        isEditing = false
        rebuild()
    }

    @objc private func saveEdits() {
        guard var card = backgroundCard else { return }
        card.overview = overviewEditor?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? card.overview
        card.domain = domainField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? card.domain
        card.tone = toneField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? card.tone
        for index in card.chapters.indices where chapterTitleFields.indices.contains(index) {
            card.chapters[index].title = chapterTitleFields[index].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for index in card.entities.indices where entityTranslationFields.indices.contains(index) {
            card.entities[index].preferredTranslation = entityTranslationFields[index].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for index in card.terminology.indices where termTranslationFields.indices.contains(index) {
            card.terminology[index].preferredTranslation = termTranslationFields[index].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !card.overview.isEmpty else {
            NSSound.beep()
            return
        }
        backgroundCard = card
        isEditing = false
        onSave?(card)
        rebuild()
    }

    @objc private func toggleDisclosure(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        if expandedSections.contains(key) {
            expandedSections.remove(key)
        } else {
            expandedSections.insert(key)
        }
        rebuild()
    }

    @objc private func seekChapter(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let seconds = Double(value) else { return }
        onSeek?(seconds)
    }

    @objc private func showCardMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "背景卡操作")
        let regenerate = NSMenuItem(title: "重新生成背景卡…", action: #selector(regenerateCard), keyEquivalent: "")
        regenerate.target = self
        menu.addItem(regenerate)
        let copy = NSMenuItem(title: "复制背景卡", action: #selector(copyCard), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 2), in: sender)
    }

    @objc private func regenerateCard() { onRegenerate?(false) }

    @objc private func copyCard() {
        guard let card = backgroundCard else { return }
        var lines = ["# 视频全文概括", "", card.overview, "", "## 章节概览"]
        lines += card.chapters.map { "- \(formattedTime($0.start))  \($0.title)" }
        if !card.domain.isEmpty { lines += ["", "## 领域", card.domain] }
        if !card.tone.isEmpty { lines += ["", "## 表达风格", card.tone] }
        if !card.entities.isEmpty {
            lines += ["", "## 人物与机构"]
            lines += card.entities.map { "- \($0.source) → \($0.preferredTranslation)" }
        }
        if !card.terminology.isEmpty {
            lines += ["", "## 术语表"]
            lines += card.terminology.map { "- \($0.source) → \($0.preferredTranslation)" }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

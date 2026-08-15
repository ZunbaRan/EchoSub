import AppKit

private final class FlippedVocabularyStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private enum VocabDetailLayout {
    static let preferredSize = NSSize(width: 348, height: 480)
    static let horizontalPadding: CGFloat = 26
    static let bodyInsets = NSEdgeInsets(top: 10, left: horizontalPadding, bottom: 18, right: horizontalPadding)
    static let chipRowWidth: CGFloat = preferredSize.width - horizontalPadding * 2
    static let bodyLineSpacing: CGFloat = 4
    static let paragraphSpacing: CGFloat = 7
}

enum VocabularyPanelText {
    static func count(_ entriesCount: Int) -> String { String(entriesCount) }

    static func source(timestamp: Double, sentence: String) -> String {
        "\(formattedTime(timestamp))  \(sentence)"
    }

    static func detailSource(timestamp: Double, sentence: String) -> String {
        "本句  \(formattedTime(timestamp))  \(sentence)"
    }
}

final class VideoVocabularyPanel: NSView {
    var onClose: (() -> Void)?
    var onSelectDetail: ((VocabularySummaryEntry) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onRemove: ((VocabularySummaryEntry) -> Void)?

    private let title = EchoStyle.label("本片词汇", size: 14, weight: .semibold)
    private let count = EchoStyle.label("0", size: 11, color: EchoStyle.textTertiary)
    private let closeButton = EchoStyle.iconButton("xmark", help: "关闭本片词汇", target: nil, action: nil)
    private let scroll = NSScrollView()
    private let stack = FlippedVocabularyStackView()
    private var entries: [VocabularySummaryEntry] = []
    private var actionTargets: [VocabularyClosureTarget] = []

    var displayedCount: String { count.stringValue }
    var scrollDocumentWidth: CGFloat { stack.bounds.width }
    var scrollViewportWidth: CGFloat { scroll.contentView.bounds.width }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = EchoStyle.windowBackground.withAlphaComponent(0.985).cgColor
        buildInterface()
    }

    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        title.translatesAutoresizingMaskIntoConstraints = false
        count.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(close)
        let header = NSStackView(views: [title, count, NSView(), closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            header.heightAnchor.constraint(equalToConstant: 28),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    func render(video: VideoItem?, entries: [VocabularySummaryEntry]) {
        self.entries = entries
        actionTargets.removeAll()
        title.stringValue = "本片词汇"
        count.stringValue = VocabularyPanelText.count(entries.count)
        stack.removeAllArrangedSubviews()
        guard video != nil, !entries.isEmpty else {
            let empty = EchoStyle.label(
                video == nil ? "暂无视频" : "看字幕时选中英文并点击“✨ 直译”，这里会留下本片的词汇痕迹。",
                size: 12,
                color: EchoStyle.textSecondary,
                lines: 0
            )
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return
        }
        for entry in entries {
            stack.addArrangedSubview(makeRow(entry))
        }
    }

    private func makeRow(_ entry: VocabularySummaryEntry) -> NSView {
        let card = EchoStyle.card()
        card.translatesAutoresizingMaskIntoConstraints = false
        let word = NSButton(title: entry.gloss.surface, target: nil, action: nil)
        word.bezelStyle = .inline
        word.isBordered = false
        word.font = .systemFont(ofSize: 12.5, weight: .semibold)
        word.contentTintColor = NSColor(calibratedRed: 0.25, green: 0.61, blue: 1, alpha: 1)
        let wordTarget = VocabularyClosureTarget { [weak self] in self?.onSelectDetail?(entry) }
        actionTargets.append(wordTarget)
        word.target = wordTarget
        word.action = #selector(VocabularyClosureTarget.invoke)
        let pos = EchoStyle.label(entry.gloss.pos ?? "", size: 10, color: EchoStyle.textTertiary)
        let gloss = EchoStyle.label(entry.gloss.gloss, size: 12, color: EchoStyle.textSecondary, lines: 2)
        let remove = EchoStyle.iconButton("trash", help: "删除词汇", target: nil, action: nil)
        remove.contentTintColor = EchoStyle.textTertiary
        let removeTarget = VocabularyClosureTarget { [weak self] in self?.onRemove?(entry) }
        actionTargets.append(removeTarget)
        remove.target = removeTarget
        remove.action = #selector(VocabularyClosureTarget.invoke)
        let header = NSStackView(views: [word, pos, NSView(), remove])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 5
        let source = NSButton(title: VocabularyPanelText.source(timestamp: entry.timestamp, sentence: entry.sourceSentence), target: nil, action: nil)
        source.bezelStyle = .inline
        source.isBordered = false
        source.alignment = .left
        source.font = .systemFont(ofSize: 10.5)
        source.contentTintColor = EchoStyle.textTertiary
        source.lineBreakMode = .byTruncatingTail
        let sourceTarget = VocabularyClosureTarget { [weak self] in self?.onSeek?(entry.timestamp) }
        actionTargets.append(sourceTarget)
        source.target = sourceTarget
        source.action = #selector(VocabularyClosureTarget.invoke)
        let content = NSStackView(views: [header, gloss, source])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 3
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        content.pinEdges(to: card, insets: NSEdgeInsets(top: 8, left: 9, bottom: 8, right: 9))
        gloss.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        source.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return card
    }

    @objc private func close() { onClose?() }
}

final class VocabDetailContentView: NSView {
    var onRetry: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onRelated: ((VocabRelatedWord) -> Void)?
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerContainer = NSView()
    private let headerStack = NSStackView()
    private let headerSeparator = SeparatorView()
    private let scroll = NSScrollView()
    private let stack = FlippedVocabularyStackView()
    private var actionTargets: [VocabularyClosureTarget] = []

    var scrollDocumentWidth: CGFloat { stack.bounds.width }
    var scrollViewportWidth: CGFloat { scroll.contentView.bounds.width }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = EchoStyle.windowBackground.cgColor
        buildInterface()
    }

    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 7
        headerStack.edgeInsets = NSEdgeInsets(
            top: 16,
            left: VocabDetailLayout.horizontalPadding,
            bottom: 13,
            right: VocabDetailLayout.horizontalPadding
        )
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerStack)
        headerStack.pinEdges(to: headerContainer)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = VocabDetailLayout.bodyInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerContainer)
        addSubview(headerSeparator)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerContainer.topAnchor.constraint(equalTo: topAnchor),
            headerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerSeparator.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func render(entry: GlossEntry?, detail: VocabDetail?, state: VocabDetailState, canGoBack: Bool = false) {
        let resolvedDetail = detail
        actionTargets.removeAll()
        headerStack.removeAllArrangedSubviews()
        stack.removeAllArrangedSubviews()
        if let entry {
            let surface = resolvedDetail?.surface.isEmpty == false ? resolvedDetail!.surface : entry.surface
            let pos = resolvedDetail?.pos ?? entry.pos
            let header = makeHeader(
                surface: surface,
                pos: pos,
                phonetic: resolvedDetail?.phonetic,
                gloss: entry.gloss,
                canGoBack: canGoBack
            )
            headerStack.addArrangedSubview(header)
            header.widthAnchor.constraint(
                equalTo: headerStack.widthAnchor,
                constant: -(VocabDetailLayout.horizontalPadding * 2)
            ).isActive = true
        }
        switch state {
        case .loading:
            appendSection(makeSkeleton())
        case .failed(let message):
            let error = EchoStyle.label("生成失败：\(message)", size: 11.5, color: NSColor.systemOrange, lines: 2)
            let retry = EchoStyle.button("重试", symbol: "arrow.clockwise", target: nil, action: nil)
            let target = VocabularyClosureTarget { [weak self] in self?.onRetry?() }
            actionTargets.append(target)
            retry.target = target
            retry.action = #selector(VocabularyClosureTarget.invoke)
            let row = NSStackView(views: [error, retry])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            appendSection(row)
        case .idle:
            guard let detail = resolvedDetail else {
                appendSection(EchoStyle.label("暂无详解。", size: 12, color: EchoStyle.textSecondary))
                return
            }
            renderDetail(detail, entry: entry)
        }
    }

    private func makeHeader(surface: String, pos: String?, phonetic: String?, gloss: String, canGoBack: Bool) -> NSView {
        var rowViews: [NSView] = []
        if canGoBack {
            let back = EchoStyle.iconButton("chevron.left", help: "返回上一个词", target: nil, action: nil)
            let target = VocabularyClosureTarget { [weak self] in self?.onBack?() }
            actionTargets.append(target)
            back.target = target
            back.action = #selector(VocabularyClosureTarget.invoke)
            rowViews.append(back)
        }
        let word = EchoStyle.label(surface, size: 19, weight: .bold)
        rowViews.append(word)
        if let pos, !pos.isEmpty {
            let posLabel = EchoStyle.label(pos, size: 11, color: EchoStyle.textSecondary)
            posLabel.font = NSFontManager.shared.convert(posLabel.font ?? .systemFont(ofSize: 11), toHaveTrait: .italicFontMask)
            rowViews.append(posLabel)
        }
        rowViews.append(NSView())
        let close = EchoStyle.iconButton("xmark", help: "关闭（Esc）", target: nil, action: nil)
        close.contentTintColor = EchoStyle.textSecondary
        let closeTarget = VocabularyClosureTarget { [weak self] in self?.onClose?() }
        actionTargets.append(closeTarget)
        close.target = closeTarget
        close.action = #selector(VocabularyClosureTarget.invoke)
        rowViews.append(close)
        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8

        var headerViews: [NSView] = [row]
        if let phonetic, !phonetic.isEmpty {
            headerViews.append(EchoStyle.label("发音: \(phonetic)", size: 11.5, color: EchoStyle.textSecondary))
        }
        if !gloss.isEmpty {
            let glossLine = [pos, gloss].compactMap { value in
                value?.isEmpty == false ? value : nil
            }.joined(separator: "  ")
            headerViews.append(EchoStyle.label(
                glossLine,
                size: 13,
                weight: .semibold,
                color: NSColor(calibratedRed: 1, green: 0.835, blue: 0.31, alpha: 1),
                lines: 0
            ))
        }
        let header = NSStackView(views: headerViews)
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        for view in headerViews {
            view.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        }
        return header
    }

    private func makeSkeleton() -> NSView {
        let skeleton = NSStackView()
        skeleton.orientation = .vertical
        skeleton.alignment = .width
        skeleton.spacing = 8
        for width in [1.0, 0.78, 0.92, 0.65] {
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            line.layer?.cornerRadius = 3
            line.translatesAutoresizingMaskIntoConstraints = false
            skeleton.addArrangedSubview(line)
            line.heightAnchor.constraint(equalToConstant: 18).isActive = true
            line.widthAnchor.constraint(equalTo: skeleton.widthAnchor, multiplier: CGFloat(width)).isActive = true
        }
        return skeleton
    }

    private func renderDetail(_ detail: VocabDetail, entry: GlossEntry?) {
        if !detail.contextualMeaning.isEmpty {
            let card = EchoStyle.card()
            let title = EchoStyle.label("在这里的意思", size: 11, weight: .semibold, color: EchoStyle.accent)
            let meaning = makeReadingLabel(detail.contextualMeaning, size: 12, color: EchoStyle.textPrimary)
            var contentViews: [NSView] = [title, meaning]
            if let source = detail.examples.first(where: { $0.isSourceExample }), let timestamp = source.timestamp {
                contentViews.append(makeSourceButton(source, timestamp: timestamp))
            }
            let content = NSStackView(views: contentViews)
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 7
            content.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(content)
            content.pinEdges(to: card, insets: NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12))
            for view in contentViews {
                view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
            appendSection(card)
        }
        let isPhrase = VocabularyDetailPromptPolicy.omitsFormsAndEtymology(for: entry?.surface ?? detail.surface)
        if !isPhrase, !detail.forms.isEmpty {
            appendSection(makeChipSection("词形变化", detail.forms.map {
                "\($0.label)  \($0.value)\($0.translation.map { "  \($0)" } ?? "")"
            }))
        }
        if !detail.explanation.isEmpty { appendSection(makeSection("解释", [detail.explanation])) }
        if !isPhrase, !detail.etymology.isEmpty { appendSection(makeSection("词源学", [detail.etymology])) }
        if !detail.memory.isEmpty { appendSection(makeSection("记忆方法", [detail.memory])) }
        addRelatedSection("同根词", detail.cognates)
        addRelatedSection("近义词", detail.synonyms)
        addRelatedSection("反义词", detail.antonyms)
        if !detail.phrases.isEmpty {
            appendSection(makeSection("常用短语", detail.phrases.enumerated().map { "\($0.offset + 1). \($0.element.phrase)\($0.element.translation.map { "  \($0)" } ?? "")" }))
        }
        if !detail.examples.isEmpty {
            appendSection(makeSection("例句", detail.examples.enumerated().map { index, example in
                let prefix = example.isSourceExample ? "本句" : "\(index + 1)"
                return "\(prefix)  \(example.sentence)\(example.translation.map { "\n\($0)" } ?? "")"
            }))
        }
    }

    private func makeSourceButton(_ source: VocabExample, timestamp: Double) -> NSButton {
        let button = NSButton(title: VocabularyPanelText.detailSource(timestamp: timestamp, sentence: source.sentence), target: nil, action: nil)
        button.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放本句")
        button.imagePosition = .imageLeading
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = EchoStyle.textSecondary
        button.lineBreakMode = .byWordWrapping
        button.cell?.wraps = true
        button.cell?.isScrollable = false
        button.cell?.usesSingleLineMode = false
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let target = VocabularyClosureTarget { [weak self] in self?.onSeek?(timestamp) }
        actionTargets.append(target)
        button.target = target
        button.action = #selector(VocabularyClosureTarget.invoke)
        return button
    }

    private func appendSection(_ view: NSView) {
        if !stack.arrangedSubviews.isEmpty {
            let separator = SeparatorView()
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -(VocabDetailLayout.horizontalPadding * 2)
            ).isActive = true
        }
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(
            equalTo: stack.widthAnchor,
            constant: -(VocabDetailLayout.horizontalPadding * 2)
        ).isActive = true
    }

    private func makeSection(_ title: String, _ values: [String]) -> NSView {
        let heading = EchoStyle.label(title, size: 10.5, weight: .semibold, color: EchoStyle.textTertiary)
        heading.alignment = .left
        heading.cell?.alignment = .left
        let body = makeReadingLabel(
            values.joined(separator: "\n\n"),
            size: 11.5,
            color: EchoStyle.textSecondary
        )
        let section = NSStackView(views: [heading, body])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        section.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 10, right: 0)
        heading.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeChipSection(_ title: String, _ values: [String]) -> NSView {
        let heading = EchoStyle.label(title, size: 10.5, weight: .semibold, color: EchoStyle.textTertiary)
        heading.alignment = .left
        heading.cell?.alignment = .left
        let buttons = values.map { value -> NSButton in
            let button = NSButton(title: value, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 10.5)
            button.contentTintColor = EchoStyle.textSecondary
            return button
        }
        let section = NSStackView(views: [heading, makeChipRows(buttons)])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        section.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 10, right: 0)
        for view in section.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    private func addRelatedSection(_ title: String, _ values: [VocabRelatedWord]) {
        guard !values.isEmpty else { return }
        let heading = EchoStyle.label(title, size: 10.5, weight: .semibold, color: EchoStyle.textTertiary)
        heading.alignment = .left
        heading.cell?.alignment = .left
        var buttons: [NSButton] = []
        for value in values {
            let label = [value.pos, value.word, value.translation].compactMap { item in
                item?.isEmpty == false ? item : nil
            }.joined(separator: "  ")
            let button = NSButton(title: label, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 10.5)
            button.contentTintColor = EchoStyle.textSecondary
            let target = VocabularyClosureTarget { [weak self] in self?.onRelated?(value) }
            actionTargets.append(target)
            button.target = target
            button.action = #selector(VocabularyClosureTarget.invoke)
            buttons.append(button)
        }
        let section = NSStackView(views: [heading, makeChipRows(buttons)])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        section.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 10, right: 0)
        for view in section.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        appendSection(section)
    }

    private func makeReadingLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = EchoStyle.label(text, size: size, color: color, lines: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = VocabDetailLayout.bodyLineSpacing
        paragraph.paragraphSpacing = VocabDetailLayout.paragraphSpacing
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
        label.alignment = .left
        label.cell?.alignment = .left
        label.cell?.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        return label
    }

    private func makeChipRows(_ buttons: [NSButton]) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 5
        var currentRow: NSStackView?
        var usedWidth: CGFloat = 0
        for button in buttons {
            button.sizeToFit()
            let width = min(max(44, button.fittingSize.width), VocabDetailLayout.chipRowWidth)
            if currentRow == nil || usedWidth + (usedWidth > 0 ? 5 : 0) + width > VocabDetailLayout.chipRowWidth {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 5
                rows.addArrangedSubview(row)
                currentRow = row
                usedWidth = 0
            }
            button.widthAnchor.constraint(lessThanOrEqualToConstant: VocabDetailLayout.chipRowWidth).isActive = true
            currentRow?.addArrangedSubview(button)
            usedWidth += (usedWidth > 0 ? 5 : 0) + width
        }
        for case let row as NSStackView in rows.arrangedSubviews {
            row.addArrangedSubview(NSView())
        }
        return rows
    }
}

final class VocabDetailPopover: NSPopover {
    let detailContentView = VocabDetailContentView(frame: .zero)

    override init() {
        super.init()
        behavior = .transient
        animates = true
        detailContentView.onClose = { [weak self] in self?.close() }
        detailContentView.frame = NSRect(origin: .zero, size: VocabDetailLayout.preferredSize)
        let controller = NSViewController()
        controller.view = detailContentView
        controller.preferredContentSize = VocabDetailLayout.preferredSize
        contentViewController = controller
        contentSize = VocabDetailLayout.preferredSize
    }

    required init?(coder: NSCoder) { nil }

    func show(
        entry: GlossEntry?,
        detail: VocabDetail?,
        state: VocabDetailState,
        relativeTo rect: NSRect,
        of view: NSView,
        canGoBack: Bool = false
    ) {
        contentSize = VocabDetailLayout.preferredSize
        detailContentView.render(entry: entry, detail: detail, state: state, canGoBack: canGoBack)
        if !isShown {
            show(relativeTo: rect, of: view, preferredEdge: .minX)
        }
    }
}

private final class VocabularyClosureTarget: NSObject {
    private let closure: () -> Void

    init(_ closure: @escaping () -> Void) { self.closure = closure }

    @objc func invoke() { closure() }
}

private extension NSStackView {
    func removeAllArrangedSubviews() {
        arrangedSubviews.forEach {
            removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }
}

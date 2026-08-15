import AppKit

final class GlossInlineView: NSView {
    var entries: [GlossEntry] = [] { didSet { rebuildText(); invalidateIntrinsicContentSize(); needsDisplay = true } }
    var state: GlossLookupState = .idle { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var fontSize: CGFloat = 10 { didSet { rebuildText(); invalidateIntrinsicContentSize(); needsDisplay = true } }
    var onSelect: ((GlossEntry) -> Void)?
    var onRemove: ((GlossEntry) -> Void)?
    var onRetry: (() -> Void)?

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private var entryRanges: [NSRange] = []
    private struct EntryLayout {
        let characterRange: NSRange
        let glyphRange: NSRange
        let lastGlyphRect: NSRect
        let lastLineFragmentRect: NSRect

        var closeRect: NSRect {
            let width = max(15, lastGlyphRect.width + 8)
            let x = max(lastLineFragmentRect.minX, lastGlyphRect.midX - width / 2)
            return NSRect(
                x: x,
                y: lastLineFragmentRect.minY,
                width: width,
                height: max(15, lastLineFragmentRect.height)
            )
        }
    }
    private var entryLayouts: [EntryLayout] = []
    private var hoveredIndex: Int?
    private var tracking: NSTrackingArea?

    var renderedText: String { textStorage.string }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        rebuildText()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override var intrinsicContentSize: NSSize {
        let width = max(80, bounds.width > 1 ? bounds.width : 280)
        return NSSize(width: NSView.noIntrinsicMetric, height: height(for: width))
    }

    func height(for width: CGFloat) -> CGFloat {
        let entryHeight = Self.measuredHeight(entries: entries, fontSize: fontSize, width: width)
        switch state {
        case .idle:
            return entryHeight
        case .loading, .failed:
            return entryHeight + (entries.isEmpty ? 0 : 5) + 24
        }
    }

    override func layout() {
        super.layout()
        textContainer.containerSize = NSSize(width: max(40, bounds.width), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        rebuildEntryLayouts()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !entries.isEmpty {
            layoutManager.ensureLayout(for: textContainer)
            if let hoveredIndex, entryLayouts.indices.contains(hoveredIndex) {
                let closeRect = entryLayouts[hoveredIndex].closeRect
                NSColor(calibratedWhite: 1, alpha: 0.06).setFill()
                NSBezierPath(roundedRect: closeRect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
            }
            layoutManager.drawBackground(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs), at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs), at: .zero)
        }
        switch state {
        case .loading:
            drawStatus("正在生成…", color: EchoStyle.textTertiary, y: entries.isEmpty ? 1 : height(for: bounds.width) - 24)
        case .failed:
            drawStatus("生成失败 · 重试", color: NSColor.systemOrange, y: entries.isEmpty ? 1 : height(for: bounds.width) - 24)
        case .idle:
            break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = entryIndex(at: point), entries.indices.contains(index) {
            if entryLayouts[index].closeRect.contains(point) {
                onRemove?(entries[index])
            } else {
                onSelect?(entries[index])
            }
            return
        }
        if case .failed = state {
            onRetry?()
        }
    }

    private func updateHover(at point: NSPoint) {
        let next = entryIndex(at: point)
        if next != hoveredIndex {
            hoveredIndex = next
            needsDisplay = true
        }
    }

    func entryIndex(at point: NSPoint) -> Int? {
        guard !entryRanges.isEmpty else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        if entryLayouts.count != entryRanges.count {
            rebuildEntryLayouts()
        }
        if let closeIndex = entryLayouts.firstIndex(where: { $0.closeRect.contains(point) }) {
            return closeIndex
        }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(point) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return entryLayouts.firstIndex { NSLocationInRange(characterIndex, $0.characterRange) }
    }

    func lastGlyphRect(forEntryAt index: Int) -> NSRect? {
        guard entryLayouts.indices.contains(index) else { return nil }
        return entryLayouts[index].lastGlyphRect
    }

    func entryLineFragmentCount(forEntryAt index: Int) -> Int {
        guard entryLayouts.indices.contains(index) else { return 0 }
        let glyphRange = entryLayouts[index].glyphRange
        var lineOrigins: [CGFloat] = []
        for glyphIndex in glyphRange.location..<(glyphRange.location + glyphRange.length) {
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            if !lineOrigins.contains(where: { abs($0 - rect.minY) < 0.5 }) {
                lineOrigins.append(rect.minY)
            }
        }
        return lineOrigins.count
    }

    private func drawStatus(_ text: String, color: NSColor, y: CGFloat) {
        let value = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: max(10, fontSize - 1)),
            .foregroundColor: color,
        ])
        value.draw(at: NSPoint(x: 0, y: y))
    }

    private func rebuildText() {
        textStorage.setAttributedString(makeAttributedString())
        entryRanges.removeAll()
        entryLayouts.removeAll()
        var location = 0
        for (index, entry) in entries.enumerated() {
            let text = "✨ \(entry.surface) · \(entry.gloss)  ×"
            entryRanges.append(NSRange(location: location, length: (text as NSString).length))
            location += (text as NSString).length
            if index < entries.count - 1 {
                location += ("  ┆  " as NSString).length
            }
        }
        textContainer.containerSize = NSSize(width: max(40, bounds.width), height: .greatestFiniteMagnitude)
    }

    private func rebuildEntryLayouts() {
        entryLayouts = entryRanges.compactMap { range in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }
            let lastGlyphIndex = glyphRange.location + glyphRange.length - 1
            let lastGlyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: lastGlyphIndex, length: 1),
                in: textContainer
            )
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            return EntryLayout(
                characterRange: range,
                glyphRange: glyphRange,
                lastGlyphRect: lastGlyphRect,
                lastLineFragmentRect: lineFragmentRect
            )
        }
    }

    static func measuredHeight(entries: [GlossEntry], fontSize: CGFloat, width: CGFloat) -> CGFloat {
        guard !entries.isEmpty else { return 0 }
        return ceil(makeAttributedString(entries: entries, fontSize: fontSize).boundingRect(
            with: NSSize(width: max(40, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 2
    }

    private func makeAttributedString() -> NSAttributedString {
        Self.makeAttributedString(entries: entries, fontSize: fontSize)
    }

    private static func makeAttributedString(entries: [GlossEntry], fontSize: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, entry) in entries.enumerated() {
            let surface = NSAttributedString(string: "✨ \(entry.surface)", attributes: [
                .font: NSFont.systemFont(ofSize: max(10, fontSize), weight: .medium),
                .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.61, blue: 1, alpha: 1),
            ])
            let meaning = NSAttributedString(string: " · \(entry.gloss)", attributes: [
                .font: NSFont.systemFont(ofSize: max(10, fontSize)),
                .foregroundColor: EchoStyle.textSecondary,
            ])
            let close = NSAttributedString(string: "  ×", attributes: [
                .font: NSFont.systemFont(ofSize: max(10.5, fontSize), weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.58),
            ])
            output.append(surface)
            output.append(meaning)
            output.append(close)
            if index < entries.count - 1 {
                output.append(NSAttributedString(string: "  ┆  ", attributes: [
                    .font: NSFont.systemFont(ofSize: max(9, fontSize - 1)),
                    .foregroundColor: EchoStyle.textTertiary,
                ]))
            }
        }
        return output
    }
}

final class InlineTranslationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTextChange: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, frameRect.width), height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        super.init(frame: frameRect, textContainer: container)
        isEditable = true
        isSelectable = true
        isRichText = false
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = NSSize(width: 5, height: 5)
        textContainer?.lineFragmentPadding = 0
        font = .systemFont(ofSize: 12)
        textColor = EchoStyle.textPrimary
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { nil }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommit?()
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

final class InlineTranslationEditor: NSView {
    let textView = InlineTranslationTextView(frame: .zero)
    private let saveButton = EchoStyle.button("保存", symbol: "checkmark", primary: true)
    private let cancelButton = EchoStyle.button("取消", symbol: "xmark")
    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onTextChange: ((String) -> Void)?

    init(value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        layer?.cornerRadius = 6
        textView.string = value
        textView.translatesAutoresizingMaskIntoConstraints = false
        saveButton.target = self
        saveButton.action = #selector(save)
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        textView.onCommit = { [weak self] in self?.save() }
        textView.onCancel = { [weak self] in self?.cancel() }
        textView.onTextChange = { [weak self] text in self?.onTextChange?(text) }
        addSubview(textView)
        addSubview(saveButton)
        addSubview(cancelButton)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            saveButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            saveButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 3),
            saveButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            cancelButton.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 5),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
        textView.setSelectedRange(NSRange(location: 0, length: (value as NSString).length))
    }

    required init?(coder: NSCoder) { nil }

    func focus() {
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
    }

    @objc private func save() { onSave?(textView.string) }
    @objc private func cancel() { onCancel?() }
}

enum SubtitleRowLayout {
    static func rowHeight(
        for segment: SubtitleSegment,
        mode: SubtitleDisplayMode,
        availableWidth: CGFloat,
        editing: Bool = false,
        glossState: GlossLookupState = .idle
    ) -> CGFloat {
        let width = max(100, availableWidth)
        func height(_ text: String, _ font: NSFont) -> CGFloat {
            ceil(NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
        }
        var result: CGFloat = 18
        if mode != .translated { result += height(segment.original, .systemFont(ofSize: 13, weight: .medium)) }
        if mode == .bilingual { result += 5 }
        if editing {
            result += 78
        } else if mode != .original {
            result += height(segment.effectiveTranslation ?? "等待翻译…", .systemFont(ofSize: 12))
            if !segment.glosses.isEmpty {
                let glossText = segment.glosses.map { "✨ \($0.surface) · \($0.gloss)  ×" }.joined(separator: "  ┆  ")
                result += 5 + height(glossText, .systemFont(ofSize: 10))
            }
            if case .loading = glossState { result += 5 + 24 }
            if case .failed = glossState { result += 5 + 24 }
        }
        return max(54, result)
    }
}

import AppKit

final class VocabularySelectionContext {
    let videoID: String
    let segmentID: String
    let surface: String
    weak var textView: SelectableEnglishTextView?
    let rect: NSRect

    init(
        videoID: String,
        segmentID: String,
        surface: String,
        textView: SelectableEnglishTextView? = nil,
        rect: NSRect = .zero
    ) {
        self.videoID = videoID
        self.segmentID = segmentID
        self.surface = surface
        self.textView = textView
        self.rect = rect
    }

    func matches(videoID: String, segmentID: String, surface: String) -> Bool {
        self.videoID == videoID && self.segmentID == segmentID && self.surface == surface
    }

    func isValid(currentVideoID: String, currentSegmentID: String, currentSurface: String, requireActiveTextView: Bool = true) -> Bool {
        guard matches(videoID: currentVideoID, segmentID: currentSegmentID, surface: currentSurface) else { return false }
        guard requireActiveTextView else { return true }
        return textView?.selectedSurfaceText == surface
    }
}

enum SubtitleInteractionAction: Equatable {
    case none
    case pendingSingleClick
    case directGloss
    case selectionToolbar
}

enum SubtitleInteractionPolicy {
    static func action(clickCount: Int, hasEligibleSelection: Bool, isDragSelection: Bool = false) -> SubtitleInteractionAction {
        if clickCount >= 2, hasEligibleSelection { return .directGloss }
        if hasEligibleSelection, isDragSelection { return .selectionToolbar }
        if clickCount == 1, !hasEligibleSelection { return .pendingSingleClick }
        return .none
    }

    static func cancelsPending(clickCount: Int, hasEligibleSelection: Bool) -> Bool {
        clickCount >= 2 || hasEligibleSelection
    }
}

final class SelectableEnglishTextView: NSTextView {
    var segmentID: String?
    var representedVideoID: String?
    var representedSegmentID: String? {
        get { segmentID }
        set { segmentID = newValue }
    }
    var onSelectionToolbar: ((SelectableEnglishTextView, String, NSRect) -> Void)?
    var onDoubleClickGloss: ((SelectableEnglishTextView, String) -> Void)?
    var onContextualGloss: ((SelectableEnglishTextView, String) -> Void)?
    var onPlainClick: (() -> Void)?
    var onInteractionBegan: (() -> Void)?
    private var pendingPlainClick: DispatchWorkItem?
    private var contextualMenuEligible = false
    private var lastIntrinsicWidth: CGFloat = 0
    private static let contextualGlossMarker = "EchoSub.contextualGloss"

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, frameRect.width), height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        super.init(frame: frameRect, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = true
        allowsUndo = false
        drawsBackground = false
        backgroundColor = .clear
        textColor = EchoStyle.textPrimary
        importsGraphics = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        isVerticallyResizable = false
        isHorizontallyResizable = false
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        minSize = .zero
    }

    required init?(coder: NSCoder) { nil }

    deinit { pendingPlainClick?.cancel() }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    override var intrinsicContentSize: NSSize {
        guard bounds.width > 0,
              let layoutManager,
              let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: lineHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(lineHeight, ceil(layoutManager.usedRect(for: textContainer).height))
        )
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        if width > 0, abs(width - lastIntrinsicWidth) > 0.5 {
            lastIntrinsicWidth = width
            invalidateIntrinsicContentSize()
        }
    }

    func configure(text: String, font: NSFont, color: NSColor, alpha: CGFloat = 1) {
        cancelPendingPlainClick()
        contextualMenuEligible = false
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.withAlphaComponent(alpha)]
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        setSelectedRange(NSRange(location: 0, length: 0))
        typingAttributes = attributes
        alignment = .left
        drawsBackground = false
        isSelectable = true
        invalidateIntrinsicContentSize()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextualMenuEligible = representedVideoID != nil && representedSegmentID != nil && selectedSurfaceText != nil
        let menu = super.menu(for: event) ?? NSMenu(title: "文本操作")
        menu.items
            .filter {
                ($0.representedObject as? String) == Self.contextualGlossMarker
                    || $0.action == #selector(contextualGlossFromMenu)
            }
            .forEach { menu.removeItem($0) }
        guard onContextualGloss != nil else { return menu }

        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let item = NSMenuItem(title: "讲解选词", action: #selector(contextualGlossFromMenu), keyEquivalent: "")
        item.target = self
        item.representedObject = Self.contextualGlossMarker
        menu.addItem(item)
        item.isEnabled = contextualMenuEligible
        return menu
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(contextualGlossFromMenu)
            || (menuItem.representedObject as? String) == Self.contextualGlossMarker {
            return contextualMenuEligible && representedVideoID != nil && representedSegmentID != nil && selectedSurfaceText != nil
        }
        return super.validateMenuItem(menuItem)
    }

    var selectedSurfaceText: String? {
        guard let range = lookupSelectionRange() else { return nil }
        return (string as NSString).substring(with: range)
    }

    var selectionRectInViewCoordinates: NSRect {
        guard let range = lookupSelectionRange(), let layoutManager, let textContainer else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        if rect.height < 1 { rect.size.height = lineHeight }
        return rect
    }

    func lookupSelectionRange() -> NSRange? {
        let rawRange = selectedRange()
        guard rawRange.location != NSNotFound, rawRange.length > 0 else { return nil }
        let text = string as NSString
        guard rawRange.location < text.length else { return nil }
        let safeLength = min(rawRange.length, text.length - rawRange.location)
        guard safeLength > 0 else { return nil }
        var start = rawRange.location
        var end = rawRange.location + safeLength

        while start < end, isTrimCharacter(text.character(at: start)) { start += 1 }
        while end > start, isTrimCharacter(text.character(at: end - 1)) { end -= 1 }
        guard start < end else { return nil }

        let selected = text.substring(with: NSRange(location: start, length: end - start))
        let containsWhitespace = selected.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
        if !containsWhitespace {
            while start > 0, isWordCharacter(text.character(at: start - 1)) { start -= 1 }
            while end < text.length, isWordCharacter(text.character(at: end)) { end += 1 }
        }
        let surface = text.substring(with: NSRange(location: start, length: end - start))
        guard isEnglishSurface(surface) else { return nil }
        return NSRange(location: start, length: end - start)
    }

    override func mouseDown(with event: NSEvent) {
        cancelPendingPlainClick()
        onInteractionBegan?()
        let clickCount = event.clickCount
        super.mouseDown(with: event)
        completeSelectionInteraction(clickCount: clickCount)
    }

    func completeSelectionInteraction(clickCount: Int) {
        let surface = selectedSurfaceText
        switch SubtitleInteractionPolicy.action(
            clickCount: clickCount,
            hasEligibleSelection: surface != nil,
            isDragSelection: surface != nil && clickCount < 2
        ) {
        case .directGloss:
            cancelPendingPlainClick()
            if let surface { onDoubleClickGloss?(self, surface) }
        case .selectionToolbar:
            cancelPendingPlainClick()
            if let surface { onSelectionToolbar?(self, surface, selectionRectInViewCoordinates) }
        case .pendingSingleClick:
            schedulePlainClick()
        case .none:
            cancelPendingPlainClick()
        }
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        if selectedSurfaceText != nil {
            cancelPendingPlainClick()
            onSelectionToolbar?(self, selectedSurfaceText ?? "", selectionRectInViewCoordinates)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelPendingPlainClick()
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    @objc private func contextualGlossFromMenu() {
        guard contextualMenuEligible,
              representedVideoID != nil,
              representedSegmentID != nil,
              let surface = selectedSurfaceText else { return }
        onContextualGloss?(self, surface)
    }

    private func schedulePlainClick() {
        cancelPendingPlainClick()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingPlainClick?.isCancelled == false else { return }
            self.pendingPlainClick = nil
            self.onPlainClick?()
        }
        pendingPlainClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    private func cancelPendingPlainClick() {
        pendingPlainClick?.cancel()
        pendingPlainClick = nil
    }

    private var lineHeight: CGFloat {
        (font?.capHeight ?? 13) + (font?.leading ?? 2) + 4
    }

    private func isEnglishSurface(_ value: String) -> Bool {
        guard VocabularyNormalization.isEligibleSurface(value) else { return false }
        let scalars = value.unicodeScalars
        guard scalars.contains(where: { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }) else { return false }
        return !scalars.contains { $0.value >= 0x2E80 && $0.value <= 0x9FFF }
    }

    private func isWordCharacter(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "-"
    }

    private func isTrimCharacter(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar)
    }
}

final class SelectionActionPresenter: NSObject, NSPopoverDelegate {
    static let shared = SelectionActionPresenter()

    private let popover = NSPopover()
    private var target: SelectionActionTarget?

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    func present(
        for textView: SelectableEnglishTextView,
        surface: String,
        rect: NSRect,
        allowsDetail: Bool,
        onGloss: @escaping () -> Void,
        onDetail: (() -> Void)? = nil
    ) {
        close()
        let target = SelectionActionTarget { [weak self] action in
            self?.close()
            if action == .gloss { onGloss() } else { onDetail?() }
        }
        self.target = target
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        stack.layer?.cornerRadius = 7

        let gloss = NSButton(title: "✨ 直译", target: target, action: #selector(SelectionActionTarget.gloss))
        gloss.bezelStyle = .texturedRounded
        gloss.controlSize = .small
        gloss.font = .systemFont(ofSize: 12, weight: .medium)
        gloss.toolTip = surface
        stack.addArrangedSubview(gloss)
        if allowsDetail {
            let detail = NSButton(title: "详解 ▸", target: target, action: #selector(SelectionActionTarget.detail))
            detail.bezelStyle = .texturedRounded
            detail.controlSize = .small
            detail.font = .systemFont(ofSize: 12, weight: .medium)
            stack.addArrangedSubview(detail)
        }

        let controller = NSViewController()
        controller.view = stack
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: allowsDetail ? 136 : 72, height: 32)
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
    }

    func close() {
        popover.close()
        target = nil
    }

    var isShown: Bool { popover.isShown }

    func popoverDidClose(_ notification: Notification) { target = nil }
}

final class VocabularyMainWindow: NSWindow {
    var onGlossShortcut: (() -> Bool)?
    var onDetailShortcut: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch VocabularyShortcutPolicy.action(
            key: event.charactersIgnoringModifiers,
            modifiers: modifiers,
            allowsDetail: onDetailShortcut != nil
        ) {
        case .gloss:
            return onGlossShortcut?() ?? false
        case .detail:
            return onDetailShortcut?() ?? false
        case .ignored:
            return true
        case .none:
            return super.performKeyEquivalent(with: event)
        }
    }
}

enum VocabularyShortcutAction: Equatable {
    case none
    case gloss
    case detail
    case ignored
}

enum VocabularyShortcutPolicy {
    static func action(
        key: String?,
        modifiers: NSEvent.ModifierFlags,
        allowsDetail: Bool
    ) -> VocabularyShortcutAction {
        guard key?.lowercased() == "e", modifiers.contains(.command) else { return .none }
        if modifiers.contains(.shift) {
            return allowsDetail ? .detail : .ignored
        }
        return .gloss
    }
}

final class VocabularyFloatingPanel: NSPanel {
    var onGlossShortcut: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch VocabularyShortcutPolicy.action(key: event.charactersIgnoringModifiers, modifiers: modifiers, allowsDetail: false) {
        case .gloss:
            return onGlossShortcut?() ?? false
        case .detail, .ignored:
            return true
        case .none:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class SelectionActionTarget: NSObject {
    enum Action { case gloss, detail }
    private let handler: (Action) -> Void

    init(handler: @escaping (Action) -> Void) { self.handler = handler }

    @objc func gloss() { handler(.gloss) }
    @objc func detail() { handler(.detail) }
}

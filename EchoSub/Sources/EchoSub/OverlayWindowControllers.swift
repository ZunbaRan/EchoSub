import AppKit

enum OverlayWindowPresentation {
    static func shouldRaisePinnedWindow(isPinned: Bool, isVisible: Bool) -> Bool {
        isPinned && isVisible
    }
}

extension NSWindowController {
    func hideManagedOverlay() {
        (window as? NSPanel)?.isFloatingPanel = false
        window?.orderOut(nil)
    }

    func showManagedOverlay() {
        (window as? NSPanel)?.isFloatingPanel = true
        window?.orderFrontRegardless()
    }
}

final class FloatingSubtitleWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let state = AppState.shared
    private let settings = AppSettings.shared
    private let table = NSTableView()
    private let modeControl = NSSegmentedControl(labels: ["原文", "中文", "双语"], trackingMode: .selectOne, target: nil, action: nil)
    private let pinButton = EchoStyle.iconButton("pin", help: "Pin 置顶", target: nil, action: nil)
    private let followButton = EchoStyle.iconButton("scope", help: "自动跟随", target: nil, action: nil)
    private let opacitySlider = NSSlider()
    private weak var scrollView: NSScrollView?
    private var autoFollow = true
    private var currentRow = -1
    private var isProgrammaticScroll = false
    private var observers: [NSObjectProtocol] = []
    private let selectionPresenter = SelectionActionPresenter.shared
    private var selectionContext: VocabularySelectionContext?
    private var suppressNextSubtitleSeek = false

    init() {
        let panel = VocabularyFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // With a fully transparent background, the system window shadow is
        // derived from subtitle glyphs and can retain stale glyph silhouettes
        // as the table scrolls. The subtitle cells provide their own highlight.
        panel.hasShadow = false
        panel.minSize = NSSize(width: 320, height: 200)
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.setFrameAutosaveName("EchoSub.floating.v2")
        super.init(window: panel)
        panel.onGlossShortcut = { [weak self] in self?.performFloatingGlossShortcut() ?? false }
        panel.delegate = self
        buildInterface()
        setPinned(settings.floatPinned)
        bindState()
    }

    required init?(coder: NSCoder) { nil }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        applyBackgroundOpacity(settings.floatingBackgroundOpacity)

        pinButton.target = self
        pinButton.action = #selector(togglePin)
        let small = EchoStyle.iconButton("textformat.size.smaller", help: "字号减小", target: self, action: #selector(decreaseFont))
        let large = EchoStyle.iconButton("textformat.size.larger", help: "字号增大", target: self, action: #selector(increaseFont))
        modeControl.selectedSegment = AppSettings.shared.subtitleMode.rawValue
        modeControl.controlSize = .small
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        followButton.target = self
        followButton.action = #selector(toggleFollow)
        let lyrics = EchoStyle.iconButton("text.bubble", help: "切换到桌面歌词", target: self, action: #selector(showLyrics))
        let bar = NSStackView(views: [pinButton, small, large, modeControl, NSView(), followButton, lyrics])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 5
        bar.translatesAutoresizingMaskIntoConstraints = false

        let opacityIcon = NSImageView(image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "背景透明度")!)
        opacityIcon.contentTintColor = EchoStyle.textSecondary
        opacityIcon.translatesAutoresizingMaskIntoConstraints = false
        opacityIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        opacityIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        opacitySlider.minValue = 0
        opacitySlider.maxValue = 1
        opacitySlider.doubleValue = settings.floatingBackgroundOpacity
        opacitySlider.isContinuous = true
        opacitySlider.controlSize = .mini
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.toolTip = "悬浮字幕背景透明度"
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let opacityBar = NSStackView(views: [NSView(), opacityIcon, opacitySlider])
        opacityBar.orientation = .horizontal
        opacityBar.alignment = .centerY
        opacityBar.spacing = 5
        opacityBar.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("floating-subtitle"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 5)
        table.dataSource = self
        table.delegate = self
        let contextMenu = NSMenu(title: "字幕操作")
        contextMenu.delegate = self
        let retryLine = NSMenuItem(title: "补翻 / 重试此句", action: #selector(retryClickedSubtitle), keyEquivalent: "")
        retryLine.target = self
        contextMenu.addItem(retryLine)
        let diagnosticLine = NSMenuItem(title: "查看此句翻译状态…", action: #selector(showClickedSubtitleDiagnostic), keyEquivalent: "")
        diagnosticLine.target = self
        contextMenu.addItem(diagnosticLine)
        table.menu = contextMenu
        let scroll = TransparentSubtitleScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollView = scroll
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            guard let self, !self.isProgrammaticScroll, self.window?.firstResponder === self.table else { return }
            self.autoFollow = false
            self.refreshControls()
        })

        content.addSubview(bar)
        content.addSubview(opacityBar)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            bar.heightAnchor.constraint(equalToConstant: 32),
            opacityBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            opacityBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            opacityBar.topAnchor.constraint(equalTo: bar.bottomAnchor),
            opacityBar.heightAnchor.constraint(equalToConstant: 22),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: opacityBar.bottomAnchor, constant: 2),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        refreshControls()
    }

    private func bindState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .echoTranscriptChanged, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        observers.append(center.addObserver(forName: .echoCurrentVideoChanged, object: nil, queue: .main) { [weak self] _ in
            self?.clearSelectionContext()
            self?.reload()
        })
        observers.append(center.addObserver(forName: .echoPlaybackTimeChanged, object: nil, queue: .main) { [weak self] _ in self?.updateCurrentRow() })
        observers.append(center.addObserver(forName: .echoSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.applySettings() })
        observers.append(center.addObserver(forName: .echoVocabularyChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshVocabularyRows() })
    }

    private func reload() {
        currentRow = -1
        table.reloadData()
        invalidateAllRowHeights()
        updateCurrentRow()
    }

    private func updateCurrentRow(forceScroll: Bool = false) {
        guard let segments = state.currentTranscript?.segments else { return }
        let row = segments.lastIndex(where: { $0.start <= state.playbackTime }) ?? (segments.isEmpty ? -1 : 0)
        guard row != currentRow else {
            if forceScroll, autoFollow, row >= 0 { scrollCurrentRowNearTop(row) }
            return
        }
        let old = currentRow
        currentRow = row
        var rows = IndexSet()
        if old >= 0 { rows.insert(old) }
        if row >= 0 { rows.insert(row) }
        table.noteHeightOfRows(withIndexesChanged: rows)
        table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        if autoFollow, row >= 0 { scrollCurrentRowNearTop(row) }
    }

    private func scrollCurrentRowNearTop(_ row: Int) {
        guard let scrollView else { return }
        table.layoutSubtreeIfNeeded()
        let rowRect = table.rect(ofRow: row)
        guard !rowRect.isEmpty else { return }
        let clipView = scrollView.contentView
        let y = SubtitleAutoFollow.scrollOrigin(
            row: rowRect,
            documentHeight: table.bounds.height,
            viewportHeight: clipView.bounds.height
        )
        isProgrammaticScroll = true
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clipView)
        DispatchQueue.main.async { [weak self] in self?.isProgrammaticScroll = false }
    }

    private func refreshControls() {
        followButton.contentTintColor = autoFollow ? EchoStyle.accent : EchoStyle.textSecondary
        let pinned = window?.level == .screenSaver
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.contentTintColor = pinned ? EchoStyle.accent : EchoStyle.textSecondary
    }

    private func applySettings() {
        opacitySlider.doubleValue = settings.floatingBackgroundOpacity
        applyBackgroundOpacity(settings.floatingBackgroundOpacity)
        setPinned(settings.floatPinned)
        refreshRowHeights()
    }

    private func applyBackgroundOpacity(_ opacity: Double) {
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = EchoStyle.windowBackground.withAlphaComponent(CGFloat(min(1, max(0, opacity)))).cgColor
    }

    private func setPinned(_ pinned: Bool) {
        window?.level = pinned ? .screenSaver : .normal
        (window as? NSPanel)?.hidesOnDeactivate = false
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary]
        if settings.showsOnAllSpaces { behavior.insert(.canJoinAllSpaces) }
        window?.collectionBehavior = behavior
        if OverlayWindowPresentation.shouldRaisePinnedWindow(isPinned: pinned, isVisible: window?.isVisible == true) {
            window?.orderFrontRegardless()
        }
        refreshControls()
    }

    func windowWillClose(_ notification: Notification) {
        (window as? NSPanel)?.isFloatingPanel = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { state.currentTranscript?.segments.count ?? 0 }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let segment = state.currentTranscript?.segments[safeOverlay: row] else { return 58 }
        let mode = SubtitleDisplayMode(rawValue: modeControl.selectedSegment) ?? .bilingual
        let columnWidth = tableColumnWidth(in: tableView)
        return FloatingSubtitleLayout.rowHeight(
            for: segment,
            mode: mode,
            availableWidth: columnWidth - 24,
            fontSize: CGFloat(settings.overlayFontSize),
            glossState: state.glossState(for: segment.id)
        )
    }

    private func tableColumnWidth(in tableView: NSTableView) -> CGFloat {
        tableView.tableColumns.first?.width ?? tableView.bounds.width
    }

    private func invalidateAllRowHeights() {
        guard table.numberOfRows > 0 else { return }
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
    }

    private func refreshRowHeights() {
        guard table.numberOfRows > 0 else { table.reloadData(); return }
        invalidateAllRowHeights()
        table.reloadData()
    }

    private func refreshVocabularyRows() {
        refreshRowHeights()
        updateCurrentRow()
    }

    private func presentFloatingSelection(textView: SelectableEnglishTextView, surface: String, rect: NSRect, segmentID: String) {
        guard let videoID = state.currentVideoID,
              state.currentTranscript?.segments.contains(where: { $0.id == segmentID }) == true,
              VocabularyNormalization.isEligibleSurface(surface) else { return }
        let context = VocabularySelectionContext(videoID: videoID, segmentID: segmentID, surface: surface, textView: textView, rect: rect)
        selectionContext = context
        DispatchQueue.main.async { [weak self] in self?.suppressNextSubtitleSeek = false }
        selectionPresenter.present(
            for: textView,
            surface: surface,
            rect: rect,
            allowsDetail: false,
            onGloss: { [weak self] in _ = self?.performFloatingGloss(context: context) }
        )
    }

    private func performFloatingGlossShortcut() -> Bool {
        guard let context = selectionContext,
              let videoID = state.currentVideoID,
              context.isValid(
                currentVideoID: videoID,
                currentSegmentID: context.segmentID,
                currentSurface: context.surface
              ) else { return false }
        return performFloatingGloss(context: context)
    }

    @discardableResult
    private func performFloatingGloss(textView: SelectableEnglishTextView, surface: String, segmentID: String) -> Bool {
        guard let videoID = state.currentVideoID,
              state.currentTranscript?.segments.contains(where: { $0.id == segmentID }) == true else { return false }
        let context = VocabularySelectionContext(
            videoID: videoID,
            segmentID: segmentID,
            surface: surface,
            textView: textView,
            rect: textView.selectionRectInViewCoordinates
        )
        guard context.isValid(
            currentVideoID: videoID,
            currentSegmentID: segmentID,
            currentSurface: surface
        ) else { return false }
        selectionContext = context
        DispatchQueue.main.async { [weak self] in self?.suppressNextSubtitleSeek = false }
        selectionPresenter.close()
        state.lookupGloss(surface: surface, segmentID: segmentID, videoID: videoID)
        return true
    }

    private func performFloatingGloss(context: VocabularySelectionContext) -> Bool {
        guard let videoID = state.currentVideoID,
              context.isValid(
                currentVideoID: videoID,
                currentSegmentID: context.segmentID,
                currentSurface: context.surface
              ),
              state.currentTranscript?.segments.contains(where: { $0.id == context.segmentID }) == true else { return false }
        selectionPresenter.close()
        state.lookupGloss(surface: context.surface, segmentID: context.segmentID, videoID: videoID)
        return true
    }

    private func seekFloatingRow(_ row: Int) {
        guard let segment = state.currentTranscript?.segments[safeOverlay: row] else { return }
        suppressNextSubtitleSeek = false
        clearSelectionContext()
        NotificationCenter.default.post(name: .echoSeekRequested, object: segment.start)
        state.updatePlaybackTime(segment.start)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let segment = state.currentTranscript?.segments[safeOverlay: row] else { return nil }
        let cell = tableView.makeView(withIdentifier: FloatingCell.identifier, owner: self) as? FloatingCell ?? FloatingCell()
        let mode = SubtitleDisplayMode(rawValue: modeControl.selectedSegment) ?? .bilingual
        cell.onSelectionToolbar = { [weak self] cell, textView, surface, rect in
            guard let segmentID = cell.representedSegmentID else { return }
            self?.presentFloatingSelection(textView: textView, surface: surface, rect: rect, segmentID: segmentID)
        }
        cell.onDoubleClickGloss = { [weak self] cell, textView, surface in
            guard let segmentID = cell.representedSegmentID else { return }
            _ = self?.performFloatingGloss(textView: textView, surface: surface, segmentID: segmentID)
        }
        cell.onPlainEnglishClick = { [weak self] in
            guard let self else { return }
            let selectedRow = self.table.row(for: cell)
            guard selectedRow >= 0 else { return }
            self.seekFloatingRow(selectedRow)
        }
        cell.onTextInteractionBegan = { [weak self] in
            guard let self else { return }
            self.suppressNextSubtitleSeek = true
            self.clearSelectionContext()
        }
        cell.onGlossRemoved = { [weak self] entry in
            guard let self else { return }
            let selectedRow = self.table.row(for: cell)
            guard let segment = self.state.currentTranscript?.segments[safeOverlay: selectedRow] else { return }
            self.state.removeGloss(id: entry.id, from: segment.id)
        }
        cell.onGlossRetry = { [weak self] in
            guard let self else { return }
            let selectedRow = self.table.row(for: cell)
            guard let segment = self.state.currentTranscript?.segments[safeOverlay: selectedRow],
                  let surface = self.state.retryableGlossSurface(for: segment.id) else { return }
            self.state.retryGloss(surface: surface, in: segment.id)
        }
        cell.configure(
            segment,
            mode: mode,
            current: row == currentRow,
            fontSize: CGFloat(settings.overlayFontSize),
            glossState: state.glossState(for: segment.id)
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, let segment = state.currentTranscript?.segments[safeOverlay: table.selectedRow] else { return }
        if suppressNextSubtitleSeek || selectionPresenter.isShown {
            suppressNextSubtitleSeek = false
            return
        }
        _ = segment
        seekFloatingRow(table.selectedRow)
    }

    private func clearSelectionContext() {
        selectionContext = nil
        selectionPresenter.close()
    }

    @objc private func togglePin() {
        let willPin = window?.level != .screenSaver
        setPinned(willPin)
        settings.floatPinned = willPin
    }
    @objc private func toggleFollow() { autoFollow.toggle(); refreshControls(); if autoFollow { updateCurrentRow(forceScroll: true) } }
    @objc private func decreaseFont() { settings.overlayFontSize = max(12, settings.overlayFontSize - 2); refreshRowHeights() }
    @objc private func increaseFont() { settings.overlayFontSize = min(36, settings.overlayFontSize + 2); refreshRowHeights() }
    @objc private func modeChanged() { refreshRowHeights() }
    @objc private func showLyrics() { NotificationCenter.default.post(name: .echoToggleLyricsWindow, object: nil) }
    @objc private func opacityChanged(_ sender: NSSlider) {
        settings.floatingBackgroundOpacity = sender.doubleValue
        applyBackgroundOpacity(sender.doubleValue)
    }
    @objc private func retryClickedSubtitle() {
        let row = table.clickedRow
        guard row >= 0, let segment = state.currentTranscript?.segments[safeOverlay: row] else { return }
        state.translateSegment(id: segment.id)
    }

    @objc private func showClickedSubtitleDiagnostic() {
        let row = table.clickedRow
        guard row >= 0,
              let videoID = state.currentVideoID,
              let segment = state.currentTranscript?.segments[safeOverlay: row] else { return }
        TranslationDiagnosticPresenter.present(segment: segment, videoID: videoID, state: state, parentWindow: window)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === table.menu else { return }
        let row = table.clickedRow
        let segment = state.currentTranscript?.segments[safeOverlay: row]
        for item in menu.items {
            if item.action == #selector(retryClickedSubtitle) {
                item.isEnabled = segment != nil
                item.title = segment.map { $0.hasEffectiveTranslation ? "重新翻译此句" : "补翻此句" } ?? "补翻 / 重试此句"
            } else if item.action == #selector(showClickedSubtitleDiagnostic) {
                item.isEnabled = segment != nil
                if let segment, let videoID = state.currentVideoID,
                   let diagnostic = state.translationDiagnostic(for: segment.id, videoID: videoID) {
                    item.title = diagnostic.menuTitle
                } else {
                    item.title = "查看此句翻译状态…"
                }
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.refreshRowHeights() }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        refreshRowHeights()
        if autoFollow { updateCurrentRow(forceScroll: true) }
    }
}

final class FloatingCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FloatingCell")
    private let original = SelectableEnglishTextView(frame: .zero)
    private let translation = EchoStyle.label("", size: 13, color: EchoStyle.textSecondary, lines: 0)
    private let glosses = GlossInlineView()

    var representedSegmentID: String?
    var onSelectionToolbar: ((FloatingCell, SelectableEnglishTextView, String, NSRect) -> Void)?
    var onDoubleClickGloss: ((FloatingCell, SelectableEnglishTextView, String) -> Void)?
    var onPlainEnglishClick: (() -> Void)?
    var onTextInteractionBegan: (() -> Void)?
    var onGlossRemoved: ((GlossEntry) -> Void)?
    var onGlossRetry: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        let stack = NSStackView(views: [original, translation, glosses])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self, insets: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))
        original.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        translation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        glosses.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        original.setContentCompressionResistancePriority(.required, for: .vertical)
        translation.setContentCompressionResistancePriority(.required, for: .vertical)
        original.alignment = .left
        translation.alignment = .left
        glosses.isHidden = true
        original.onSelectionToolbar = { [weak self] textView, surface, rect in
            guard let self else { return }
            self.onSelectionToolbar?(self, textView, surface, rect)
        }
        original.onDoubleClickGloss = { [weak self] textView, surface in
            guard let self else { return }
            self.onDoubleClickGloss?(self, textView, surface)
        }
        original.onPlainClick = { [weak self] in self?.onPlainEnglishClick?() }
        original.onInteractionBegan = { [weak self] in self?.onTextInteractionBegan?() }
        glosses.onRemove = { [weak self] entry in self?.onGlossRemoved?(entry) }
        glosses.onRetry = { [weak self] in self?.onGlossRetry?() }
    }
    required init?(coder: NSCoder) { nil }

    func configure(
        _ segment: SubtitleSegment,
        mode: SubtitleDisplayMode,
        current: Bool,
        fontSize: CGFloat,
        glossState: GlossLookupState = .idle
    ) {
        representedSegmentID = segment.id
        let settings = AppSettings.shared
        let translated = segment.effectiveTranslation ?? "等待翻译…"
        original.isHidden = mode == .translated
        translation.isHidden = mode == .original
        original.configure(
            text: segment.original,
            font: .systemFont(ofSize: fontSize, weight: current ? .semibold : .regular),
            color: settings.englishSubtitleColor,
            alpha: current ? 1 : 0.72
        )
        EchoStyle.applySubtitleText(
            translation,
            text: translated,
            font: .systemFont(ofSize: max(11, fontSize - 3)),
            color: settings.chineseSubtitleColor,
            alpha: current ? 1 : 0.72
        )
        glosses.fontSize = max(10, fontSize - 6)
        glosses.entries = mode == .original ? [] : segment.glosses
        glosses.state = mode == .original ? .idle : glossState
        glosses.isHidden = mode == .original || (segment.glosses.isEmpty && glossState == .idle)
        layer?.backgroundColor = current ? EchoStyle.highlight.cgColor : NSColor.clear.cgColor
    }
}

/// AppKit minimizes invalidation while scrolling. That optimization leaves old
/// glyph pixels in a fully transparent window because no opaque background is
/// painted over them, so invalidate the complete transparent surface whenever
/// its clip view moves.
final class TransparentSubtitleScrollView: NSScrollView {
    private(set) var transparentRedrawCount = 0
    private(set) var lastInvalidatedDocumentRect = NSRect.zero

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        invalidateTransparentSurface()
    }

    func invalidateTransparentSurface() {
        transparentRedrawCount += 1
        lastInvalidatedDocumentRect = documentVisibleRect
        contentView.needsDisplay = true
        documentView?.needsDisplay = true
        documentView?.setNeedsDisplay(documentVisibleRect)
        superview?.needsDisplay = true
        window?.contentView?.needsDisplay = true
        displayIfNeeded()
    }
}

final class DesktopLyricsWindowController: NSWindowController, NSWindowDelegate {
    private let state = AppState.shared
    private let settings = AppSettings.shared
    private let plate = NSVisualEffectView()
    private let original = EchoStyle.label("等待视频播放…", size: 27, weight: .bold, lines: 0)
    private let translation = EchoStyle.label("", size: 17, color: EchoStyle.textSecondary, lines: 0)
    private let controls = NSStackView()
    private let opacitySlider = NSSlider()
    private var observers: [NSObjectProtocol] = []
    private(set) var isLocked = false
    private var isAutoResizing = false
    private var previousWidth: CGFloat = 0

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 158),
            styleMask: [.titled, .resizable, .utilityWindow, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .screenSaver
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 320, height: 100)
        panel.maxSize = NSSize(width: NSScreen.main.map { $0.visibleFrame.width * 0.82 } ?? 1_200, height: 500)
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.setFrameAutosaveName("EchoSub.lyrics.v2")
        super.init(window: panel)
        panel.delegate = self
        buildInterface()
        bindState()
        applySettings()
        updateText()
        previousWidth = panel.frame.width
    }

    required init?(coder: NSCoder) { nil }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        let englishSmaller = compactTextButton("A−", help: "英文字号减小", action: #selector(decreaseEnglishFont))
        let englishLarger = compactTextButton("A+", help: "英文字号增大", action: #selector(increaseEnglishFont))
        let chineseSmaller = compactTextButton("中−", help: "中文字幕号减小", action: #selector(decreaseChineseFont))
        let chineseLarger = compactTextButton("中+", help: "中文字幕号增大", action: #selector(increaseChineseFont))
        let opacityIcon = NSImageView(image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "背景透明度")!)
        opacityIcon.contentTintColor = EchoStyle.textSecondary
        opacityIcon.translatesAutoresizingMaskIntoConstraints = false
        opacityIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        opacityIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        opacitySlider.minValue = 0
        opacitySlider.maxValue = 1
        opacitySlider.doubleValue = settings.desktopLyricsBackgroundOpacity
        opacitySlider.isContinuous = true
        opacitySlider.controlSize = .mini
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.toolTip = "背景透明度（最左为完全透明）"
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let lock = EchoStyle.iconButton("lock", help: "锁定并穿透鼠标", target: self, action: #selector(toggleLock))
        let close = EchoStyle.iconButton("xmark", help: "关闭", target: self, action: #selector(closeLyrics))
        controls.setViews([englishSmaller, englishLarger, chineseSmaller, chineseLarger, opacityIcon, opacitySlider, lock, close], in: .leading)
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 4
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.86).cgColor
        controls.layer?.cornerRadius = 8
        controls.edgeInsets = NSEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)
        controls.translatesAutoresizingMaskIntoConstraints = false

        plate.material = .hudWindow
        plate.blendingMode = .behindWindow
        plate.state = .active
        plate.wantsLayer = true
        plate.layer?.cornerRadius = 13
        plate.layer?.masksToBounds = true
        plate.layer?.borderWidth = 1
        plate.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        plate.translatesAutoresizingMaskIntoConstraints = false
        original.alignment = .left
        translation.alignment = .left
        let textStack = NSStackView(views: [original, translation])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        textStack.translatesAutoresizingMaskIntoConstraints = false
        original.setContentCompressionResistancePriority(.required, for: .vertical)
        translation.setContentCompressionResistancePriority(.required, for: .vertical)

        content.addSubview(plate)
        content.addSubview(textStack)
        content.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            plate.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            plate.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            plate.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 7),
            plate.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            textStack.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 28),
            textStack.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -28),
            textStack.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
            original.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            translation.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])
    }

    private func compactTextButton(_ title: String, help: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = EchoStyle.textSecondary
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func bindState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .echoPlaybackTimeChanged, object: nil, queue: .main) { [weak self] _ in self?.updateText() })
        observers.append(center.addObserver(forName: .echoTranscriptChanged, object: nil, queue: .main) { [weak self] _ in self?.updateText() })
        observers.append(center.addObserver(forName: .echoCurrentVideoChanged, object: nil, queue: .main) { [weak self] _ in self?.updateText() })
        observers.append(center.addObserver(forName: .echoSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.applySettings() })
    }

    private func updateText() {
        guard let segment = state.currentSegment else {
            applyStyledText(originalText: "等待视频播放…", translatedText: "")
            resizeHeightForContent()
            return
        }
        applyStyledText(originalText: segment.original, translatedText: segment.effectiveTranslation ?? "")
        resizeHeightForContent()
    }

    private func applySettings() {
        applyStyledText(originalText: original.stringValue, translatedText: translation.stringValue)
        opacitySlider.doubleValue = settings.desktopLyricsBackgroundOpacity
        updateBackgroundOpacity(settings.desktopLyricsBackgroundOpacity)
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary]
        if settings.showsOnAllSpaces { behavior.insert(.canJoinAllSpaces) }
        window?.collectionBehavior = behavior
        resizeHeightForContent()
    }

    private func applyStyledText(originalText: String, translatedText: String) {
        EchoStyle.applySubtitleText(
            original,
            text: originalText,
            font: .systemFont(ofSize: CGFloat(settings.desktopEnglishFontSize), weight: .bold),
            color: settings.englishSubtitleColor
        )
        EchoStyle.applySubtitleText(
            translation,
            text: translatedText,
            font: .systemFont(ofSize: CGFloat(settings.desktopChineseFontSize), weight: .regular),
            color: settings.chineseSubtitleColor
        )
    }

    private func updateBackgroundOpacity(_ opacity: Double) {
        let value = CGFloat(min(1, max(0, opacity)))
        plate.isHidden = value <= 0.001
        plate.alphaValue = value
        plate.layer?.borderColor = isLocked ? NSColor.clear.cgColor : NSColor.white.withAlphaComponent(0.28 * value).cgColor
    }

    private func resizeHeightForContent() {
        guard window != nil, !isAutoResizing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !self.isAutoResizing else { return }
            let availableWidth = max(240, window.frame.width - 72)
            self.original.preferredMaxLayoutWidth = availableWidth
            self.translation.preferredMaxLayoutWidth = availableWidth
            func textHeight(_ label: NSTextField) -> CGFloat {
                let attributed = NSAttributedString(string: label.stringValue, attributes: [.font: label.font ?? .systemFont(ofSize: 17)])
                return ceil(attributed.boundingRect(
                    with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height)
            }
            let originalHeight = textHeight(self.original)
            let translationHeight = self.translation.stringValue.isEmpty ? 0 : textHeight(self.translation)
            let spacing: CGFloat = translationHeight > 0 ? 8 : 0
            let desired = min(500, max(100, 43 + 32 + originalHeight + translationHeight + spacing))
            guard abs(desired - window.frame.height) > 1 else { return }
            self.isAutoResizing = true
            let frame = window.frame
            window.setFrame(NSRect(x: frame.minX, y: frame.maxY - desired, width: frame.width, height: desired), display: true)
            self.isAutoResizing = false
        }
    }

    func toggleLockedState() {
        isLocked.toggle()
        controls.isHidden = isLocked
        window?.ignoresMouseEvents = isLocked
        updateBackgroundOpacity(settings.desktopLyricsBackgroundOpacity)
    }

    @objc private func toggleLock() { toggleLockedState() }
    @objc private func decreaseEnglishFont() { settings.desktopEnglishFontSize = settings.desktopEnglishFontSize - 2 }
    @objc private func increaseEnglishFont() { settings.desktopEnglishFontSize = settings.desktopEnglishFontSize + 2 }
    @objc private func decreaseChineseFont() { settings.desktopChineseFontSize = settings.desktopChineseFontSize - 2 }
    @objc private func increaseChineseFont() { settings.desktopChineseFontSize = settings.desktopChineseFontSize + 2 }
    @objc private func opacityChanged(_ sender: NSSlider) {
        settings.desktopLyricsBackgroundOpacity = sender.doubleValue
        updateBackgroundOpacity(sender.doubleValue)
    }
    @objc private func closeLyrics() { hideManagedOverlay() }

    func windowWillClose(_ notification: Notification) {
        (window as? NSPanel)?.isFloatingPanel = false
    }

    func windowDidResize(_ notification: Notification) {
        guard let width = window?.frame.width, abs(width - previousWidth) > 1 else { return }
        previousWidth = width
        resizeHeightForContent()
    }
}

private extension Array {
    subscript(safeOverlay index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

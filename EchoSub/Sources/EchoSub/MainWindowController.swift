import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate, YouTubePlayerViewDelegate {
    private let state = AppState.shared
    private let settings = AppSettings.shared

    private let linkField = NSTextField()
    private let playlistTable = NSTableView()
    private let subtitleTable = NSTableView()
    private let playerView = YouTubePlayerView()
    private let playerContainer = NSView()
    private let stateOverlay = FlippedView()
    private let titleLabel = EchoStyle.label("", size: 13, weight: .semibold)
    private let channelLabel = EchoStyle.label("", size: 11, color: EchoStyle.textTertiary)
    private let modeControl = NSSegmentedControl(labels: ["原文", "中文", "双语"], trackingMode: .selectOne, target: nil, action: nil)
    private let followButton = EchoStyle.iconButton("scope", help: "自动跟随", target: nil, action: nil)
    private let backgroundCardButton = EchoStyle.button("背景卡", symbol: "sparkles", target: nil, action: nil)
    private let subtitleFooter = EchoStyle.label("", size: 11, color: EchoStyle.textTertiary)
    private let playlistContainer = NSView()
    private let subtitleContainer = NSView()
    private let backgroundCardPanel = BackgroundCardPanel()
    private let playlistToggleButton = EchoStyle.iconButton("sidebar.left", help: "折叠播放列表", target: nil, action: nil)
    private let subtitleToggleButton = EchoStyle.iconButton("sidebar.right", help: "折叠字幕", target: nil, action: nil)
    private let nativeFullscreenButton = EchoStyle.iconButton("arrow.up.left.and.arrow.down.right", help: "播放器窗口全屏", target: nil, action: nil)
    private let playlistCountLabel = EchoStyle.label("0", size: 11, color: EchoStyle.textTertiary)
    private let playButton = EchoStyle.iconButton("play.fill", help: "播放 / 暂停", target: nil, action: nil)
    private var splitView: NSSplitView!
    private var currentSubtitleRow = -1
    private var autoFollow = true
    private var isPlaying = false
    private var playlistCollapsed = false
    private var subtitleCollapsed = false
    private var lastPlaylistWidth: CGFloat = 236
    private var lastSubtitleWidth: CGFloat = 348
    private var isApplyingSplitLayout = false
    private var playerWindowOverlay: PlayerWindowOverlay?
    private var observers: [NSObjectProtocol] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "EchoSub"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = EchoStyle.windowBackground
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("EchoSub.main")
        super.init(window: window)
        window.delegate = self
        buildInterface()
        bindState()
        refreshAll()
    }

    required init?(coder: NSCoder) { nil }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = EchoStyle.windowBackground.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        root.pinEdges(to: content)

        root.addArrangedSubview(makeTopBar())
        let separator = SeparatorView()
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        root.addArrangedSubview(separator)

        splitView = EchoSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(splitView)

        let playlist = makePlaylistPanel()
        let center = makeCenterPanel()
        let subtitles = makeSubtitlePanel()
        splitView.addArrangedSubview(playlist)
        splitView.addArrangedSubview(center)
        splitView.addArrangedSubview(subtitles)
        let centerMinimum = center.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        centerMinimum.priority = .defaultHigh
        centerMinimum.isActive = true
        DispatchQueue.main.async { [weak self] in self?.applyInitialSplitLayout() }
    }

    private func makeTopBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 52).isActive = true

        linkField.placeholderString = "粘贴 YouTube 链接开始…"
        linkField.font = .systemFont(ofSize: 13)
        linkField.controlSize = .regular
        linkField.isBordered = false
        linkField.drawsBackground = false
        linkField.focusRingType = .none
        linkField.translatesAutoresizingMaskIntoConstraints = false
        linkField.target = self
        linkField.action = #selector(addVideo)

        let input = NSView()
        input.wantsLayer = true
        input.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.72).cgColor
        input.layer?.cornerRadius = 9
        input.layer?.borderWidth = 1
        input.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        input.translatesAutoresizingMaskIntoConstraints = false
        let linkIcon = NSImageView(image: NSImage(systemSymbolName: "link", accessibilityDescription: nil)!)
        linkIcon.contentTintColor = EchoStyle.textSecondary
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        let paste = EchoStyle.iconButton("clipboard", help: "从剪贴板粘贴", target: self, action: #selector(pasteYouTubeURL))
        paste.widthAnchor.constraint(equalToConstant: 32).isActive = true
        input.addSubview(linkIcon)
        input.addSubview(linkField)
        input.addSubview(paste)
        NSLayoutConstraint.activate([
            input.heightAnchor.constraint(equalToConstant: 28),
            linkIcon.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 12),
            linkIcon.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            linkIcon.widthAnchor.constraint(equalToConstant: 15),
            linkIcon.heightAnchor.constraint(equalToConstant: 15),
            linkField.leadingAnchor.constraint(equalTo: linkIcon.trailingAnchor, constant: 9),
            linkField.trailingAnchor.constraint(equalTo: paste.leadingAnchor, constant: -4),
            linkField.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            paste.trailingAnchor.constraint(equalTo: input.trailingAnchor, constant: -4),
            paste.centerYAnchor.constraint(equalTo: input.centerYAnchor),
        ])

        let add = EchoStyle.button("添加", symbol: "plus", target: self, action: #selector(addVideo), primary: true)
        add.controlSize = .regular
        add.bezelColor = EchoStyle.accent
        add.font = .systemFont(ofSize: 13, weight: .semibold)
        add.widthAnchor.constraint(equalToConstant: 76).isActive = true
        add.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let settingsButton = EchoStyle.iconButton("gearshape", help: "设置", target: self, action: #selector(openSettings))
        let stack = NSStackView(views: [input, add, settingsButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: bar.leadingAnchor, constant: 160),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 8),
            input.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            input.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
        let preferredInputWidth = input.widthAnchor.constraint(equalToConstant: 320)
        preferredInputWidth.priority = .defaultHigh
        preferredInputWidth.isActive = true
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return bar
    }

    private func makePlaylistPanel() -> NSView {
        playlistContainer.wantsLayer = true
        playlistContainer.layer?.backgroundColor = EchoStyle.sidebarBackground.cgColor
        playlistContainer.translatesAutoresizingMaskIntoConstraints = false

        let headerTitle = EchoStyle.label("播放列表", size: 12, weight: .semibold, color: EchoStyle.textSecondary)
        let header = NSStackView(views: [headerTitle, NSView(), playlistCountLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("playlist"))
        column.resizingMask = .autoresizingMask
        playlistTable.addTableColumn(column)
        playlistTable.headerView = nil
        playlistTable.rowHeight = 64
        playlistTable.backgroundColor = .clear
        playlistTable.selectionHighlightStyle = .none
        playlistTable.intercellSpacing = NSSize(width: 0, height: 4)
        playlistTable.dataSource = self
        playlistTable.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = playlistTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        playlistContainer.addSubview(header)
        playlistContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: playlistContainer.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: playlistContainer.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: playlistContainer.topAnchor, constant: 13),
            header.heightAnchor.constraint(equalToConstant: 24),
            scroll.leadingAnchor.constraint(equalTo: playlistContainer.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: playlistContainer.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 5),
            scroll.bottomAnchor.constraint(equalTo: playlistContainer.bottomAnchor, constant: -8),
        ])
        return playlistContainer
    }

    private func makeCenterPanel() -> NSView {
        let center = NSView()
        center.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.wantsLayer = true
        playerContainer.layer?.backgroundColor = NSColor.black.cgColor
        playerContainer.layer?.cornerRadius = 8
        playerContainer.layer?.masksToBounds = true
        playerView.delegate = self
        playerContainer.addSubview(playerView)
        playerView.pinEdges(to: playerContainer)

        stateOverlay.wantsLayer = true
        stateOverlay.layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 1).cgColor
        stateOverlay.isHidden = true
        stateOverlay.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(stateOverlay)
        stateOverlay.pinEdges(to: playerContainer)

        let videoBar = makeVideoBar()
        let footer = NSStackView(views: [playlistToggleButton, EchoStyle.label("左右分栏均可折叠、拖动并记忆", size: 11, color: EchoStyle.textTertiary), NSView(), subtitleToggleButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        playlistToggleButton.target = self
        playlistToggleButton.action = #selector(togglePlaylist)
        subtitleToggleButton.target = self
        subtitleToggleButton.action = #selector(toggleSubtitles)

        center.addSubview(playerContainer)
        center.addSubview(videoBar)
        center.addSubview(footer)
        let aspect = playerContainer.heightAnchor.constraint(equalTo: playerContainer.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.priority = .defaultHigh
        NSLayoutConstraint.activate([
            playerContainer.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 16),
            playerContainer.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -16),
            playerContainer.topAnchor.constraint(equalTo: center.topAnchor, constant: 64),
            aspect,
            playerContainer.heightAnchor.constraint(lessThanOrEqualTo: center.heightAnchor, multiplier: 0.68),
            videoBar.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 16),
            videoBar.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -16),
            videoBar.topAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            videoBar.heightAnchor.constraint(equalToConstant: 58),
            footer.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: center.bottomAnchor, constant: -10),
            footer.heightAnchor.constraint(equalToConstant: 30),
        ])
        return center
    }

    private func makeVideoBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let titles = NSStackView(views: [titleLabel, channelLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let back = EchoStyle.iconButton("gobackward.5", help: "后退 5 秒", target: self, action: #selector(backFive))
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        let forward = EchoStyle.iconButton("goforward.5", help: "前进 5 秒", target: self, action: #selector(forwardFive))
        let floatButton = EchoStyle.button("悬浮字幕", symbol: "rectangle.on.rectangle", target: self, action: #selector(toggleFloating))
        let lyricButton = EchoStyle.button("桌面歌词", symbol: "text.bubble", target: self, action: #selector(toggleLyrics))
        nativeFullscreenButton.target = self
        nativeFullscreenButton.action = #selector(togglePlayerFullscreen)
        let external = EchoStyle.iconButton("arrow.up.right.square", help: "在 YouTube 打开", target: self, action: #selector(openYouTube))
        let stack = NSStackView(views: [titles, NSView(), back, playButton, forward, floatButton, lyricButton, nativeFullscreenButton, external])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        stack.pinEdges(to: bar, insets: NSEdgeInsets(top: 8, left: 0, bottom: 6, right: 0))
        titles.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return bar
    }

    private func makeSubtitlePanel() -> NSView {
        subtitleContainer.wantsLayer = true
        subtitleContainer.layer?.backgroundColor = EchoStyle.panelBackground.cgColor
        subtitleContainer.translatesAutoresizingMaskIntoConstraints = false

        modeControl.selectedSegment = settings.subtitleMode.rawValue
        modeControl.controlSize = .small
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        followButton.target = self
        followButton.action = #selector(toggleFollow)
        autoFollow = settings.autoFollow

        let title = EchoStyle.label("字幕", size: 13, weight: .semibold)
        backgroundCardButton.target = self
        backgroundCardButton.action = #selector(showBackgroundCard)
        backgroundCardButton.isBordered = false
        backgroundCardButton.contentTintColor = EchoStyle.textSecondary
        let more = EchoStyle.iconButton("ellipsis", help: "翻译选项", target: self, action: #selector(showTranslationMenu(_:)))
        let header = NSStackView(views: [title, modeControl, NSView(), backgroundCardButton, followButton, more])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("subtitle"))
        column.resizingMask = .autoresizingMask
        subtitleTable.addTableColumn(column)
        subtitleTable.headerView = nil
        subtitleTable.backgroundColor = .clear
        subtitleTable.selectionHighlightStyle = .none
        subtitleTable.intercellSpacing = NSSize(width: 0, height: 1)
        subtitleTable.dataSource = self
        subtitleTable.delegate = self
        let contextMenu = NSMenu(title: "字幕操作")
        contextMenu.delegate = self
        let retryLine = NSMenuItem(title: "补翻 / 重试此句", action: #selector(retryClickedSubtitle), keyEquivalent: "")
        retryLine.target = self
        contextMenu.addItem(retryLine)
        subtitleTable.menu = contextMenu
        let scroll = NSScrollView()
        scroll.documentView = subtitleTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            guard let self, self.window?.firstResponder === self.subtitleTable else { return }
            self.autoFollow = false
            self.refreshFollowButton()
        })

        let separator = SeparatorView()
        subtitleContainer.addSubview(header)
        subtitleContainer.addSubview(separator)
        subtitleContainer.addSubview(scroll)
        subtitleContainer.addSubview(subtitleFooter)
        backgroundCardPanel.isHidden = true
        backgroundCardPanel.onClose = { [weak self] in self?.hideBackgroundCard() }
        backgroundCardPanel.onGenerate = { [weak self] in self?.state.regenerateBackgroundCard() }
        backgroundCardPanel.onRegenerate = { [weak self] _ in self?.confirmRegenerateBackgroundCard() }
        backgroundCardPanel.onSave = { [weak self] card in self?.state.saveBackgroundCard(card) }
        backgroundCardPanel.onSeek = { [weak self] seconds in
            self?.playerView.seek(to: seconds)
            self?.state.updatePlaybackTime(seconds)
        }
        subtitleContainer.addSubview(backgroundCardPanel)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: subtitleContainer.topAnchor, constant: 9),
            header.heightAnchor.constraint(equalToConstant: 34),
            separator.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            separator.heightAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: subtitleFooter.topAnchor, constant: -4),
            subtitleFooter.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor, constant: 14),
            subtitleFooter.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor, constant: -14),
            subtitleFooter.bottomAnchor.constraint(equalTo: subtitleContainer.bottomAnchor, constant: -8),
            subtitleFooter.heightAnchor.constraint(equalToConstant: 20),
        ])
        backgroundCardPanel.pinEdges(to: subtitleContainer)
        refreshFollowButton()
        return subtitleContainer
    }

    private func bindState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .echoLibraryChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshLibrary() })
        observers.append(center.addObserver(forName: .echoCurrentVideoChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshCurrentVideo() })
        observers.append(center.addObserver(forName: .echoTranscriptChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshTranscript() })
        observers.append(center.addObserver(forName: .echoBackgroundCardChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshBackgroundCard() })
        observers.append(center.addObserver(forName: .echoPlaybackTimeChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshPlaybackPosition() })
        observers.append(center.addObserver(forName: .echoSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshSubtitleAppearance() })
        observers.append(center.addObserver(forName: .echoSeekRequested, object: nil, queue: .main) { [weak self] note in
            guard let seconds = note.object as? Double else { return }
            self?.playerView.seek(to: seconds)
        })
    }

    private func refreshAll() {
        refreshLibrary()
        refreshCurrentVideo()
        refreshTranscript()
        refreshBackgroundCard()
    }

    private func refreshLibrary() {
        playlistTable.reloadData()
        playlistCountLabel.stringValue = "\(state.library.videos.count)"
    }

    private func refreshCurrentVideo() {
        guard let video = state.currentVideo else {
            titleLabel.stringValue = "粘贴一个 YouTube 链接开始"
            channelLabel.stringValue = "无需登录，公开视频即可生成双语字幕"
            playerView.isHidden = true
            nativeFullscreenButton.isHidden = true
            stateOverlay.isHidden = false
            showEmptyState()
            refreshBackgroundCard()
            return
        }
        titleLabel.stringValue = video.title
        channelLabel.stringValue = video.channel + (video.duration.map { " · \(formattedTime($0))" } ?? "")
        playerView.isHidden = false
        nativeFullscreenButton.isHidden = false
        stateOverlay.isHidden = true
        if playerView.videoID != video.id {
            playerView.load(videoID: video.id, start: video.progress)
        }
        refreshLibrary()
        refreshTranscript()
        refreshBackgroundCard()
    }

    private func refreshTranscript() {
        subtitleTable.reloadData()
        guard let video = state.currentVideo else { subtitleFooter.stringValue = ""; return }
        if state.isCurrentBackgroundCardGenerating {
            subtitleFooter.stringValue = "正在理解完整视频内容…"
            refreshPlaybackPosition()
            return
        }
        switch video.status {
        case .loading:
            subtitleFooter.stringValue = "正在获取字幕…"
        case .translating:
            let total = state.currentTranscript?.segments.count ?? 0
            let done = state.currentTranscript?.segments.filter { $0.translation?.isEmpty == false }.count ?? 0
            subtitleFooter.stringValue = "正在翻译 \(done) / \(total) 句"
        case .failed:
            subtitleFooter.stringValue = state.lastErrorMessage ?? "字幕或翻译失败，可点击右上角重试。"
        case .noSubtitles:
            subtitleFooter.stringValue = "这个视频没有可用字幕。"
        case .ready:
            let source = state.currentTranscript?.isGenerated == true ? "YouTube 自动字幕" : "YouTube 人工字幕"
            let provider = state.currentTranscript?.provider?.label ?? "YouTube"
            let missing = state.missingTranslationCount
            subtitleFooter.stringValue = missing > 0 ? "\(provider) · \(source) · 待补全 \(missing) 句" : "\(provider) · \(source)"
        case .idle:
            subtitleFooter.stringValue = "等待获取字幕"
        }

        if state.currentVideo != nil {
            playerView.isHidden = false
            stateOverlay.isHidden = true
        }
        refreshPlaybackPosition()
    }

    private func refreshBackgroundCard() {
        let hasTranscript = state.currentTranscript?.segments.isEmpty == false
        backgroundCardButton.isEnabled = hasTranscript
        if state.isCurrentBackgroundCardGenerating {
            backgroundCardButton.title = "理解中"
            backgroundCardButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            backgroundCardButton.contentTintColor = EchoStyle.accent
        } else if state.currentBackgroundCard != nil {
            backgroundCardButton.title = "背景卡"
            backgroundCardButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            backgroundCardButton.contentTintColor = EchoStyle.accent
        } else if state.currentBackgroundCardError != nil {
            backgroundCardButton.title = "背景卡"
            backgroundCardButton.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            backgroundCardButton.contentTintColor = NSColor.systemOrange
        } else {
            backgroundCardButton.title = "背景卡"
            backgroundCardButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            backgroundCardButton.contentTintColor = EchoStyle.textSecondary
        }
        if !backgroundCardPanel.isHidden {
            backgroundCardPanel.render(
                video: state.currentVideo,
                card: state.currentBackgroundCard,
                generating: state.isCurrentBackgroundCardGenerating,
                error: state.currentBackgroundCardError
            )
        }
        refreshTranscript()
    }

    private func refreshPlaybackPosition() {
        let row = indexOfCurrentSubtitle()
        guard row != currentSubtitleRow else { return }
        let previous = currentSubtitleRow
        currentSubtitleRow = row
        var indexes = IndexSet()
        if previous >= 0 { indexes.insert(previous) }
        if row >= 0 { indexes.insert(row) }
        subtitleTable.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: 0))
        if autoFollow, row >= 0 { subtitleTable.scrollRowToVisible(row) }
    }

    private func indexOfCurrentSubtitle() -> Int {
        guard let segments = state.currentTranscript?.segments else { return -1 }
        return segments.lastIndex(where: { $0.start <= state.playbackTime }) ?? (segments.isEmpty ? -1 : 0)
    }

    private func showEmptyState() {
        stateOverlay.removeAllSubviews()
        let icon = NSImageView(image: NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: nil)!)
        icon.contentTintColor = EchoStyle.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 42).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let title = EchoStyle.label("EchoSub", size: 22, weight: .bold)
        let detail = EchoStyle.label("粘贴一个 YouTube 链接开始。", size: 13, color: EchoStyle.textSecondary)
        let stack = NSStackView(views: [icon, title, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stateOverlay.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: stateOverlay.centerXAnchor), stack.centerYAnchor.constraint(equalTo: stateOverlay.centerYAnchor)])
    }

    private func showTranscriptState(_ status: TranscriptStatus) {
        stateOverlay.removeAllSubviews()
        let isNoSub = status == .noSubtitles
        let icon = NSImageView(image: NSImage(systemSymbolName: isNoSub ? "captions.bubble" : "exclamationmark.triangle", accessibilityDescription: nil)!)
        icon.contentTintColor = EchoStyle.textSecondary
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = EchoStyle.label(isNoSub ? "这个视频没有可用字幕" : "字幕获取失败", size: 15, weight: .semibold)
        let detail = EchoStyle.label(state.lastErrorMessage ?? "暂时无法生成双语字幕。", size: 12, color: EchoStyle.textSecondary, lines: 3)
        detail.alignment = .center
        let retry = EchoStyle.button("重新检测", symbol: "arrow.clockwise", target: self, action: #selector(retryTranscript), primary: true)
        let open = EchoStyle.button("在 YouTube 打开", symbol: "arrow.up.right.square", target: self, action: #selector(openYouTube))
        let actions = NSStackView(views: [retry, open])
        actions.orientation = .horizontal
        actions.spacing = 8
        let stack = NSStackView(views: [icon, title, detail, actions])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stateOverlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: stateOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: stateOverlay.centerYAnchor),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
    }

    private func refreshFollowButton() {
        followButton.contentTintColor = autoFollow ? EchoStyle.accent : EchoStyle.textSecondary
        followButton.toolTip = autoFollow ? "自动跟随中" : "恢复自动跟随"
    }

    private func refreshSubtitleAppearance() {
        if subtitleTable.numberOfRows > 0 {
            subtitleTable.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<subtitleTable.numberOfRows))
        }
        subtitleTable.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === playlistTable ? state.library.videos.count : (state.currentTranscript?.segments.count ?? 0)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === playlistTable { return 64 }
        guard let segment = state.currentTranscript?.segments[safe: row] else { return 64 }
        let mode = SubtitleDisplayMode(rawValue: modeControl.selectedSegment) ?? .bilingual
        let width = max(120, subtitleTable.bounds.width - 70)
        func textHeight(_ text: String, font: NSFont) -> CGFloat {
            ceil(NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
        }
        var height: CGFloat = 18
        if mode != .translated { height += textHeight(segment.original, font: .systemFont(ofSize: 13, weight: .medium)) }
        if mode == .bilingual { height += 5 }
        if mode != .original { height += textHeight(segment.translation ?? "等待翻译…", font: .systemFont(ofSize: 12)) }
        return max(54, height)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === playlistTable {
            guard let video = state.library.videos[safe: row] else { return nil }
            let view = tableView.makeView(withIdentifier: PlaylistCell.identifier, owner: self) as? PlaylistCell ?? PlaylistCell()
            view.configure(video, current: video.id == state.currentVideoID)
            return view
        }
        guard let segment = state.currentTranscript?.segments[safe: row] else { return nil }
        let view = tableView.makeView(withIdentifier: SubtitleCell.identifier, owner: self) as? SubtitleCell ?? SubtitleCell()
        let mode = SubtitleDisplayMode(rawValue: modeControl.selectedSegment) ?? .bilingual
        view.configure(segment, mode: mode, current: row == currentSubtitleRow)
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table.selectedRow >= 0 else { return }
        if table === playlistTable, let video = state.library.videos[safe: table.selectedRow] {
            state.selectVideo(video.id)
        } else if table === subtitleTable, let segment = state.currentTranscript?.segments[safe: table.selectedRow] {
            playerView.seek(to: segment.start)
            state.updatePlaybackTime(segment.start)
        }
    }

    @objc private func addVideo() {
        switch state.addVideo(from: linkField.stringValue) {
        case .success:
            linkField.stringValue = ""
            window?.makeFirstResponder(nil)
        case .failure(let error):
            presentInlineAlert(error.localizedDescription)
        }
    }

    @objc private func pasteYouTubeURL() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        linkField.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        window?.makeFirstResponder(linkField)
    }

    private func presentInlineAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "无法添加视频"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }

    @objc private func modeChanged() {
        settings.subtitleMode = SubtitleDisplayMode(rawValue: modeControl.selectedSegment) ?? .bilingual
        if subtitleTable.numberOfRows > 0 {
            subtitleTable.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<subtitleTable.numberOfRows))
        }
        subtitleTable.reloadData()
    }
    @objc private func toggleFollow() { autoFollow.toggle(); refreshFollowButton(); if autoFollow { refreshPlaybackPosition() } }
    @objc private func togglePlaylist() {
        setPlaylistCollapsed(!playlistCollapsed)
    }

    private func setPlaylistCollapsed(_ collapsed: Bool) {
        guard let splitView, collapsed != playlistCollapsed else { return }
        if !collapsed {
            playlistCollapsed = false
            isApplyingSplitLayout = true
            playlistContainer.isHidden = false
            splitView.adjustSubviews()
            splitView.setPosition(max(180, lastPlaylistWidth), ofDividerAt: 0)
            if !subtitleCollapsed {
                let availableRight = max(280, splitView.bounds.width - max(180, lastPlaylistWidth) - 360 - splitView.dividerThickness * 2)
                let right = min(lastSubtitleWidth, availableRight)
                splitView.setPosition(splitView.bounds.width - right - splitView.dividerThickness, ofDividerAt: 1)
            }
            isApplyingSplitLayout = false
        } else {
            lastPlaylistWidth = max(180, playlistContainer.frame.width)
            playlistCollapsed = true
            isApplyingSplitLayout = true
            splitView.setPosition(0, ofDividerAt: 0)
            playlistContainer.isHidden = true
            splitView.adjustSubviews()
            isApplyingSplitLayout = false
        }
        playlistToggleButton.contentTintColor = playlistCollapsed ? EchoStyle.textSecondary : EchoStyle.accent
        playlistToggleButton.toolTip = playlistCollapsed ? "展开播放列表" : "折叠播放列表"
    }

    @objc private func toggleSubtitles() { setSubtitlesCollapsed(!subtitleCollapsed) }

    private func setSubtitlesCollapsed(_ collapsed: Bool) {
        guard let splitView, collapsed != subtitleCollapsed else { return }
        isApplyingSplitLayout = true
        if collapsed {
            lastSubtitleWidth = max(280, subtitleContainer.frame.width)
            subtitleCollapsed = true
            splitView.setPosition(splitView.bounds.width, ofDividerAt: 1)
            subtitleContainer.isHidden = true
            splitView.adjustSubviews()
        } else {
            subtitleCollapsed = false
            subtitleContainer.isHidden = false
            splitView.adjustSubviews()
            let left = playlistCollapsed ? 0 : max(180, playlistContainer.frame.width)
            let available = max(280, splitView.bounds.width - left - 360 - splitView.dividerThickness * 2)
            let width = min(lastSubtitleWidth, available)
            splitView.setPosition(splitView.bounds.width - width - splitView.dividerThickness, ofDividerAt: 1)
        }
        isApplyingSplitLayout = false
        subtitleToggleButton.contentTintColor = subtitleCollapsed ? EchoStyle.textSecondary : EchoStyle.accent
        subtitleToggleButton.toolTip = subtitleCollapsed ? "展开字幕" : "折叠字幕"
    }
    @objc private func togglePlayback() { playerView.togglePlayback() }
    @objc private func backFive() { playerView.skip(by: -5) }
    @objc private func forwardFive() { playerView.skip(by: 5) }
    @objc private func retryTranscript() { state.retryTranscript() }
    @objc private func showBackgroundCard() {
        guard state.currentTranscript != nil else { return }
        if subtitleCollapsed { setSubtitlesCollapsed(false) }
        backgroundCardPanel.alphaValue = 0
        backgroundCardPanel.isHidden = false
        backgroundCardPanel.render(
            video: state.currentVideo,
            card: state.currentBackgroundCard,
            generating: state.isCurrentBackgroundCardGenerating,
            error: state.currentBackgroundCardError
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            backgroundCardPanel.animator().alphaValue = 1
        }
    }

    private func hideBackgroundCard() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            backgroundCardPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.backgroundCardPanel.isHidden = true
            self?.backgroundCardPanel.alphaValue = 1
        })
    }

    private func confirmRegenerateBackgroundCard() {
        guard let window else { return }
        guard let card = state.currentBackgroundCard else {
            state.regenerateBackgroundCard()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "重新生成视频背景卡？"
        alert.informativeText = "将重新读取完整字幕。已经完成的字幕翻译不会自动改变。"
        if card.wasEdited {
            alert.addButton(withTitle: "保留术语并重新生成")
            alert.addButton(withTitle: "全部覆盖")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.state.regenerateBackgroundCard(preservingUserTerms: true)
                } else if response == .alertSecondButtonReturn {
                    self?.state.regenerateBackgroundCard()
                }
            }
        } else {
            alert.addButton(withTitle: "重新生成")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.state.regenerateBackgroundCard() }
            }
        }
    }

    @objc private func showTranslationMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "翻译选项")
        let fill = NSMenuItem(title: "补全翻译（\(state.missingTranslationCount) 句）", action: #selector(fillMissingTranslations), keyEquivalent: "")
        fill.target = self
        fill.isEnabled = state.currentTranscript != nil && state.missingTranslationCount > 0
        menu.addItem(fill)
        let all = NSMenuItem(title: "全部重新翻译…", action: #selector(confirmRetranslateAll), keyEquivalent: "")
        all.target = self
        all.isEnabled = state.currentTranscript != nil
        menu.addItem(all)
        menu.addItem(.separator())
        let fetch = NSMenuItem(title: "重新获取原字幕", action: #selector(retryTranscript), keyEquivalent: "")
        fetch.target = self
        menu.addItem(fetch)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 2), in: sender)
    }
    @objc private func fillMissingTranslations() { state.translateMissing() }
    @objc private func retryClickedSubtitle() {
        let row = subtitleTable.clickedRow
        guard row >= 0, let segment = state.currentTranscript?.segments[safe: row] else { return }
        state.translateSegment(id: segment.id)
    }
    @objc private func confirmRetranslateAll() {
        guard let window else { return }
        let count = state.currentTranscript?.segments.count ?? 0
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "全部重新翻译？"
        alert.informativeText = "将清除当前 \(count) 句的中文翻译并重新调用翻译服务。原英文字幕不会改变。"
        alert.addButton(withTitle: "全部重新翻译")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.state.retranslateAll() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === subtitleTable.menu, let item = menu.items.first else { return }
        let row = subtitleTable.clickedRow
        item.isEnabled = row >= 0
        if row >= 0, let segment = state.currentTranscript?.segments[safe: row] {
            item.title = segment.translation?.isEmpty == false ? "重新翻译此句" : "补翻此句"
        } else {
            item.title = "补翻 / 重试此句"
        }
    }
    @objc private func openSettings() { NotificationCenter.default.post(name: .echoOpenSettings, object: nil) }
    @objc private func toggleFloating() { NotificationCenter.default.post(name: .echoToggleFloatingWindow, object: nil) }
    @objc private func toggleLyrics() { NotificationCenter.default.post(name: .echoToggleLyricsWindow, object: nil) }
    @objc private func togglePlayerFullscreen() {
        if playerWindowOverlay != nil {
            exitPlayerFullscreen()
            return
        }
        guard let content = window?.contentView else { return }
        playerView.removeFromSuperview()
        let overlay = PlayerWindowOverlay(playerView: playerView) { [weak self] in
            self?.exitPlayerFullscreen()
        }
        playerWindowOverlay = overlay
        content.addSubview(overlay, positioned: .above, relativeTo: nil)
        overlay.pinEdges(to: content)
        window?.makeFirstResponder(overlay)
    }

    private func exitPlayerFullscreen() {
        guard let overlay = playerWindowOverlay else { return }
        playerView.removeFromSuperview()
        overlay.removeFromSuperview()
        playerContainer.addSubview(playerView, positioned: .below, relativeTo: stateOverlay)
        playerView.pinEdges(to: playerContainer)
        playerWindowOverlay = nil
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func openYouTube() {
        guard let value = state.currentVideo?.url, let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    func playerView(_ view: YouTubePlayerView, didUpdateTime time: Double) { state.updatePlaybackTime(time) }
    func playerView(_ view: YouTubePlayerView, didChangeState playerState: Int) {
        isPlaying = playerState == 1
        playButton.image = NSImage(systemSymbolName: isPlaying ? "pause.fill" : "play.fill", accessibilityDescription: nil)
    }
    func playerView(_ view: YouTubePlayerView, didFailWithCode code: Int) {
        if code == 101 || code == 150 || code == 152 || code == 153 {
            stateOverlay.isHidden = false
            playerView.isHidden = true
            nativeFullscreenButton.isHidden = true
            stateOverlay.removeAllSubviews()
            let title = EchoStyle.label("该视频不允许在第三方播放器中播放", size: 15, weight: .semibold)
            let detail = EchoStyle.label("可以在 YouTube 中打开；已获取的字幕仍可继续阅读。", size: 12, color: EchoStyle.textSecondary)
            let open = EchoStyle.button("在 YouTube 打开", symbol: "arrow.up.right.square", target: self, action: #selector(openYouTube), primary: true)
            let stack = NSStackView(views: [title, detail, open])
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            stateOverlay.addSubview(stack)
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: stateOverlay.centerXAnchor), stack.centerYAnchor.constraint(equalTo: stateOverlay.centerYAnchor)])
        }
    }

    private func applyInitialSplitLayout() {
        guard let splitView, splitView.bounds.width > 700 else {
            DispatchQueue.main.async { [weak self] in self?.applyInitialSplitLayout() }
            return
        }
        isApplyingSplitLayout = true
        defer { isApplyingSplitLayout = false }
        let defaults = UserDefaults.standard
        let leftValue = defaults.object(forKey: "mainPlaylistWidth") == nil ? 236 : defaults.double(forKey: "mainPlaylistWidth")
        let rightValue = defaults.object(forKey: "mainSubtitleWidth") == nil ? 348 : defaults.double(forKey: "mainSubtitleWidth")
        let left = min(360, max(180, CGFloat(leftValue)))
        let right = min(520, max(280, CGFloat(rightValue)))
        lastPlaylistWidth = left
        lastSubtitleWidth = right
        splitView.setPosition(left, ofDividerAt: 0)
        splitView.setPosition(splitView.bounds.width - right - splitView.dividerThickness, ofDividerAt: 1)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === playlistContainer || subview === subtitleContainer
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 { return playlistCollapsed ? 0 : 180 }
        let leading = playlistCollapsed ? 0 : playlistContainer.frame.width + splitView.dividerThickness
        return leading + 360
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            let right = subtitleCollapsed ? 0 : max(280, splitView.subviews[safe: 2]?.frame.width ?? lastSubtitleWidth)
            return min(360, splitView.bounds.width - 360 - right - splitView.dividerThickness * 2)
        }
        return subtitleCollapsed ? splitView.bounds.width : splitView.bounds.width - 280 - splitView.dividerThickness
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingSplitLayout, let splitView, splitView.subviews.count == 3 else { return }
        let left = splitView.subviews[0].frame.width
        let right = splitView.subviews[2].frame.width
        if !playlistCollapsed, left >= 180 {
            lastPlaylistWidth = left
            UserDefaults.standard.set(Double(left), forKey: "mainPlaylistWidth")
        }
        if !subtitleCollapsed, right >= 280 {
            lastSubtitleWidth = right
            UserDefaults.standard.set(Double(right), forKey: "mainSubtitleWidth")
        }
        if subtitleTable.numberOfRows > 0 {
            subtitleTable.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<subtitleTable.numberOfRows))
        }
    }

    func windowWillClose(_ notification: Notification) {
        if playerWindowOverlay != nil { exitPlayerFullscreen() }
        state.saveCurrentProgress()
    }
}

private final class PlaylistCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PlaylistCell")
    private let thumbnail = NSImageView()
    private let title = EchoStyle.label("", size: 11.5, weight: .medium, lines: 2)
    private let subtitle = EchoStyle.label("", size: 10, color: EchoStyle.textTertiary)
    private let badge = EchoStyle.label("", size: 9.5, weight: .semibold)
    private let accentBar = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        wantsLayer = true
        layer?.cornerRadius = 7
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = EchoStyle.accent.cgColor
        accentBar.layer?.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.imageScaling = .scaleAxesIndependently
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 5
        thumbnail.layer?.masksToBounds = true
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        let meta = NSStackView(views: [title, subtitle, badge])
        meta.orientation = .vertical
        meta.alignment = .leading
        meta.spacing = 2
        meta.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentBar)
        addSubview(thumbnail)
        addSubview(meta)
        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 74),
            thumbnail.heightAnchor.constraint(equalToConstant: 44),
            meta.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8),
            meta.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            meta.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { nil }

    func configure(_ video: VideoItem, current: Bool) {
        title.stringValue = video.title
        subtitle.stringValue = video.channel
        badge.stringValue = "● \(video.status.label)"
        switch video.status {
        case .ready: badge.textColor = .systemGreen
        case .loading, .translating: badge.textColor = .systemBlue
        case .noSubtitles: badge.textColor = .systemOrange
        case .failed: badge.textColor = .systemRed
        case .idle: badge.textColor = EchoStyle.textTertiary
        }
        layer?.backgroundColor = current ? NSColor(calibratedWhite: 1, alpha: 0.13).cgColor : NSColor.clear.cgColor
        accentBar.isHidden = !current
        thumbnail.loadRemoteImage(video.thumbnailURL)
    }
}

final class SubtitleCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SubtitleCell")
    private let time = EchoStyle.label("", size: 9.5, color: EchoStyle.textTertiary)
    private let original = EchoStyle.label("", size: 13, weight: .medium, lines: 0)
    private let translation = EchoStyle.label("", size: 12, color: EchoStyle.textSecondary, lines: 0)
    private let bar = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        wantsLayer = true
        bar.wantsLayer = true
        bar.layer?.backgroundColor = EchoStyle.accent.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        let texts = NSStackView(views: [original, translation])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 5
        texts.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        addSubview(time)
        addSubview(texts)
        time.alignment = .left
        original.alignment = .left
        translation.alignment = .left
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),
            time.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            time.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            time.widthAnchor.constraint(equalToConstant: 38),
            texts.leadingAnchor.constraint(equalTo: time.trailingAnchor, constant: 2),
            texts.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            texts.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            texts.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            original.widthAnchor.constraint(equalTo: texts.widthAnchor),
            translation.widthAnchor.constraint(equalTo: texts.widthAnchor),
        ])
    }
    required init?(coder: NSCoder) { nil }

    var subtitleTextFrames: [NSRect] {
        layoutSubtreeIfNeeded()
        return [original.frame, translation.frame]
    }

    func configure(_ segment: SubtitleSegment, mode: SubtitleDisplayMode, current: Bool) {
        let settings = AppSettings.shared
        time.stringValue = formattedTime(segment.start)
        let translated = segment.translation ?? (mode == .original ? "" : "等待翻译…")
        EchoStyle.applySubtitleText(
            original,
            text: segment.original,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: settings.englishSubtitleColor
        )
        EchoStyle.applySubtitleText(
            translation,
            text: translated,
            font: .systemFont(ofSize: 12),
            color: settings.chineseSubtitleColor
        )
        original.isHidden = mode == .translated
        translation.isHidden = mode == .original
        layer?.backgroundColor = current ? EchoStyle.highlight.cgColor : NSColor.clear.cgColor
        bar.isHidden = !current
    }
}

private final class PlayerWindowOverlay: NSView {
    private let playerView: YouTubePlayerView
    private let exitHandler: () -> Void

    init(playerView: YouTubePlayerView, exitHandler: @escaping () -> Void) {
        self.playerView = playerView
        self.exitHandler = exitHandler
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(playerView)

        let exit = EchoStyle.iconButton("arrow.down.right.and.arrow.up.left", help: "退出播放器窗口全屏", target: self, action: #selector(exitFullscreen))
        exit.wantsLayer = true
        exit.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        exit.layer?.cornerRadius = 22
        addSubview(exit)
        NSLayoutConstraint.activate([
            exit.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            exit.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exit.widthAnchor.constraint(equalToConstant: 48),
            exit.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    @objc private func exitFullscreen() { exitHandler() }
    override func cancelOperation(_ sender: Any?) { exitHandler() }

    override func layout() {
        super.layout()
        let targetAspect: CGFloat = 16.0 / 9.0
        let availableAspect = bounds.width / max(1, bounds.height)
        let size: NSSize
        if availableAspect > targetAspect {
            size = NSSize(width: bounds.height * targetAspect, height: bounds.height)
        } else {
            size = NSSize(width: bounds.width, height: bounds.width / targetAspect)
        }
        playerView.frame = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

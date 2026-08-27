import Testing
import AppKit
@testable import EchoSub

@Suite("EchoSub core")
struct CoreTests {
    @Test("Parses common YouTube URLs")
    func parsesCommonYouTubeURLs() {
        #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=4") == "dQw4w9WgXcQ")
        #expect(YouTubeURLParser.videoID(from: "https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURLParser.videoID(from: "https://youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURLParser.videoID(from: "https://example.com/watch?v=dQw4w9WgXcQ") == nil)
    }

    @Test("Groups caption fragments into semantic sentences")
    func groupsFragmentsIntoSemanticSentences() {
        let cues = [
            RawCaptionCue(text: "The human voice", start: 0, duration: 1.2),
            RawCaptionCue(text: "is the instrument", start: 1.2, duration: 1.2),
            RawCaptionCue(text: "we all play.", start: 2.4, duration: 1.2),
            RawCaptionCue(text: "It is powerful.", start: 3.6, duration: 2.3),
        ]
        let segments = SubtitleSegmenter.group(cues)
        #expect(segments.count == 2)
        #expect(segments[0].original == "The human voice is the instrument we all play.")
        #expect(segments[0].start == 0)
    }

    @Test("Plans every missing translation without a hidden cap")
    func plansEveryMissingTranslation() {
        let segments = (0..<100).map {
            SubtitleSegment(id: "s\($0)", start: Double($0), end: Double($0 + 1), original: "Line \($0)", translation: $0.isMultiple(of: 3) ? "已翻译" : nil)
        }
        let document = TranscriptDocument(videoID: "video", sourceLanguage: "en", isGenerated: false, segments: segments)
        #expect(TranslationWorkPlan.segments(from: document, scope: .missing).count == 66)
        #expect(TranslationWorkPlan.segments(from: document, scope: .all).count == 100)
    }

    @Test("Interrupted translation status is recovered after an app restart")
    func recoversInterruptedTranslationStatus() {
        var interrupted = VideoItem(id: "interrupted", url: "https://www.youtube.com/watch?v=interrupted")
        interrupted.status = .translating
        let transcript = TranscriptDocument(
            videoID: interrupted.id,
            sourceLanguage: "en",
            isGenerated: false,
            segments: [SubtitleSegment(id: "s0", start: 0, end: 1, original: "Hello", translation: nil)]
        )
        var library = AppLibrary(videos: [interrupted], transcripts: [interrupted.id: transcript])

        let recovered = library.recoverInterruptedOperations()

        #expect(recovered == [interrupted.id])
        #expect(library.videos.first?.status == .ready)
    }

    @Test("Different videos keep independent translation jobs")
    func parallelVideoTranslationJobs() {
        var jobs = TranslationJobRegistry()
        let firstJob = UUID()
        let secondJob = UUID()

        jobs.start(videoID: "first", jobID: firstJob)
        jobs.start(videoID: "second", jobID: secondJob)

        #expect(jobs.matches(videoID: "first", jobID: firstJob))
        #expect(jobs.matches(videoID: "second", jobID: secondJob))
        jobs.finish(videoID: "first", jobID: firstJob)
        #expect(!jobs.isRunning(videoID: "first"))
        #expect(jobs.matches(videoID: "second", jobID: secondJob))
    }

    @Test("Rate-limited batches retry three total attempts then move on")
    func translationRetryPolicy() {
        let rateLimit = TranslationError.requestFailed(
            statusCode: 429,
            message: "rate limited",
            retryAfter: 7
        )

        #expect(TranslationRetryPolicy.delay(afterFailedAttempt: 1, error: rateLimit) == 7)
        #expect(TranslationRetryPolicy.delay(afterFailedAttempt: 2, error: rateLimit) == 15)
        #expect(TranslationRetryPolicy.delay(afterFailedAttempt: 3, error: rateLimit) == nil)
    }

    @Test("Routine translation disables thinking while background analysis keeps it")
    func translationThinkingPolicy() {
        #expect(TranslationRequestPolicy.thinkingMode(model: "qwen3.7-flash", purpose: .translation) == false)
        #expect(TranslationRequestPolicy.thinkingMode(model: "qwen3.7-flash", purpose: .backgroundCard) == true)
        #expect(TranslationRequestPolicy.thinkingMode(model: "qwen3.8-flash", purpose: .backgroundCard) == true)
        #expect(TranslationRequestPolicy.thinkingMode(model: "qwen-3.8-flash", purpose: .backgroundCard) == true)
        #expect(TranslationRequestPolicy.thinkingMode(model: "deepseek-v4-flash", purpose: .translation) == false)
        #expect(TranslationRequestPolicy.thinkingMode(model: "gpt-4o-mini", purpose: .translation) == nil)
    }

    @Test("Long subtitle jobs use smaller batches and a realistic request timeout")
    func longVideoTranslationPolicy() {
        #expect(TranslationRequestPolicy.batchSize == 4)
        #expect(TranslationRequestPolicy.translationTimeout == 120)
        #expect(TranslationRequestPolicy.backgroundCardTimeout == 600)
        #expect(TranslationRequestPolicy.backgroundCardResourceTimeout == 720)
        #expect(TranslationRetryPolicy.delay(afterFailedAttempt: 1, error: TranslationError.malformedResponse) == 5)
        #expect(TranslationRetryPolicy.delay(afterFailedAttempt: 2, error: TranslationError.malformedResponse) == 15)
    }

    @Test("Retries model responses that omit individual subtitle IDs")
    func identifiesPartiallyTranslatedBatch() {
        let batch = (0..<4).map {
            SubtitleSegment(id: "s\($0)", start: Double($0), end: Double($0 + 1), original: "Line \($0)", translation: nil)
        }
        let unresolved = TranslationWorkPlan.unresolved(in: batch, translations: ["s0": "零", "s2": "二"])
        #expect(unresolved.map(\.id) == ["s1", "s3"])
    }

    @Test("Single-line retries include neighboring subtitle context")
    func buildsNeighboringTranslationContext() {
        let segments = (0..<7).map {
            SubtitleSegment(id: "s\($0)", start: Double($0), end: Double($0 + 1), original: "Line \($0)", translation: $0 < 3 ? "译文 \($0)" : nil)
        }
        let document = TranscriptDocument(videoID: "video", sourceLanguage: "en", isGenerated: false, segments: segments)

        let context = TranslationWorkPlan.context(around: [segments[3]], in: document)

        #expect(context.map(\.id) == ["s1", "s2", "s3", "s4", "s5"])
        #expect(context.first(where: { $0.id == "s2" })?.translation == "译文 2")
    }

    @Test("Right-panel bilingual lines share one full-width left edge")
    @MainActor
    func rightPanelSubtitleAlignment() {
        let cell = SubtitleCell(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
        let segment = SubtitleSegment(
            id: "alignment",
            start: 0,
            end: 2,
            original: "Short English line.",
            translation: "较短的中文行。"
        )
        cell.configure(segment, mode: .bilingual, current: false)
        cell.layoutSubtreeIfNeeded()

        let frames = cell.subtitleTextFrames
        #expect(abs(frames[0].minX - frames[1].minX) < 0.5)
        #expect(abs(frames[0].width - frames[1].width) < 0.5)
        #expect(frames[0].width > 250)
    }

    @Test("Right-panel selectable English occupies its own non-overlapping rows")
    @MainActor
    func rightPanelSelectableEnglishLayoutDoesNotOverlapTranslation() {
        let segment = SubtitleSegment(
            id: "wrapped-layout",
            start: 0,
            end: 5,
            original: "Depression has been something I have struggled with for many years, and every sentence must remain independently readable.",
            translation: "抑郁是我多年来一直面对的问题，每一行字幕都必须保持独立且清晰可读，不能与英文重叠。"
        )
        let width: CGFloat = 520
        let height = SubtitleRowLayout.rowHeight(
            for: segment,
            mode: .bilingual,
            availableWidth: width - 70
        )
        // NSTableView creates reusable views at .zero, configures them, and only
        // then assigns the actual row frame. Reproduce that lifecycle here.
        let cell = SubtitleCell()
        cell.configure(segment, videoID: "video-a", mode: .bilingual, current: false)
        cell.frame = NSRect(x: 0, y: 0, width: width, height: height)
        cell.layoutSubtreeIfNeeded()

        let frames = cell.subtitleTextFrames
        #expect(frames[0].height >= 30)
        #expect(frames[1].height >= 30)
        #expect(frames[0].height >= cell.originalTextUsedHeight)
        #expect(!frames[0].intersects(frames[1]))
        guard let textView = cell.descendants.compactMap({ $0 as? SelectableEnglishTextView }).first else {
            Issue.record("Expected a selectable English text view")
            return
        }
        #expect(textView.intrinsicContentSize.height >= cell.originalTextUsedHeight)
    }

    @Test("Right-panel English text view owns a hittable selection surface")
    @MainActor
    func rightPanelEnglishTextViewIsHittable() {
        let segment = SubtitleSegment(
            id: "selection-surface",
            start: 0,
            end: 3,
            original: "First, gossip means speaking ill of somebody.",
            translation: "第一，八卦指的是在背后说别人坏话。"
        )
        let cell = SubtitleCell(frame: NSRect(x: 0, y: 0, width: 520, height: 100))
        cell.configure(segment, videoID: "video-a", mode: .bilingual, current: false)
        cell.layoutSubtreeIfNeeded()

        guard let textView = cell.descendants.compactMap({ $0 as? SelectableEnglishTextView }).first else {
            Issue.record("Expected a selectable English text view")
            return
        }
        let pointInCell = textView.convert(NSPoint(x: 8, y: max(1, textView.bounds.midY)), to: cell)
        let hit = cell.hitTest(pointInCell)

        #expect(textView.frame.height >= cell.originalTextUsedHeight)
        #expect(hit === textView || hit?.isDescendant(of: textView) == true)
    }

    @Test("Subtitle rendering uses one plain font color without an outline")
    @MainActor
    func simpleSubtitleColorRendering() {
        let field = EchoStyle.label("", size: 13, lines: 0)
        EchoStyle.applySubtitleText(
            field,
            text: "Left aligned subtitle",
            font: .systemFont(ofSize: 13),
            color: .systemBlue
        )

        #expect(field.alignment == .left)
        #expect(field.cell?.alignment == .left)
        #expect(field.attributedStringValue.attribute(.strokeWidth, at: 0, effectiveRange: nil) == nil)
        #expect(field.textColor?.echoHex == NSColor.systemBlue.echoHex)
    }

    @Test("Loads existing libraries created before background cards were introduced")
    func decodesLegacyLibraryWithoutBackgroundCards() throws {
        let json = """
        {
          "videos": [],
          "transcripts": {}
        }
        """
        let library = try JSONDecoder.echo.decode(AppLibrary.self, from: Data(json.utf8))
        #expect(library.videos.isEmpty)
        #expect(library.transcripts.isEmpty)
        #expect(library.backgroundCards.isEmpty)
    }

    @Test("Background card exposes compact global translation context")
    func backgroundCardTranslationContext() {
        let card = VideoBackgroundCard(
            videoID: "video",
            overview: "完整视频围绕播放器控件展开。",
            chapters: [BackgroundChapter(start: 12, end: 42, title: "控件参数")],
            domain: "软件开发",
            tone: "口语化教程",
            entities: [BackgroundEntity(source: "Google Developers", preferredTranslation: "Google 开发者")],
            terminology: [BackgroundTerm(source: "controls", preferredTranslation: "控件")],
            uncertainties: [],
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: 20
        )

        #expect(card.translationContext["overview"] as? String == "完整视频围绕播放器控件展开。")
        #expect((card.translationContext["terminology"] as? [[String: String]])?.first?["preferred_zh"] == "控件")
    }

    @Test("Background card drawer lays out empty, loading, and ready states")
    @MainActor
    func backgroundCardPanelStates() {
        let panel = BackgroundCardPanel(frame: NSRect(x: 0, y: 0, width: 360, height: 640))
        panel.render(video: nil, card: nil, generating: false, error: nil)
        panel.layoutSubtreeIfNeeded()
        #expect(panel.subviews.count == 2)

        panel.render(video: nil, card: nil, generating: true, error: nil)
        panel.layoutSubtreeIfNeeded()
        #expect(panel.subviews.count == 2)

        let video = VideoItem(id: "video", url: "https://www.youtube.com/watch?v=video")
        let card = VideoBackgroundCard(
            videoID: "video",
            overview: "完整概括。",
            chapters: [BackgroundChapter(start: 0, end: 30, title: "开场")],
            domain: "教育",
            tone: "自然",
            entities: [],
            terminology: [],
            uncertainties: [],
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: 12
        )
        panel.render(video: video, card: card, generating: false, error: nil)
        panel.layoutSubtreeIfNeeded()
        #expect(panel.subviews.count == 2)
    }

    @Test("Stores both API keys as plaintext JSON without losing either value")
    func plaintextCredentialStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoSubCredentialTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PlaintextCredentialStore(fileURL: fileURL)
        store.saveTranslationAPIKey("  translate-secret  ")
        store.saveSupadataAPIKey("supadata-secret")

        #expect(store.loadTranslationAPIKey() == "translate-secret")
        #expect(store.loadSupadataAPIKey() == "supadata-secret")
        let plaintext = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(plaintext.contains("translate-secret"))
        #expect(plaintext.contains("supadata-secret"))
    }

    @Test("Production credentials live beside the subtitle library")
    func credentialStorageLocation() {
        #expect(PlaintextCredentialStore.shared.fileURL.deletingLastPathComponent() == EchoStorage.directoryURL)
        #expect(PlaintextCredentialStore.shared.fileURL.lastPathComponent == "credentials.json")
    }

    @Test("Diagnostic logs are stored locally and redact credentials")
    func diagnosticLogRedaction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoSubDiagnosticTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("diagnostics.jsonl")
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticLogger(fileURL: fileURL)

        logger.record("translation.request.started", fields: [
            "model": "qwen3.7-flash",
            "api_key": "never-write-this-secret",
            "header": "Bearer another-secret",
        ])

        let log = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(log.contains("translation.request.started"))
        #expect(log.contains("qwen3.7-flash"))
        #expect(!log.contains("never-write-this-secret"))
        #expect(!log.contains("another-secret"))
    }

    @Test("Floating bilingual rows grow for every wrapped English and Chinese line")
    func floatingSubtitleRowHeightFitsBothLanguages() {
        let segment = SubtitleSegment(
            id: "wrapped",
            start: 0,
            end: 4,
            original: "goal, aka you want the good grades, but you don't know where you're going to get the fried chicken, then you're just going to walk around aimlessly and",
            translation: "目标，也就是你想要好成绩，但如果你不知道去哪里买炸鸡，那你就只会漫无目的地走来走去，"
        )
        let width: CGFloat = 380
        let fontSize: CGFloat = 16.4553125
        let englishOnly = FloatingSubtitleLayout.rowHeight(
            for: segment,
            mode: .original,
            availableWidth: width,
            fontSize: fontSize
        )
        let bilingual = FloatingSubtitleLayout.rowHeight(
            for: segment,
            mode: .bilingual,
            availableWidth: width,
            fontSize: fontSize
        )
        let highlightedEnglishHeight = ceil(NSAttributedString(
            string: segment.original,
            attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
        ).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        let translatedHeight = ceil(NSAttributedString(
            string: segment.translation ?? "",
            attributes: [.font: NSFont.systemFont(ofSize: max(11, fontSize - 3))]
        ).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        let requiredHighlightedHeight = 16 + highlightedEnglishHeight + 5 + translatedHeight

        #expect(bilingual > englishOnly + 20)
        #expect(bilingual >= requiredHighlightedHeight)
    }

    @Test("Floating active row never compresses an existing Chinese translation")
    @MainActor
    func floatingActiveRowKeepsTranslationVisible() {
        let translation = "这绝不是某种疗法，也不是治愈手段。"
        let segment = SubtitleSegment(
            id: "current-wrap",
            start: 0,
            end: 4,
            original: "ago, I was going through one of my bad bouts of depression and I came across this question, which is very simple, and",
            translation: translation,
            glosses: [GlossEntry(surface: "depression", gloss: "抑郁；低落状态")]
        )
        let actualCellWidth: CGFloat = 410
        let fontSize: CGFloat = 18
        let rowHeight = FloatingSubtitleLayout.rowHeight(
            for: segment,
            mode: .bilingual,
            availableWidth: actualCellWidth - 24,
            fontSize: fontSize
        )
        let cell = FloatingCell(frame: NSRect(x: 0, y: 0, width: actualCellWidth, height: rowHeight))

        cell.configure(segment, mode: .bilingual, current: false, fontSize: fontSize)
        cell.layoutSubtreeIfNeeded()
        cell.configure(segment, mode: .bilingual, current: true, fontSize: fontSize)
        cell.layoutSubtreeIfNeeded()

        let translated = cell.descendants.compactMap { $0 as? NSTextField }.first { $0.stringValue == translation }
        #expect(translated?.isHidden == false)
        let visibleHeight = translated?.frame.height ?? 0
        let requiredHeight = translated.map {
            ceil($0.attributedStringValue.boundingRect(
                with: NSSize(width: max(1, $0.frame.width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
        } ?? .greatestFiniteMagnitude
        #expect(visibleHeight >= requiredHeight)
        let original = cell.descendants.compactMap { $0 as? SelectableEnglishTextView }.first
        let glosses = cell.descendants.compactMap { $0 as? GlossInlineView }.first
        let exactRequiredHeight = 16
            + (original?.intrinsicContentSize.height ?? 0)
            + 5 + requiredHeight
            + 5 + (glosses?.height(for: glosses?.bounds.width ?? 1) ?? 0)
        #expect(rowHeight >= exactRequiredHeight)
    }

    @Test("Per-cue diagnostics explain the last translation outcome")
    func translationCueDiagnosticExplainsOutcome() {
        let segment = SubtitleSegment(
            id: "segment-83-510040",
            start: 510.04,
            end: 514,
            original: "and we live a life that is always in preparation for the future, and that",
            translation: "我们过着一种永远在为未来做准备的生活，而"
        )
        let diagnostic = TranslationCueDiagnostic(
            videoID: "video",
            segmentID: segment.id,
            phase: .succeeded,
            attempt: 1,
            maximumAttempts: 3,
            message: "模型已返回并保存此句译文。",
            requestID: "request-123",
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(diagnostic.menuTitle.contains("翻译成功"))
        #expect(diagnostic.detailText(for: segment).contains("字幕 ID：segment-83-510040"))
        #expect(diagnostic.detailText(for: segment).contains("当前译文：我们过着一种永远在为未来做准备的生活，而"))
        #expect(diagnostic.detailText(for: segment).contains("请求 ID：request-123"))
    }

    @Test("Main subtitle row never compresses a translation after retry succeeds")
    @MainActor
    func mainSubtitleRowKeepsRetriedTranslationVisible() {
        let translation = "我们过着一种永远在为未来做准备的生活，而那个时刻却迟迟没有到来。"
        let segment = SubtitleSegment(
            id: "retry-success",
            start: 510,
            end: 515,
            original: "and we live a life that is always in preparation for the future, and that",
            translation: translation
        )
        let tableWidth: CGFloat = 380
        let rowHeight = SubtitleRowLayout.rowHeight(
            for: segment,
            mode: .bilingual,
            availableWidth: tableWidth - 70
        )
        let cell = SubtitleCell(frame: NSRect(x: 0, y: 0, width: tableWidth, height: rowHeight))
        cell.configure(segment, mode: .bilingual, current: true)
        cell.layoutSubtreeIfNeeded()

        let translated = cell.descendants.compactMap { $0 as? NSTextField }.first { $0.stringValue == translation }
        #expect(translated?.isHidden == false)
        let visibleHeight = translated?.frame.height ?? 0
        let requiredHeight = translated.map {
            ceil($0.attributedStringValue.boundingRect(
                with: NSSize(width: max(1, $0.frame.width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height)
        } ?? .greatestFiniteMagnitude
        #expect(visibleHeight >= requiredHeight)
    }

    @Test("Auto-follow positions the active subtitle near the top of the viewport")
    func floatingSubtitleFollowPosition() {
        let origin = SubtitleAutoFollow.scrollOrigin(
            row: NSRect(x: 0, y: 900, width: 400, height: 100),
            documentHeight: 2_000,
            viewportHeight: 400
        )
        #expect(origin == 820)
    }

    @Test("Transparent subtitle scrolling invalidates old glyph pixels")
    @MainActor
    func transparentSubtitleScrollInvalidatesVisibleSurface() {
        let scroll = TransparentSubtitleScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        scroll.documentView = document

        let before = scroll.transparentRedrawCount
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)

        #expect(scroll.transparentRedrawCount == before + 1)
        #expect(scroll.lastInvalidatedDocumentRect.height > 0)
        #expect(scroll.lastInvalidatedDocumentRect.intersects(scroll.documentVisibleRect))
    }

    @Test("Fully transparent floating subtitles do not use a glyph-shaped window shadow")
    @MainActor
    func floatingSubtitleWindowDisablesSystemShadow() {
        let controller = FloatingSubtitleWindowController()
        #expect(controller.window?.hasShadow == false)
    }

    @Test("Hidden videos stay persisted but disappear from the active playlist")
    func hiddenVideoLibrarySemantics() {
        let first = VideoItem(id: "first", url: "https://www.youtube.com/watch?v=first")
        let second = VideoItem(id: "second", url: "https://www.youtube.com/watch?v=second")
        let transcript = TranscriptDocument(videoID: "first", sourceLanguage: "en", isGenerated: false, segments: [])
        var library = AppLibrary(videos: [first, second], transcripts: ["first": transcript])

        library.hideVideo("first")
        #expect(library.visibleVideos.map(\.id) == ["second"])
        #expect(library.hiddenVideos.map(\.id) == ["first"])
        #expect(library.transcripts["first"] != nil)

        library.unhideVideo("first")
        #expect(library.visibleVideos.map(\.id) == ["first", "second"])
        #expect(library.hiddenVideos.isEmpty)
    }

    @Test("Deleting a video removes its metadata, subtitles, and background card")
    func deletingVideoRemovesAllStoredData() {
        let video = VideoItem(id: "delete-me", url: "https://www.youtube.com/watch?v=delete-me")
        let transcript = TranscriptDocument(videoID: video.id, sourceLanguage: "en", isGenerated: false, segments: [])
        let card = VideoBackgroundCard(
            videoID: video.id,
            overview: "overview",
            chapters: [],
            domain: "",
            tone: "",
            entities: [],
            terminology: [],
            uncertainties: [],
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: 0
        )
        var library = AppLibrary(videos: [video], transcripts: [video.id: transcript], backgroundCards: [video.id: card])

        library.deleteVideo(video.id)

        #expect(library.videos.isEmpty)
        #expect(library.transcripts[video.id] == nil)
        #expect(library.backgroundCards[video.id] == nil)
        #expect(!library.hiddenVideoIDs.contains(video.id))
    }

    @Test("Playback queue supports list loop and single-video loop")
    func playbackQueueLoopModes() {
        let videos = [
            VideoItem(id: "a", url: "https://www.youtube.com/watch?v=a"),
            VideoItem(id: "b", url: "https://www.youtube.com/watch?v=b"),
            VideoItem(id: "c", url: "https://www.youtube.com/watch?v=c"),
        ]

        #expect(PlaybackQueue.nextVideoID(after: "b", videos: videos, mode: .list) == "c")
        #expect(PlaybackQueue.nextVideoID(after: "c", videos: videos, mode: .list) == "a")
        #expect(PlaybackQueue.nextVideoID(after: "b", videos: videos, mode: .single) == "b")
        #expect(PlaybackQueue.nextVideoID(after: "b", videos: videos, mode: .none) == nil)
    }

    @Test("Legacy subtitle rows decode with empty vocabulary and overrides prefer non-empty user text")
    func subtitleVocabularyAndOverrideCompatibility() throws {
        let json = """
        {"id":"legacy","start":0,"end":1,"original":"Hello","translation":null}
        """
        var segment = try JSONDecoder.echo.decode(SubtitleSegment.self, from: Data(json.utf8))
        #expect(segment.glosses.isEmpty)
        #expect(segment.effectiveTranslation == nil)
        segment.zhUserOverride = "  人工补译  "
        #expect(segment.effectiveTranslation == "人工补译")
        let document = TranscriptDocument(videoID: "video", sourceLanguage: "en", isGenerated: false, segments: [segment])
        #expect(TranslationWorkPlan.segments(from: document, scope: .missing).isEmpty)
    }

    @Test("Gloss entries are idempotent by normalized term while preserving query order")
    func glossEntryNormalizationAndOrder() {
        let first = GlossEntry(id: "first", surface: "Gossip", gloss: "八卦")
        let second = GlossEntry(id: "second", surface: "judging", gloss: "评判")
        var segment = SubtitleSegment(id: "s", start: 0, end: 1, original: "Gossip and judging", translation: "八卦和评判", glosses: [first, second])
        let updated = GlossEntry(id: first.id, surface: "gossip", gloss: "闲话")
        segment.glosses[segment.glosses.firstIndex(where: { $0.normalized == updated.normalized })!] = updated
        #expect(segment.glosses.map(\.id) == ["first", "second"])
        #expect(segment.glosses.first?.gloss == "闲话")
    }

    @Test("Detail cache keys isolate both video and subtitle context and delete with the video")
    func detailCacheIsolationAndDeletion() {
        let video = VideoItem(id: "video-a", url: "https://www.youtube.com/watch?v=video-a")
        let other = VideoItem(id: "video-b", url: "https://www.youtube.com/watch?v=video-b")
        let key = VocabDetailCacheKey.make(normalizedTerm: "onwards", videoID: video.id, subtitleID: "s1")
        let otherSentence = VocabDetailCacheKey.make(normalizedTerm: "onwards", videoID: video.id, subtitleID: "s2")
        let otherVideo = VocabDetailCacheKey.make(normalizedTerm: "onwards", videoID: other.id, subtitleID: "s1")
        let detail = VocabDetail(surface: "onwards", contextual: "继续向前")
        var library = AppLibrary(videos: [video, other], detailCache: [key: detail, otherSentence: detail, otherVideo: detail])

        library.deleteVideo(video.id)

        #expect(library.detailCache[key] == nil)
        #expect(library.detailCache[otherSentence] == nil)
        #expect(library.detailCache[otherVideo] == detail)
    }

    @Test("Gloss and detail parsers accept JSON embedded in model text and source examples are first")
    func parsesVocabularyResponses() {
        let gloss = TranslationService.parseGlossResponse("Here is the result:\n{\"surface\":\"onwards\",\"normalized\":\"Onwards\",\"pos\":\"adv.\",\"contextual_gloss\":\"从那时起\"}")
        #expect(gloss?.normalized == "onwards")
        #expect(gloss?.contextualGloss == "从那时起")
        let detail = TranslationService.parseDetailResponse("thinking… {\"surface\":\"onwards\",\"contextual_meaning\":\"继续向前\",\"examples\":[{\"sentence\":\"Other example.\"}]}")
        let segment = SubtitleSegment(id: "s", start: 84, end: 86, original: "From that day onwards, I decided to speak differently.", translation: "从那天起，我决定换一种方式说话。")
        let completed = detail?.withSourceExample(segment)
        #expect(completed?.examples.first?.isSourceExample == true)
        #expect(completed?.examples.first?.timestamp == 84)
        #expect(completed?.forms.isEmpty == true)
    }

    @Test("English selection expands partial words and rejects Chinese or punctuation")
    @MainActor
    func normalizesSelectableEnglishSelection() {
        let text = SelectableEnglishTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        text.configure(text: "First, gossip.", font: .systemFont(ofSize: 13), color: .white)
        text.setSelectedRange(NSRange(location: 8, length: 2))
        #expect(text.selectedSurfaceText == "gossip")
        text.configure(text: "中文", font: .systemFont(ofSize: 13), color: .white)
        text.setSelectedRange(NSRange(location: 0, length: 2))
        #expect(text.selectedSurfaceText == nil)
        text.configure(text: "...", font: .systemFont(ofSize: 13), color: .white)
        text.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(text.selectedSurfaceText == nil)
    }

    @Test("Completing an English drag selection opens the lookup actions")
    @MainActor
    func completedEnglishSelectionPresentsActions() {
        let text = SelectableEnglishTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
        text.configure(
            text: "The thing about discipline is consistency.",
            font: .systemFont(ofSize: 13),
            color: .white
        )
        text.setSelectedRange(NSRange(location: 19, length: 5))
        var presentedSurface: String?
        text.onSelectionToolbar = { _, surface, _ in presentedSurface = surface }

        text.completeSelectionInteraction(clickCount: 1)

        #expect(presentedSurface == "discipline")
    }

    @Test("Vocabulary cells and detail content lay out with glosses, loading, and edit controls")
    @MainActor
    func vocabularyViewsLayout() {
        let entry = GlossEntry(surface: "gossip", gloss: "八卦；闲话")
        let segment = SubtitleSegment(id: "s", start: 0, end: 1, original: "Speaking ill of somebody.", translation: "说别人的闲话。", glosses: [entry])
        let floating = FloatingCell(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        floating.configure(segment, mode: .bilingual, current: true, fontSize: 16)
        floating.layoutSubtreeIfNeeded()
        let panel = VideoVocabularyPanel(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        let item = VocabularySummaryEntry(videoID: "video", segmentID: segment.id, gloss: entry, timestamp: 0, sourceSentence: segment.original)
        panel.render(video: VideoItem(id: "video", url: "https://www.youtube.com/watch?v=video"), entries: [item])
        panel.layoutSubtreeIfNeeded()
        #expect(panel.displayedCount == "1")
        let detail = VocabDetailContentView(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        detail.render(entry: entry, detail: VocabDetail(surface: "gossip", contextual: "在这里表示背后议论别人"), state: .idle)
        detail.layoutSubtreeIfNeeded()
        let editor = InlineTranslationEditor(value: "说别人的闲话。")
        editor.layoutSubtreeIfNeeded()
        let popover = VocabDetailPopover()
        popover.detailContentView.render(
            entry: entry,
            detail: VocabDetail(surface: "gossip", contextual: "在这里表示背后议论别人"),
            state: .idle
        )
        popover.detailContentView.layoutSubtreeIfNeeded()
        #expect(floating.subviews.isEmpty == false)
        #expect(panel.subviews.isEmpty == false)
        #expect(detail.subviews.isEmpty == false)
        #expect(editor.subviews.isEmpty == false)
        #expect(popover.contentViewController != nil)
        #expect(popover.contentSize == NSSize(width: 348, height: 480))
        let readingStack = popover.detailContentView.descendants
            .compactMap { $0 as? NSStackView }
            .first { $0.edgeInsets.left > 0 }
        #expect(readingStack?.edgeInsets.left == 26)
        #expect(readingStack?.edgeInsets.right == 26)
        let close = popover.detailContentView.descendants
            .compactMap { $0 as? NSButton }
            .first { $0.toolTip == "关闭（Esc）" }
        #expect(close != nil)
    }

    @Test("Vocabulary detail body keeps real horizontal padding and readable line spacing")
    @MainActor
    func vocabularyDetailBodyUsesReadableLayout() {
        let explanation = "传统意义上，discipline 常指军队、学校中的纪律或惩罚；在本视频的心理成长语境中，它与爱紧密相连。"
        let etymology = "源自拉丁语 disciplina，由 discipulus 派生，词根含有学习与训练的含义。"
        let detail = VocabDetail(
            surface: "discipline",
            pos: "noun",
            phonetic: "/dɪˈsɪplɪn/",
            contextualMeaning: "自律",
            explanation: explanation,
            etymology: etymology,
            examples: [
                VocabExample(
                    sentence: "She practiced discipline every morning, even when she felt overwhelmed.",
                    translation: "即使感到不堪重负，她仍坚持每天早晨练习自律。"
                )
            ]
        )
        let view = VocabDetailContentView(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        view.render(entry: GlossEntry(surface: "discipline", gloss: "自律", pos: "noun"), detail: detail, state: .idle)
        view.layoutSubtreeIfNeeded()

        let bodyLabels = view.descendants.compactMap { $0 as? NSTextField }.filter {
            $0.stringValue == explanation || $0.stringValue == etymology || $0.stringValue.contains("She practiced discipline")
        }
        #expect(bodyLabels.count == 3)
        for label in bodyLabels {
            let frame = label.convert(label.bounds, to: view)
            #expect(frame.minX >= 24)
            #expect(frame.maxX <= view.bounds.width - 24)
            let paragraph = label.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect((paragraph?.lineSpacing ?? 0) >= 4)
        }
        let word = view.descendants.compactMap { $0 as? NSTextField }.first { $0.stringValue == "discipline" }
        let wordFrame = word.map { $0.convert($0.bounds, to: view) }
        #expect((wordFrame?.minX ?? 0) >= 24)
    }

    @Test("Vocabulary panels stay dark, lay out from the top, and expose deletion")
    @MainActor
    func vocabularyPanelPresentationAndRemoval() {
        let entry = GlossEntry(surface: "achievements", gloss: "世俗成就", pos: "n")
        let summary = VocabularySummaryEntry(
            videoID: "video",
            segmentID: "cue",
            gloss: entry,
            timestamp: 533,
            sourceSentence: "Nobody was speaking about their achievements."
        )
        let panel = VideoVocabularyPanel(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        var removed: VocabularySummaryEntry?
        panel.onRemove = { removed = $0 }
        panel.render(video: VideoItem(id: "video", url: "https://www.youtube.com/watch?v=video"), entries: [summary])
        panel.layoutSubtreeIfNeeded()

        let background = panel.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.deviceRGB)
        let luminance = background.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent } ?? 1
        #expect(luminance < 0.3)
        #expect((background?.alphaComponent ?? 0) > 0.9)
        let panelScroll = panel.descendants.compactMap { $0 as? NSScrollView }.first
        #expect(panelScroll?.documentView?.isFlipped == true)
        let delete = panel.descendants.compactMap { $0 as? NSButton }.first { $0.toolTip == "删除词汇" }
        #expect(delete != nil)
        delete?.performClick(nil)
        #expect(removed == summary)

        let detail = VocabDetailContentView(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        detail.render(entry: entry, detail: nil, state: .loading)
        detail.layoutSubtreeIfNeeded()
        let detailScroll = detail.descendants.compactMap { $0 as? NSScrollView }.first
        #expect(detailScroll?.documentView?.isFlipped == true)
    }

    @Test("Cached details do not rebuild the vocabulary panel during its click event")
    func cachedDetailDoesNotPostVocabularyRefresh() {
        #expect(!VocabularyDetailRefreshPolicy.shouldPostVocabularyChangedAfterCacheHit())
    }

    @Test("Vocabulary panel text formats real counts and source sentences")
    func vocabularyPanelTextUsesValues() {
        #expect(VocabularyPanelText.count(3) == "3")
        #expect(VocabularyPanelText.source(timestamp: 84, sentence: "From that day onwards.") == "01:24  From that day onwards.")
        #expect(VocabularyPanelText.detailSource(timestamp: 84, sentence: "From that day onwards.") == "本句  01:24  From that day onwards.")
    }

    @Test("Vocabulary scroll documents track their viewport widths")
    @MainActor
    func vocabularyScrollDocumentsTrackViewportWidths() {
        let panel = VideoVocabularyPanel(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        let detail = VocabDetailContentView(frame: NSRect(x: 0, y: 0, width: 348, height: 480))
        panel.render(video: VideoItem(id: "video", url: "https://www.youtube.com/watch?v=video"), entries: [])
        detail.render(entry: nil, detail: nil, state: .loading)
        panel.layoutSubtreeIfNeeded()
        detail.layoutSubtreeIfNeeded()
        #expect(abs(panel.scrollDocumentWidth - panel.scrollViewportWidth) < 0.5)
        #expect(abs(detail.scrollDocumentWidth - detail.scrollViewportWidth) < 0.5)
    }

    @Test("Unconfigured translation plans preserve existing text and overrides")
    func unconfiguredTranslationDoesNotApplyCleanup() {
        let segment = SubtitleSegment(
            id: "s",
            start: 0,
            end: 1,
            original: "Hello",
            translation: "已有译文",
            zhUserOverride: "手工译文"
        )
        let document = TranscriptDocument(videoID: "video", sourceLanguage: "en", isGenerated: false, segments: [segment])
        let plan = TranslationStartPlan.make(
            document: document,
            scope: .all,
            apiKey: "",
            hasBackgroundCard: true,
            backgroundAttempted: true,
            clearExisting: true,
            clearUserOverrides: true
        )
        #expect(plan.readiness == .notConfigured)
        #expect(plan.shouldApplyCleanup == false)
        #expect(plan.applyingCleanup(to: document).segments == document.segments)
    }

    @Test("Floating shortcuts gloss on command-E and consume command-shift-E without detail")
    func floatingShortcutPolicy() {
        let command: NSEvent.ModifierFlags = [.command]
        let commandShift: NSEvent.ModifierFlags = [.command, .shift]
        #expect(VocabularyShortcutPolicy.action(key: "e", modifiers: command, allowsDetail: false) == .gloss)
        #expect(VocabularyShortcutPolicy.action(key: "e", modifiers: commandShift, allowsDetail: false) == .ignored)
        #expect(VocabularyShortcutPolicy.action(key: "e", modifiers: commandShift, allowsDetail: true) == .detail)
    }

    @Test("Selection context rejects same cue IDs from another video")
    func selectionContextIncludesVideoIdentity() {
        let first = VocabularySelectionContext(videoID: "video-a", segmentID: "cue-1", surface: "gossip")
        let second = VocabularySelectionContext(videoID: "video-b", segmentID: "cue-1", surface: "gossip")

        #expect(first.matches(videoID: "video-a", segmentID: "cue-1", surface: "gossip"))
        #expect(!first.matches(videoID: "video-b", segmentID: "cue-1", surface: "gossip"))
        #expect(!second.matches(videoID: "video-a", segmentID: "cue-1", surface: "gossip"))
    }

    @Test("Subtitle drafts survive reloads and remain visible in original mode")
    @MainActor
    func subtitleDraftSurvivesRepeatedConfigure() {
        var drafts = SubtitleDraftStore()
        drafts.update(videoID: "video-a", segmentID: "cue-1", text: "正在编辑的草稿")
        let segment = SubtitleSegment(id: "cue-1", start: 0, end: 1, original: "Hello", translation: "持久译文")
        let cell = SubtitleCell(frame: NSRect(x: 0, y: 0, width: 360, height: 140))

        cell.configure(segment, mode: .original, current: false, editing: true, draft: drafts.value(videoID: "video-a", segmentID: "cue-1"))
        cell.layoutSubtreeIfNeeded()
        #expect(cell.isEditorVisible)
        #expect(cell.editorText == "正在编辑的草稿")
        let editingHeight = SubtitleRowLayout.rowHeight(for: segment, mode: .original, availableWidth: 280, editing: true)
        let normalHeight = SubtitleRowLayout.rowHeight(for: segment, mode: .original, availableWidth: 280, editing: false)
        #expect(editingHeight > normalHeight)

        cell.configure(segment, mode: .original, current: false, editing: true, draft: drafts.value(videoID: "video-a", segmentID: "cue-1"))
        #expect(cell.editorText == "正在编辑的草稿")
    }

    @Test("Gloss content keeps entries while loading or failed")
    @MainActor
    func glossEntriesRemainWithTransientState() {
        let entry = GlossEntry(surface: "gossip", gloss: "八卦")
        let view = GlossInlineView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        view.entries = [entry]
        view.state = .loading
        let loadingHeight = view.height(for: 280)
        view.state = .failed("网络错误")
        let failedHeight = view.height(for: 280)
        view.state = .idle
        let entriesHeight = view.height(for: 280)

        #expect(view.entries == [entry])
        #expect(loadingHeight > entriesHeight)
        #expect(failedHeight > entriesHeight)
        #expect(loadingHeight > 24)
        #expect(failedHeight > 24)
    }

    @Test("Detail responses require the current presentation and request identity")
    func detailRequestIdentityGate() {
        let presentation = UUID()
        let firstRequest = UUID()
        let retryRequest = UUID()
        let identity = VocabDetailRequestIdentity(
            videoID: "video-a",
            segmentID: "cue-1",
            normalized: "gossip",
            presentationID: presentation,
            requestID: firstRequest
        )

        #expect(identity.matches(videoID: "video-a", segmentID: "cue-1", normalized: "gossip", presentationID: presentation, requestID: firstRequest))
        #expect(!identity.matches(videoID: "video-a", segmentID: "cue-1", normalized: "gossip", presentationID: presentation, requestID: retryRequest))
        #expect(!identity.matches(videoID: "video-b", segmentID: "cue-1", normalized: "gossip", presentationID: presentation, requestID: firstRequest))
        #expect(!identity.matches(videoID: "video-a", segmentID: "cue-1", normalized: "gossip", presentationID: UUID(), requestID: firstRequest))
    }

    @Test("Single click waits for double click before seeking")
    func singleClickWaitsForDoubleClick() {
        #expect(SubtitleInteractionPolicy.action(clickCount: 1, hasEligibleSelection: false) == .pendingSingleClick)
        #expect(SubtitleInteractionPolicy.cancelsPending(clickCount: 2, hasEligibleSelection: true))
        #expect(SubtitleInteractionPolicy.action(clickCount: 2, hasEligibleSelection: true) == .directGloss)
        #expect(SubtitleInteractionPolicy.action(clickCount: 1, hasEligibleSelection: true, isDragSelection: true) == .selectionToolbar)
    }

    @Test("Missing vocabulary configuration requests the translation settings page")
    func missingVocabularyConfigurationOpensSettings() {
        #expect(VocabularyLookupAvailabilityPolicy.decision(apiKey: "") == .openSettings)
        #expect(VocabularyLookupAvailabilityPolicy.decision(apiKey: "  \n") == .openSettings)
        #expect(VocabularyLookupAvailabilityPolicy.decision(apiKey: "configured") == .configured)
    }

    @Test("Missing vocabulary configuration targets the translation settings tab")
    func missingVocabularyConfigurationTargetsTranslationTab() {
        let firstTarget = VocabularyLookupAvailabilityPolicy.settingsTarget(apiKey: "")
        let laterTarget = VocabularyLookupAvailabilityPolicy.settingsTarget(apiKey: "")
        #expect(firstTarget == .translation)
        #expect(VocabularyLookupAvailabilityPolicy.settingsTarget(apiKey: "  \n") == .translation)
        #expect(VocabularyLookupAvailabilityPolicy.settingsTarget(apiKey: "configured") == nil)
        #expect(laterTarget == .translation)
    }

    @Test("Settings target policy preserves default settings behavior")
    func settingsTargetPolicyPreservesDefaultBehavior() {
        let targeted = SettingsPresentationPolicy.userInfo(for: .translation)
        #expect(SettingsPresentationPolicy.target(from: targeted) == .translation)
        #expect(SettingsPresentationPolicy.target(from: nil) == .defaultTab)
    }

    @Test("Cached detail hydrates the latest current subtitle translation exactly once")
    func cachedDetailHydratesLatestSourceExample() {
        let cachedSegment = SubtitleSegment(
            id: "cue-1",
            start: 12,
            end: 14,
            original: "From that day onwards.",
            translation: "旧译文"
        )
        let cached = VocabDetail(
            surface: "onwards",
            contextual: "继续向前",
            examples: [
                VocabExample(
                    sentence: cachedSegment.original,
                    translation: cachedSegment.effectiveTranslation,
                    timestamp: cachedSegment.start,
                    isSourceExample: true
                ),
                VocabExample(sentence: "The story continued onwards.")
            ]
        )
        var latestSegment = cachedSegment
        latestSegment.zhUserOverride = "最新手工译文"

        let hydrated = VocabDetailHydrationPolicy.hydrate(cached, with: latestSegment)
        let rehydrated = VocabDetailHydrationPolicy.hydrate(hydrated, with: latestSegment)

        #expect(hydrated.examples.first?.translation == "最新手工译文")
        #expect(hydrated.examples.filter(\.isSourceExample).count == 1)
        #expect(hydrated.examples.first?.timestamp == 12)
        #expect(rehydrated.examples.filter(\.isSourceExample).count == 1)
        #expect(rehydrated.examples.count == hydrated.examples.count)
    }

    @Test("Removing a gloss invalidates only its in-flight normalized job")
    func removingGlossInvalidatesOnlyMatchingJob() {
        let removedKey = GlossJobInvalidationPolicy.requestKey(
            videoID: "video-a",
            segmentID: "cue-1",
            normalized: "gossip"
        )
        let retainedKey = GlossJobInvalidationPolicy.requestKey(
            videoID: "video-a",
            segmentID: "cue-1",
            normalized: "judging"
        )
        let removedJob = UUID()
        let retainedJob = UUID()
        var jobs = [removedKey: removedJob, retainedKey: retainedJob]
        var errors = [removedKey: "旧错误", retainedKey: "另一个错误"]

        GlossJobInvalidationPolicy.invalidate(
            videoID: "video-a",
            segmentID: "cue-1",
            normalized: "gossip",
            jobs: &jobs,
            errors: &errors
        )

        #expect(jobs[removedKey] == nil)
        #expect(errors[removedKey] == nil)
        #expect(!GlossJobInvalidationPolicy.matches(
            videoID: "video-a",
            segmentID: "cue-1",
            normalized: "gossip",
            jobID: removedJob,
            jobs: jobs
        ))
        #expect(jobs[retainedKey] == retainedJob)
        #expect(errors[retainedKey] == "另一个错误")
    }

    @Test("Phrase details use the simplified whole-phrase policy")
    func phraseDetailPolicy() {
        #expect(VocabularyNormalization.isPhrase("give up"))
        #expect(VocabularyNormalization.isPhrase("  Take   off  "))
        #expect(!VocabularyNormalization.isPhrase("gossip"))
        #expect(VocabularyDetailPromptPolicy.kind(for: "give up") == .phrase)
        #expect(VocabularyDetailPromptPolicy.omitsFormsAndEtymology(for: "give up"))
        #expect(VocabularyDetailPromptPolicy.promptInstruction(for: "give up").contains("whole phrase"))
        #expect(!VocabularyDetailPromptPolicy.omitsFormsAndEtymology(for: "gossip"))
    }

    @Test("Wrapped gloss hit testing uses the actual glyph for each entry")
    @MainActor
    func wrappedGlossHitTestingUsesGlyphIdentity() {
        let first = GlossEntry(surface: "alpha", gloss: "a long contextual meaning that wraps")
        let second = GlossEntry(surface: "beta", gloss: "short meaning")
        let view = GlossInlineView(frame: NSRect(x: 0, y: 0, width: 220, height: 180))
        view.entries = [first, second]
        view.layoutSubtreeIfNeeded()

        #expect(view.renderedText.contains("a long contextual meaning that wraps  ×"))
        #expect(view.renderedText.contains("short meaning  ×"))
        #expect(view.entryLineFragmentCount(forEntryAt: 0) > 1)
        guard let firstRect = view.lastGlyphRect(forEntryAt: 0),
              let secondRect = view.lastGlyphRect(forEntryAt: 1) else {
            Issue.record("Expected glyph layout for both gloss entries")
            return
        }
        let firstPoint = NSPoint(x: firstRect.midX, y: firstRect.midY)
        let secondPoint = NSPoint(x: secondRect.midX, y: secondRect.midY)
        #expect(abs(firstRect.midY - secondRect.midY) < 0.5)
        #expect(view.entryIndex(at: firstPoint) == 0)
        #expect(view.entryIndex(at: secondPoint) == 1)
    }

    @Test("English contextual menu routes the current text view identity")
    @MainActor
    func selectableEnglishContextualMenuRoutesCurrentIdentity() {
        let text = SelectableEnglishTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        text.representedVideoID = "video-a"
        text.representedSegmentID = "cue-1"
        var receivedVideoID: String?
        var receivedSegmentID: String?
        var receivedSurface: String?
        text.onContextualGloss = { view, surface in
            receivedVideoID = view.representedVideoID
            receivedSegmentID = view.representedSegmentID
            receivedSurface = surface
        }

        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 4, y: 4),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
        text.configure(text: "First gossip", font: .systemFont(ofSize: 13), color: .white)
        text.setSelectedRange(NSRange(location: 6, length: 6))
        let menu = text.menu(for: event)
        let item = menu?.items.first(where: { $0.title == "讲解选词" })
        #expect(item?.isEnabled == true)
        if let action = item?.action, let target = item?.target as? NSObject {
            target.perform(action)
        }
        #expect(receivedVideoID == "video-a")
        #expect(receivedSegmentID == "cue-1")
        #expect(receivedSurface == "gossip")

        text.representedSegmentID = "cue-2"
        text.configure(text: "Second judging", font: .systemFont(ofSize: 13), color: .white)
        text.setSelectedRange(NSRange(location: 7, length: 7))
        let reusedItem = text.menu(for: event)?.items.first(where: { $0.title == "讲解选词" })
        #expect(reusedItem?.isEnabled == true)
        if let action = reusedItem?.action, let target = reusedItem?.target as? NSObject {
            target.perform(action)
        }
        #expect(receivedSegmentID == "cue-2")
        #expect(receivedSurface == "judging")

        text.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(text.selectedSurfaceText == nil)
        #expect(text.menu(for: event)?.items.first(where: { $0.title == "讲解选词" })?.isEnabled == false)
        text.configure(text: "中文", font: .systemFont(ofSize: 13), color: .white)
        text.setSelectedRange(NSRange(location: 0, length: 2))
        #expect(text.menu(for: event)?.items.first(where: { $0.title == "讲解选词" })?.isEnabled == false)
    }

    @Test("Ending or switching subtitle editing restores one active row")
    @MainActor
    func subtitleEditingStateRestoresRowHeightAndSingleTarget() {
        let segment = SubtitleSegment(id: "cue-1", start: 0, end: 1, original: "Hello", translation: "持久译文")
        let editingHeight = SubtitleRowLayout.rowHeight(for: segment, mode: .bilingual, availableWidth: 280, editing: true)
        let normalHeight = SubtitleRowLayout.rowHeight(for: segment, mode: .bilingual, availableWidth: 280, editing: false)
        #expect(editingHeight > normalHeight)

        var editing = SubtitleEditingState()
        editing.begin(videoID: "video-a", segmentID: "cue-1")
        #expect(editing.isEditing(videoID: "video-a", segmentID: "cue-1"))
        editing.begin(videoID: "video-a", segmentID: "cue-2")
        #expect(!editing.isEditing(videoID: "video-a", segmentID: "cue-1"))
        #expect(editing.isEditing(videoID: "video-a", segmentID: "cue-2"))
        editing.end()
        #expect(!editing.isEditing(videoID: "video-a", segmentID: "cue-2"))
    }

    @Test("Pinned overlay windows stay hidden until the user shows them")
    func pinnedOverlayDoesNotRaiseHiddenWindow() {
        #expect(OverlayWindowPresentation.shouldRaisePinnedWindow(isPinned: true, isVisible: true))
        #expect(!OverlayWindowPresentation.shouldRaisePinnedWindow(isPinned: true, isVisible: false))
        #expect(!OverlayWindowPresentation.shouldRaisePinnedWindow(isPinned: false, isVisible: true))
    }

    @Test("Background-card requests target a 1M-token context window")
    func backgroundCardPlannerUsesMillionTokenWindow() {
        #expect(BackgroundCardRequestPlanner.modelContextTokens == 1_000_000)
        #expect(BackgroundCardRequestPlanner.singlePassTokenBudget > 500_000)
        #expect(BackgroundCardRequestPlanner.estimatedTokens(characterCount: 4_000) == 1_000)
        #expect(BackgroundCardRequestPlanner.estimatedTokens(characterCount: 72_000) == 18_000)

        let short = (0..<8).map {
            SubtitleSegment(id: "s\($0)", start: Double($0), end: Double($0) + 1, original: "Hello there.")
        }
        let shortPlan = BackgroundCardRequestPlanner.plan(segments: short)
        #expect(shortPlan.chunks.count == 1)
        #expect(!shortPlan.disablesThinking)

        let sentence = String(repeating: "This is a spoken sentence from a long podcast episode. ", count: 20)
        let long = (0..<400).map {
            SubtitleSegment(id: "s\($0)", start: Double($0) * 5, end: Double($0) * 5 + 4, original: sentence)
        }
        let longPlan = BackgroundCardRequestPlanner.plan(segments: long)
        #expect(longPlan.chunks.count == 1)
        #expect(!longPlan.disablesThinking)
        #expect(longPlan.estimatedTokens < BackgroundCardRequestPlanner.singlePassTokenBudget)

        let forced = BackgroundCardRequestPlanner.plan(segments: long, forceChunked: true)
        #expect(forced.chunks.count == 2)
        #expect(forced.chunks.flatMap { $0 }.map(\.id) == long.map(\.id))

        let blob = String(repeating: "abcdefghij", count: 1_200)
        let huge = (0..<400).map {
            SubtitleSegment(id: "h\($0)", start: Double($0), end: Double($0) + 1, original: blob)
        }
        let hugePlan = BackgroundCardRequestPlanner.plan(segments: huge)
        #expect(hugePlan.estimatedTokens > BackgroundCardRequestPlanner.singlePassTokenBudget)
        #expect(hugePlan.chunks.count > 1)
        #expect(hugePlan.chunks.allSatisfy { !$0.isEmpty })
        #expect(hugePlan.chunks.flatMap { $0 }.map(\.id) == huge.map(\.id))
        #expect(hugePlan.chunks.allSatisfy {
            BackgroundCardRequestPlanner.encodedCharacterCount(for: $0) <= BackgroundCardRequestPlanner.chunkCharacterBudget
                || $0.count == 1
        })
    }

    @Test("Background-card context overflow and timeouts are retried by chunking")
    func backgroundCardRecoverableErrors() {
        let overflow = TranslationError.requestFailed(
            statusCode: 400,
            message: "This model's maximum context length is 128000 tokens",
            retryAfter: nil
        )
        #expect(BackgroundCardRequestPlanner.isContextOverflow(overflow))
        #expect(BackgroundCardRequestPlanner.isContextOverflow(
            TranslationError.requestFailed(statusCode: 413, message: "payload too large", retryAfter: nil)
        ))
        #expect(BackgroundCardRequestPlanner.isTimeout(URLError(.timedOut)))
        #expect(BackgroundCardRequestPlanner.isRecoverableByChunking(overflow))
        #expect(BackgroundCardRequestPlanner.isRecoverableByChunking(URLError(.timedOut)))
        #expect(!BackgroundCardRequestPlanner.isRecoverableByChunking(TranslationError.notConfigured))
    }

    @Test("Partial background cards merge into one chronological card")
    func backgroundCardMergerUnionsPartialAnalyses() {
        let first = VideoBackgroundCard(
            videoID: "video",
            overview: "上半场讨论产品。",
            chapters: [BackgroundChapter(start: 0, end: 60, title: "开场")],
            domain: "科技",
            tone: "访谈",
            entities: [BackgroundEntity(source: "Ada", preferredTranslation: "艾达", evidenceCueIDs: ["s0"])],
            terminology: [BackgroundTerm(source: "latency", preferredTranslation: "延迟", evidenceCueIDs: ["s1"])],
            uncertainties: [],
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: 10
        )
        let second = VideoBackgroundCard(
            videoID: "video",
            overview: "下半场讨论部署。",
            chapters: [BackgroundChapter(start: 90, end: 140, title: "部署")],
            domain: "",
            tone: "",
            entities: [BackgroundEntity(source: "Ada", preferredTranslation: "艾达", evidenceCueIDs: ["s9"])],
            terminology: [BackgroundTerm(source: "rollout", preferredTranslation: "放量", evidenceCueIDs: ["s11"])],
            uncertainties: [BackgroundUncertainty(cueID: "s12", note: "专有名词可能听写错误")],
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: 10
        )
        let merged = BackgroundCardMerger.merge([first, second], videoID: "video", segmentCount: 20)
        #expect(merged.overview.contains("上半场"))
        #expect(merged.overview.contains("下半场"))
        #expect(merged.chapters.map(\.title) == ["开场", "部署"])
        #expect(merged.domain == "科技")
        #expect(merged.entities.count == 1)
        #expect(Set(merged.entities[0].evidenceCueIDs) == ["s0", "s9"])
        #expect(merged.terminology.map(\.source).sorted() == ["latency", "rollout"])
        #expect(merged.sourceSegmentCount == 20)
    }

    @Test("Supadata placeholder titles are replaced with YouTube metadata")
    func youtubeMetadataFillsPlaceholderTitles() throws {
        #expect(YouTubePageMetadata.isPlaceholderTitle("YouTube 视频"))
        #expect(YouTubePageMetadata.isPlaceholderTitle("   "))
        #expect(!YouTubePageMetadata.isPlaceholderTitle("Lex Fridman Podcast #400"))
        #expect(YouTubePageMetadata.oEmbedURL(for: "dQw4w9WgXcQ").absoluteString.contains("dQw4w9WgXcQ"))

        let oEmbed = """
        {"title":"Never Gonna Give You Up","author_name":"Rick Astley","type":"video"}
        """.data(using: .utf8)!
        let snapshot = try #require(YouTubePageMetadata.parseOEmbed(data: oEmbed))
        #expect(snapshot.title == "Never Gonna Give You Up")
        #expect(snapshot.channel == "Rick Astley")

        let fetched = TranscriptFetchResult(
            document: TranscriptDocument(videoID: "dQw4w9WgXcQ", sourceLanguage: "en", isGenerated: false, segments: []),
            title: VideoItem.placeholderTitle,
            channel: VideoItem.placeholderChannel,
            duration: nil
        )
        #expect(fetched.needsMetadataEnrichment)
        let enriched = fetched.applying(snapshot)
        #expect(enriched.title == "Never Gonna Give You Up")
        #expect(enriched.channel == "Rick Astley")

        let html = """
        <html><head>
        <meta property="og:title" content="Episode 12: Deep Work">
        <link itemprop="name" content="Cal Newport">
        </head><body></body></html>
        """
        let page = YouTubePageMetadata.parseWatchPage(html)
        #expect(page.title == "Episode 12: Deep Work")
        #expect(page.channel == "Cal Newport")
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}

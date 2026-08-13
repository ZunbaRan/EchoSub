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
}

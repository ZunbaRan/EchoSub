import Foundation

enum SubtitleDisplayMode: Int, Codable, CaseIterable {
    case original
    case translated
    case bilingual
}

enum TranscriptStatus: String, Codable {
    case idle
    case loading
    case ready
    case translating
    case noSubtitles
    case failed

    var label: String {
        switch self {
        case .idle: return "待获取"
        case .loading: return "获取中"
        case .ready: return "双语"
        case .translating: return "翻译中"
        case .noSubtitles: return "无字幕"
        case .failed: return "失败"
        }
    }
}

enum TranscriptProvider: String, Codable {
    case youtube
    case ytDLP
    case supadata

    var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .ytDLP: return "yt-dlp"
        case .supadata: return "Supadata"
        }
    }
}

struct VideoItem: Codable, Identifiable, Equatable {
    let id: String
    var url: String
    var title: String
    var channel: String
    var thumbnailURL: String?
    var duration: Double?
    var progress: Double
    var status: TranscriptStatus
    var lastOpenedAt: Date

    init(id: String, url: String) {
        self.id = id
        self.url = url
        self.title = "YouTube 视频"
        self.channel = "YouTube"
        self.thumbnailURL = "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
        self.duration = nil
        self.progress = 0
        self.status = .idle
        self.lastOpenedAt = Date()
    }
}

struct RawCaptionCue: Equatable {
    var text: String
    var start: Double
    var duration: Double

    var end: Double { start + duration }
}

struct SubtitleSegment: Codable, Identifiable, Equatable {
    let id: String
    var start: Double
    var end: Double
    var original: String
    var translation: String?

    var duration: Double { max(0, end - start) }
}

struct TranscriptDocument: Codable, Equatable {
    var videoID: String
    var sourceLanguage: String
    var isGenerated: Bool
    var segments: [SubtitleSegment]
    var provider: TranscriptProvider? = nil
}

struct BackgroundChapter: Codable, Identifiable, Equatable {
    var id: String
    var start: Double
    var end: Double?
    var title: String

    init(id: String = UUID().uuidString, start: Double, end: Double? = nil, title: String) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
    }
}

struct BackgroundEntity: Codable, Identifiable, Equatable {
    var id: String
    var source: String
    var preferredTranslation: String
    var evidenceCueIDs: [String]

    init(id: String = UUID().uuidString, source: String, preferredTranslation: String, evidenceCueIDs: [String] = []) {
        self.id = id
        self.source = source
        self.preferredTranslation = preferredTranslation
        self.evidenceCueIDs = evidenceCueIDs
    }
}

struct BackgroundTerm: Codable, Identifiable, Equatable {
    var id: String
    var source: String
    var preferredTranslation: String
    var evidenceCueIDs: [String]

    init(id: String = UUID().uuidString, source: String, preferredTranslation: String, evidenceCueIDs: [String] = []) {
        self.id = id
        self.source = source
        self.preferredTranslation = preferredTranslation
        self.evidenceCueIDs = evidenceCueIDs
    }
}

struct BackgroundUncertainty: Codable, Identifiable, Equatable {
    var id: String
    var cueID: String
    var note: String

    init(id: String = UUID().uuidString, cueID: String, note: String) {
        self.id = id
        self.cueID = cueID
        self.note = note
    }
}

struct VideoBackgroundCard: Codable, Equatable {
    var videoID: String
    var overview: String
    var chapters: [BackgroundChapter]
    var domain: String
    var tone: String
    var entities: [BackgroundEntity]
    var terminology: [BackgroundTerm]
    var uncertainties: [BackgroundUncertainty]
    var generatedAt: Date
    var editedAt: Date?
    var sourceSegmentCount: Int

    var wasEdited: Bool { editedAt != nil }

    var translationContext: [String: Any] {
        [
            "overview": overview,
            "outline": chapters.map { [
                "start": formattedTime($0.start),
                "end": $0.end.map(formattedTime) ?? "",
                "title": $0.title,
            ] },
            "domain": domain,
            "tone": tone,
            "entities": entities.map { [
                "source": $0.source,
                "preferred_zh": $0.preferredTranslation,
            ] },
            "terminology": terminology.map { [
                "source": $0.source,
                "preferred_zh": $0.preferredTranslation,
            ] },
        ]
    }
}

struct AppLibrary: Codable {
    var videos: [VideoItem] = []
    var transcripts: [String: TranscriptDocument] = [:]
    var backgroundCards: [String: VideoBackgroundCard] = [:]

    init(
        videos: [VideoItem] = [],
        transcripts: [String: TranscriptDocument] = [:],
        backgroundCards: [String: VideoBackgroundCard] = [:]
    ) {
        self.videos = videos
        self.transcripts = transcripts
        self.backgroundCards = backgroundCards
    }

    private enum CodingKeys: String, CodingKey {
        case videos, transcripts, backgroundCards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videos = try container.decodeIfPresent([VideoItem].self, forKey: .videos) ?? []
        transcripts = try container.decodeIfPresent([String: TranscriptDocument].self, forKey: .transcripts) ?? [:]
        backgroundCards = try container.decodeIfPresent([String: VideoBackgroundCard].self, forKey: .backgroundCards) ?? [:]
    }
}

struct TranslationConfiguration: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

enum TranslationScope: Equatable {
    case missing
    case all
    case segment(String)
}

enum TranslationWorkPlan {
    static func segments(from document: TranscriptDocument, scope: TranslationScope) -> [SubtitleSegment] {
        switch scope {
        case .missing:
            return document.segments.filter { $0.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
        case .all:
            return document.segments
        case .segment(let id):
            return document.segments.filter { $0.id == id }
        }
    }

    static func unresolved(in batch: [SubtitleSegment], translations: [String: String]) -> [SubtitleSegment] {
        batch.filter {
            guard let value = translations[$0.id] else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func context(
        around targets: [SubtitleSegment],
        in document: TranscriptDocument,
        radius: Int = 2
    ) -> [SubtitleSegment] {
        let targetIDs = Set(targets.map(\.id))
        guard !targetIDs.isEmpty else { return [] }
        let safeRadius = max(0, radius)
        var included = IndexSet()
        for (index, segment) in document.segments.enumerated() where targetIDs.contains(segment.id) {
            let lower = max(0, index - safeRadius)
            let upper = min(document.segments.count - 1, index + safeRadius)
            included.insert(integersIn: lower...upper)
        }
        return included.map { document.segments[$0] }
    }
}

struct SubtitlePalette: Identifiable, Equatable {
    var id: String
    var name: String
    var englishColor: String
    var chineseColor: String

    static let presets: [SubtitlePalette] = [
        SubtitlePalette(id: "classic", name: "经典白 / 黄", englishColor: "#FFFFFF", chineseColor: "#FFD54F"),
        SubtitlePalette(id: "uniform-white", name: "统一高对比白", englishColor: "#FFFFFF", chineseColor: "#FFFFFF"),
        SubtitlePalette(id: "soft-cyan", name: "柔和白 / 青", englishColor: "#F7F7F7", chineseColor: "#7FDBFF"),
        SubtitlePalette(id: "warm", name: "暖白 / 橙", englishColor: "#FFF8E7", chineseColor: "#FFB74D"),
    ]

    static var defaultPalette: SubtitlePalette { presets[0] }
}

extension Notification.Name {
    static let echoLibraryChanged = Notification.Name("EchoSub.libraryChanged")
    static let echoCurrentVideoChanged = Notification.Name("EchoSub.currentVideoChanged")
    static let echoTranscriptChanged = Notification.Name("EchoSub.transcriptChanged")
    static let echoBackgroundCardChanged = Notification.Name("EchoSub.backgroundCardChanged")
    static let echoPlaybackTimeChanged = Notification.Name("EchoSub.playbackTimeChanged")
    static let echoSettingsChanged = Notification.Name("EchoSub.settingsChanged")
    static let echoToggleFloatingWindow = Notification.Name("EchoSub.toggleFloatingWindow")
    static let echoToggleLyricsWindow = Notification.Name("EchoSub.toggleLyricsWindow")
    static let echoOpenSettings = Notification.Name("EchoSub.openSettings")
    static let echoSeekRequested = Notification.Name("EchoSub.seekRequested")
}

func formattedTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "00:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3_600
    let minutes = (total % 3_600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}

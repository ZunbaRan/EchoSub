import Foundation

final class AppState {
    static let shared = AppState()

    private let store = LibraryStore()
    private let transcriptService = YouTubeTranscriptService()
    private let translationService = TranslationService()
    private(set) var library: AppLibrary
    private(set) var currentVideoID: String?
    private(set) var playbackTime: Double = 0
    private(set) var lastErrorMessage: String?
    private var translationJobID: UUID?
    private var backgroundCardJobs: [String: UUID] = [:]
    private var backgroundCardErrors: [String: String] = [:]
    private var backgroundCardCompletions: [String: [(VideoBackgroundCard?) -> Void]] = [:]

    private init() {
        library = store.load()
        currentVideoID = library.visibleVideos.first?.id
    }

    var currentVideo: VideoItem? {
        guard let currentVideoID else { return nil }
        return library.videos.first { $0.id == currentVideoID }
    }

    var visibleVideos: [VideoItem] { library.visibleVideos }
    var hiddenVideos: [VideoItem] { library.hiddenVideos }

    var currentTranscript: TranscriptDocument? {
        guard let currentVideoID else { return nil }
        return library.transcripts[currentVideoID]
    }

    var currentBackgroundCard: VideoBackgroundCard? {
        guard let currentVideoID else { return nil }
        return library.backgroundCards[currentVideoID]
    }

    var isCurrentBackgroundCardGenerating: Bool {
        guard let currentVideoID else { return false }
        return backgroundCardJobs[currentVideoID] != nil
    }

    var currentBackgroundCardError: String? {
        guard let currentVideoID else { return nil }
        return backgroundCardErrors[currentVideoID]
    }

    var currentSegment: SubtitleSegment? {
        guard let segments = currentTranscript?.segments, !segments.isEmpty else { return nil }
        return segments.last(where: { $0.start <= playbackTime }) ?? segments.first
    }

    @discardableResult
    func addVideo(from input: String) -> Result<VideoItem, Error> {
        guard let videoID = YouTubeURLParser.videoID(from: input) else {
            return .failure(NSError(domain: "EchoSub", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法识别这个 YouTube 链接。"] ))
        }
        if let existing = library.videos.first(where: { $0.id == videoID }) {
            if library.hiddenVideoIDs.contains(videoID) {
                library.unhideVideo(videoID)
                persist()
                NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
            }
            selectVideo(videoID)
            return .success(existing)
        }
        var video = VideoItem(id: videoID, url: YouTubeURLParser.canonicalURL(for: videoID))
        video.status = .loading
        library.videos.insert(video, at: 0)
        currentVideoID = videoID
        playbackTime = 0
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
        fetchTranscript(for: videoID)
        return .success(video)
    }

    func selectVideo(_ videoID: String) {
        guard library.videos.contains(where: { $0.id == videoID }) else { return }
        saveCurrentProgress()
        currentVideoID = videoID
        playbackTime = library.videos.first(where: { $0.id == videoID })?.progress ?? 0
        lastErrorMessage = nil
        NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
        if library.transcripts[videoID] == nil { fetchTranscript(for: videoID) }
    }

    func playVideoFromBeginning(_ videoID: String) {
        guard let index = library.videos.firstIndex(where: { $0.id == videoID }) else { return }
        library.videos[index].progress = 0
        persist()
        selectVideo(videoID)
    }

    func removeVideo(_ videoID: String) {
        if currentVideoID == videoID { translationJobID = nil }
        library.deleteVideo(videoID)
        backgroundCardJobs[videoID] = nil
        backgroundCardErrors[videoID] = nil
        backgroundCardCompletions[videoID] = nil
        if currentVideoID == videoID {
            currentVideoID = library.visibleVideos.first?.id
            playbackTime = currentVideo?.progress ?? 0
            NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
        }
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
    }

    func hideVideo(_ videoID: String) {
        library.hideVideo(videoID)
        if currentVideoID == videoID {
            currentVideoID = library.visibleVideos.first?.id
            playbackTime = currentVideo?.progress ?? 0
            NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
            NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
        }
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
    }

    func unhideVideo(_ videoID: String) {
        library.unhideVideo(videoID)
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
    }

    func updatePlaybackTime(_ time: Double) {
        playbackTime = max(0, time)
        NotificationCenter.default.post(name: .echoPlaybackTimeChanged, object: nil)
    }

    func saveCurrentProgress() {
        guard let currentVideoID, let index = library.videos.firstIndex(where: { $0.id == currentVideoID }) else { return }
        library.videos[index].progress = playbackTime
        library.videos[index].lastOpenedAt = Date()
        persist()
    }

    func retryTranscript() {
        guard let currentVideoID else { return }
        fetchTranscript(for: currentVideoID)
    }

    var missingTranslationCount: Int {
        guard let document = currentTranscript else { return 0 }
        return TranslationWorkPlan.segments(from: document, scope: .missing).count
    }

    func translateMissing() { startTranslation(scope: .missing) }

    func retranslateAll() { startTranslation(scope: .all, clearExisting: true) }

    func translateSegment(id: String) { startTranslation(scope: .segment(id)) }

    func regenerateBackgroundCard(preservingUserTerms: Bool = false) {
        let previous = currentBackgroundCard
        requestBackgroundCard(force: true) { [weak self] generated in
            guard preservingUserTerms,
                  let self,
                  let previous,
                  previous.wasEdited,
                  var generated else { return }
            generated.entities = previous.entities
            generated.terminology = previous.terminology
            self.saveBackgroundCard(generated)
        }
    }

    func saveBackgroundCard(_ card: VideoBackgroundCard) {
        guard card.videoID == currentVideoID else { return }
        var edited = card
        edited.editedAt = Date()
        library.backgroundCards[card.videoID] = edited
        backgroundCardErrors[card.videoID] = nil
        persist()
        NotificationCenter.default.post(name: .echoBackgroundCardChanged, object: nil)
    }

    private func startTranslation(
        scope: TranslationScope,
        clearExisting: Bool = false,
        backgroundAttempted: Bool = false
    ) {
        guard let video = currentVideo, var document = currentTranscript else { return }
        let work = TranslationWorkPlan.segments(from: document, scope: scope)
        guard !work.isEmpty else { return }
        let config = AppSettings.shared.translationConfiguration
        guard !config.apiKey.isEmpty else {
            lastErrorMessage = TranslationError.notConfigured.localizedDescription
            NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
            return
        }
        if library.backgroundCards[video.id] == nil, !backgroundAttempted {
            requestBackgroundCard(force: false) { [weak self] _ in
                self?.startTranslation(scope: scope, clearExisting: clearExisting, backgroundAttempted: true)
            }
            return
        }
        if clearExisting {
            for index in document.segments.indices { document.segments[index].translation = nil }
            library.transcripts[video.id] = document
            persist()
            NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
        }
        let jobID = UUID()
        translationJobID = jobID
        lastErrorMessage = nil
        updateStatus(video.id, .translating)
        translateQueue(work, video: video, configuration: config, jobID: jobID, failedIDs: [])
    }

    func clearTranscriptCache() {
        library.transcripts.removeAll()
        library.backgroundCards.removeAll()
        backgroundCardJobs.removeAll()
        backgroundCardErrors.removeAll()
        backgroundCardCompletions.removeAll()
        for index in library.videos.indices { library.videos[index].status = .idle }
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
    }

    func clearAllHistory() {
        library = AppLibrary()
        backgroundCardJobs.removeAll()
        backgroundCardErrors.removeAll()
        backgroundCardCompletions.removeAll()
        currentVideoID = nil
        playbackTime = 0
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
    }

    private func fetchTranscript(for videoID: String) {
        updateStatus(videoID, .loading)
        lastErrorMessage = nil
        transcriptService.fetch(videoID: videoID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.lastErrorMessage = error.localizedDescription
                    let status: TranscriptStatus
                    if let transcriptError = error as? TranscriptServiceError,
                       case .noSubtitles = transcriptError {
                        status = .noSubtitles
                    } else {
                        status = .failed
                    }
                    self.updateStatus(videoID, status)
                case .success(let fetched):
                    self.library.backgroundCards[videoID] = nil
                    self.backgroundCardErrors[videoID] = nil
                    self.library.transcripts[videoID] = fetched.document
                    if let index = self.library.videos.firstIndex(where: { $0.id == videoID }) {
                        self.library.videos[index].title = fetched.title
                        self.library.videos[index].channel = fetched.channel
                        self.library.videos[index].duration = fetched.duration
                        self.library.videos[index].status = .ready
                    }
                    self.persist()
                    NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
                    if self.currentVideoID == videoID {
                        NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
                    }
                    NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
                    if !AppSettings.shared.translationConfiguration.apiKey.isEmpty, self.currentVideoID == videoID {
                        self.translateMissing()
                    }
                }
            }
        }
    }

    private func translateQueue(
        _ remaining: [SubtitleSegment],
        video: VideoItem,
        configuration: TranslationConfiguration,
        jobID: UUID,
        failedIDs: Set<String>
    ) {
        guard translationJobID == jobID else { return }
        guard !remaining.isEmpty else {
            translationJobID = nil
            let missing = library.transcripts[video.id].map { TranslationWorkPlan.segments(from: $0, scope: .missing).count } ?? 0
            if missing > 0 || !failedIDs.isEmpty {
                lastErrorMessage = "仍有 \(missing) 句未翻译，可用“补全翻译”或右键单句重试。"
            } else {
                lastErrorMessage = nil
            }
            updateStatus(video.id, .ready)
            return
        }
        let batch = Array(remaining.prefix(24))
        let tail = Array(remaining.dropFirst(batch.count))
        translateBatch(batch, tail: tail, attempt: 0, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs)
    }

    private func translateBatch(
        _ batch: [SubtitleSegment],
        tail: [SubtitleSegment],
        attempt: Int,
        video: VideoItem,
        configuration: TranslationConfiguration,
        jobID: UUID,
        failedIDs: Set<String>
    ) {
        guard translationJobID == jobID else { return }
        guard let document = library.transcripts[video.id] else { return }
        let context = TranslationWorkPlan.context(around: batch, in: document, radius: 4)
        let backgroundCard = library.backgroundCards[video.id]
        translationService.translate(
            segments: batch,
            context: context,
            videoTitle: video.title,
            backgroundCard: backgroundCard,
            configuration: configuration
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.translationJobID == jobID else { return }
                switch result {
                case .failure(let error):
                    if attempt < 2 {
                        self.translateBatch(batch, tail: tail, attempt: attempt + 1, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs)
                    } else {
                        self.lastErrorMessage = error.localizedDescription
                        self.translateQueue(tail, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs.union(batch.map(\.id)))
                    }
                case .success(let translations):
                    guard var document = self.library.transcripts[video.id] else { return }
                    for index in document.segments.indices {
                        if let translated = translations[document.segments[index].id] {
                            document.segments[index].translation = translated
                        }
                    }
                    self.library.transcripts[video.id] = document
                    self.persist()
                    NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
                    let unresolved = TranslationWorkPlan.unresolved(in: batch, translations: translations)
                    if !unresolved.isEmpty, attempt < 2 {
                        self.translateBatch(unresolved, tail: tail, attempt: attempt + 1, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs)
                    } else {
                        self.translateQueue(tail, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs.union(unresolved.map(\.id)))
                    }
                }
            }
        }
    }

    private func updateStatus(_ videoID: String, _ status: TranscriptStatus) {
        if let index = library.videos.firstIndex(where: { $0.id == videoID }) {
            library.videos[index].status = status
            persist()
        }
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
    }

    private func requestBackgroundCard(
        force: Bool,
        completion: ((VideoBackgroundCard?) -> Void)?
    ) {
        guard let video = currentVideo, let document = currentTranscript else {
            completion?(nil)
            return
        }
        if !force, let existing = library.backgroundCards[video.id] {
            completion?(existing)
            return
        }
        if let completion {
            backgroundCardCompletions[video.id, default: []].append(completion)
        }
        if backgroundCardJobs[video.id] != nil { return }

        let configuration = AppSettings.shared.translationConfiguration
        guard !configuration.apiKey.isEmpty else {
            backgroundCardErrors[video.id] = TranslationError.notConfigured.localizedDescription
            let completions = backgroundCardCompletions.removeValue(forKey: video.id) ?? []
            completions.forEach { $0(nil) }
            NotificationCenter.default.post(name: .echoBackgroundCardChanged, object: nil)
            return
        }

        let jobID = UUID()
        backgroundCardJobs[video.id] = jobID
        backgroundCardErrors[video.id] = nil
        NotificationCenter.default.post(name: .echoBackgroundCardChanged, object: nil)
        translationService.generateBackgroundCard(
            document: document,
            video: video,
            configuration: configuration
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.backgroundCardJobs[video.id] == jobID else { return }
                self.backgroundCardJobs[video.id] = nil
                var resultCard: VideoBackgroundCard?
                switch result {
                case .success(let card):
                    self.library.backgroundCards[video.id] = card
                    self.backgroundCardErrors[video.id] = nil
                    self.persist()
                    resultCard = card
                case .failure(let error):
                    self.backgroundCardErrors[video.id] = error.localizedDescription
                }
                NotificationCenter.default.post(name: .echoBackgroundCardChanged, object: nil)
                let completions = self.backgroundCardCompletions.removeValue(forKey: video.id) ?? []
                completions.forEach { $0(resultCard) }
            }
        }
    }

    private func persist() { store.save(library) }
}

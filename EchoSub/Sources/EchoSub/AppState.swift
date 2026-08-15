import Foundation

final class AppState {
    static let shared = AppState()

    private let store = LibraryStore()
    private let transcriptService = YouTubeTranscriptService()
    let translationService = TranslationService()
    let diagnostics = DiagnosticLogger.shared
    var library: AppLibrary
    private(set) var currentVideoID: String?
    private(set) var playbackTime: Double = 0
    private(set) var lastErrorMessage: String?
    private var translationJobs = TranslationJobRegistry()
    private var backgroundCardJobs: [String: UUID] = [:]
    private var backgroundCardErrors: [String: String] = [:]
    private var backgroundCardCompletions: [String: [(VideoBackgroundCard?) -> Void]] = [:]
    var glossJobs: [String: UUID] = [:]
    var glossErrors: [String: String] = [:]
    var detailJobs: [String: UUID] = [:]
    var detailErrors: [String: String] = [:]
    var detailCompletions: [String: [(Result<VocabDetail, Error>) -> Void]] = [:]

    private init() {
        library = store.load()
        let interruptedVideoIDs = library.recoverInterruptedOperations()
        if !interruptedVideoIDs.isEmpty {
            store.save(library)
            diagnostics.record("translation.jobs.recovered_after_restart", fields: [
                "video_ids": interruptedVideoIDs.joined(separator: ","),
                "count": String(interruptedVideoIDs.count),
            ])
        }
        currentVideoID = library.visibleVideos.first?.id
        diagnostics.record("app.started", fields: [
            "videos": String(library.videos.count),
            "recovered_jobs": String(interruptedVideoIDs.count),
        ])
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
        translationJobs.cancel(videoID: videoID)
        glossJobs = glossJobs.filter { !$0.key.hasPrefix("\(videoID)|") }
        glossErrors = glossErrors.filter { !$0.key.hasPrefix("\(videoID)|") }
        detailJobs = detailJobs.filter { !$0.key.hasPrefix("\(videoID)|") }
        detailErrors = detailErrors.filter { !$0.key.hasPrefix("\(videoID)|") }
        detailCompletions = detailCompletions.filter { !$0.key.hasPrefix("\(videoID)|") }
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
        NotificationCenter.default.post(name: .echoVocabularyChanged, object: nil)
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

    func translateMissing() {
        guard let currentVideoID else { return }
        startTranslation(videoID: currentVideoID, scope: .missing)
    }

    func retranslateAll() {
        guard let currentVideoID else { return }
        startTranslation(videoID: currentVideoID, scope: .all, clearExisting: true, clearUserOverrides: true)
    }

    func translateSegment(id: String) {
        guard let currentVideoID else { return }
        startTranslation(videoID: currentVideoID, scope: .segment(id), clearUserOverrides: true)
    }

    func regenerateBackgroundCard(preservingUserTerms: Bool = false) {
        guard let videoID = currentVideoID else { return }
        let previous = currentBackgroundCard
        requestBackgroundCard(videoID: videoID, force: true) { [weak self] generated in
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
        videoID: String,
        scope: TranslationScope,
        clearExisting: Bool = false,
        clearUserOverrides: Bool = false,
        backgroundAttempted: Bool = false
    ) {
        guard let video = library.videos.first(where: { $0.id == videoID }),
              let originalDocument = library.transcripts[videoID] else { return }
        let config = AppSettings.shared.translationConfiguration
        let plan = TranslationStartPlan.make(
            document: originalDocument,
            scope: scope,
            apiKey: config.apiKey,
            hasBackgroundCard: library.backgroundCards[video.id] != nil,
            backgroundAttempted: backgroundAttempted,
            clearExisting: clearExisting,
            clearUserOverrides: clearUserOverrides
        )
        var document = originalDocument
        if plan.shouldApplyCleanup {
            document = plan.applyingCleanup(to: document)
            library.transcripts[video.id] = document
            persist()
            NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
            if plan.clearUserOverrides {
                NotificationCenter.default.post(name: .echoVocabularyChanged, object: nil)
            }
        }
        let work = plan.work
        guard !work.isEmpty else { return }
        guard plan.readiness != .notConfigured else {
            lastErrorMessage = TranslationError.notConfigured.localizedDescription
            NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
            return
        }
        if plan.readiness == .waitingForBackgroundCard {
            requestBackgroundCard(videoID: video.id, force: false) { [weak self] _ in
                self?.startTranslation(videoID: video.id, scope: scope, clearExisting: clearExisting, clearUserOverrides: clearUserOverrides, backgroundAttempted: true)
            }
            return
        }
        let jobID = UUID()
        if let previousJobID = translationJobs.jobID(for: video.id) {
            diagnostics.record("translation.job.replaced_for_same_video", fields: [
                "previous_job_id": previousJobID.uuidString,
                "new_job_id": jobID.uuidString,
                "video_id": video.id,
            ])
        }
        translationJobs.start(videoID: video.id, jobID: jobID)
        lastErrorMessage = nil
        diagnostics.record("translation.job.started", fields: [
            "job_id": jobID.uuidString,
            "video_id": video.id,
            "scope": String(describing: scope),
            "work_count": String(work.count),
            "total_segments": String(document.segments.count),
            "already_translated": String(document.segments.count - TranslationWorkPlan.segments(from: document, scope: .missing).count),
            "model": config.model,
            "endpoint_host": URL(string: config.baseURL)?.host ?? "invalid",
            "thinking_mode": TranslationRequestPolicy.thinkingMode(model: config.model, purpose: .translation).map(String.init) ?? "provider_default",
            "batch_size": String(TranslationRequestPolicy.batchSize),
            "timeout_seconds": String(Int(TranslationRequestPolicy.translationTimeout)),
        ])
        updateStatus(video.id, .translating)
        translateQueue(work, video: video, configuration: config, jobID: jobID, failedIDs: [])
    }

    func clearTranscriptCache() {
        library.transcripts.removeAll()
        library.backgroundCards.removeAll()
        library.detailCache.removeAll()
        backgroundCardJobs.removeAll()
        backgroundCardErrors.removeAll()
        backgroundCardCompletions.removeAll()
        glossJobs.removeAll()
        glossErrors.removeAll()
        detailJobs.removeAll()
        detailErrors.removeAll()
        detailCompletions.removeAll()
        translationJobs.cancelAll()
        for index in library.videos.indices { library.videos[index].status = .idle }
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
        NotificationCenter.default.post(name: .echoVocabularyChanged, object: nil)
    }

    func clearAllHistory() {
        library = AppLibrary()
        backgroundCardJobs.removeAll()
        backgroundCardErrors.removeAll()
        backgroundCardCompletions.removeAll()
        glossJobs.removeAll()
        glossErrors.removeAll()
        detailJobs.removeAll()
        detailErrors.removeAll()
        translationJobs.cancelAll()
        currentVideoID = nil
        playbackTime = 0
        persist()
        NotificationCenter.default.post(name: .echoLibraryChanged, object: nil)
        NotificationCenter.default.post(name: .echoCurrentVideoChanged, object: nil)
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
        NotificationCenter.default.post(name: .echoVocabularyChanged, object: nil)
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
        guard translationJobs.matches(videoID: video.id, jobID: jobID) else {
            diagnostics.record("translation.job.stale_queue_ignored", fields: ["job_id": jobID.uuidString, "video_id": video.id])
            return
        }
        guard !remaining.isEmpty else {
            translationJobs.finish(videoID: video.id, jobID: jobID)
            let missing = library.transcripts[video.id].map { TranslationWorkPlan.segments(from: $0, scope: .missing).count } ?? 0
            if missing > 0 || !failedIDs.isEmpty {
                lastErrorMessage = "仍有 \(missing) 句未翻译，可用“补全翻译”或右键单句重试。"
            } else {
                lastErrorMessage = nil
            }
            updateStatus(video.id, .ready)
            diagnostics.record("translation.job.finished", fields: [
                "job_id": jobID.uuidString,
                "video_id": video.id,
                "missing_count": String(missing),
                "failed_count": String(failedIDs.count),
            ])
            return
        }
        let batch = Array(remaining.prefix(TranslationRequestPolicy.batchSize))
        let tail = Array(remaining.dropFirst(batch.count))
        diagnostics.record("translation.batch.queued", fields: [
            "job_id": jobID.uuidString,
            "video_id": video.id,
            "batch_count": String(batch.count),
            "remaining_after_batch": String(tail.count),
            "first_cue_id": batch.first?.id ?? "",
            "last_cue_id": batch.last?.id ?? "",
        ])
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
        guard translationJobs.matches(videoID: video.id, jobID: jobID) else {
            diagnostics.record("translation.batch.stale_before_request", fields: ["job_id": jobID.uuidString, "video_id": video.id])
            return
        }
        guard let document = library.transcripts[video.id] else {
            diagnostics.record("translation.batch.transcript_missing", fields: ["job_id": jobID.uuidString, "video_id": video.id])
            return
        }
        let context = TranslationWorkPlan.context(around: batch, in: document, radius: 4)
        let backgroundCard = library.backgroundCards[video.id]
        let requestID = UUID()
        let startedAt = Date()
        diagnostics.record("translation.request.started", fields: [
            "job_id": jobID.uuidString,
            "request_id": requestID.uuidString,
            "video_id": video.id,
            "attempt": String(attempt + 1),
            "target_count": String(batch.count),
            "context_count": String(context.count),
            "first_cue_id": batch.first?.id ?? "",
            "last_cue_id": batch.last?.id ?? "",
        ])
        translationService.translate(
            segments: batch,
            context: context,
            videoTitle: video.title,
            backgroundCard: backgroundCard,
            configuration: configuration
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
                guard self.translationJobs.matches(videoID: video.id, jobID: jobID) else {
                    self.diagnostics.record("translation.request.stale_response_ignored", fields: [
                        "job_id": jobID.uuidString,
                        "request_id": requestID.uuidString,
                        "video_id": video.id,
                        "elapsed_ms": String(elapsedMS),
                    ])
                    return
                }
                switch result {
                case .failure(let error):
                    self.diagnostics.record("translation.request.failed", fields: [
                        "job_id": jobID.uuidString,
                        "request_id": requestID.uuidString,
                        "video_id": video.id,
                        "attempt": String(attempt + 1),
                        "elapsed_ms": String(elapsedMS),
                        "error_type": String(reflecting: type(of: error)),
                        "error": error.localizedDescription,
                    ])
                    let failedAttempt = attempt + 1
                    if let delay = TranslationRetryPolicy.delay(afterFailedAttempt: failedAttempt, error: error) {
                        self.diagnostics.record("translation.request.retry_scheduled", fields: [
                            "job_id": jobID.uuidString,
                            "request_id": requestID.uuidString,
                            "video_id": video.id,
                            "failed_attempt": String(failedAttempt),
                            "delay_seconds": String(format: "%.1f", delay),
                        ])
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self,
                                  self.translationJobs.matches(videoID: video.id, jobID: jobID) else { return }
                            self.translateBatch(batch, tail: tail, attempt: attempt + 1, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs)
                        }
                    } else {
                        if self.currentVideoID == video.id { self.lastErrorMessage = error.localizedDescription }
                        self.diagnostics.record("translation.batch.skipped_after_retries", fields: [
                            "job_id": jobID.uuidString,
                            "video_id": video.id,
                            "attempts": String(failedAttempt),
                            "skipped_count": String(batch.count),
                            "skipped_ids": batch.map(\.id).joined(separator: ","),
                        ])
                        self.translateQueue(tail, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs.union(batch.map(\.id)))
                    }
                case .success(let translations):
                    self.diagnostics.record("translation.request.succeeded", fields: [
                        "job_id": jobID.uuidString,
                        "request_id": requestID.uuidString,
                        "video_id": video.id,
                        "attempt": String(attempt + 1),
                        "elapsed_ms": String(elapsedMS),
                        "requested_count": String(batch.count),
                        "translated_count": String(translations.count),
                    ])
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
                    if !unresolved.isEmpty {
                        self.diagnostics.record("translation.batch.partial_response", fields: [
                            "job_id": jobID.uuidString,
                            "request_id": requestID.uuidString,
                            "video_id": video.id,
                            "unresolved_count": String(unresolved.count),
                            "unresolved_ids": unresolved.map(\.id).joined(separator: ","),
                        ])
                    }
                    if !unresolved.isEmpty,
                       let delay = TranslationRetryPolicy.delay(afterFailedAttempt: attempt + 1, error: TranslationError.malformedResponse) {
                        self.diagnostics.record("translation.partial_response.retry_scheduled", fields: [
                            "job_id": jobID.uuidString,
                            "video_id": video.id,
                            "failed_attempt": String(attempt + 1),
                            "delay_seconds": String(format: "%.1f", delay),
                            "unresolved_count": String(unresolved.count),
                        ])
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self,
                                  self.translationJobs.matches(videoID: video.id, jobID: jobID) else { return }
                            self.translateBatch(unresolved, tail: tail, attempt: attempt + 1, video: video, configuration: configuration, jobID: jobID, failedIDs: failedIDs)
                        }
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
        videoID: String,
        force: Bool,
        completion: ((VideoBackgroundCard?) -> Void)?
    ) {
        guard let video = library.videos.first(where: { $0.id == videoID }),
              let document = library.transcripts[videoID] else {
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

    func persist() { store.save(library) }
}

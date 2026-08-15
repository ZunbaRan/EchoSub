import Foundation

extension AppState {
    var currentVocabularyCount: Int {
        vocabularyEntries(for: currentVideoID).count
    }

    var currentVocabularyEntries: [VocabularySummaryEntry] {
        vocabularyEntries(for: currentVideoID)
    }

    func vocabularyEntries(for videoID: String?) -> [VocabularySummaryEntry] {
        guard let videoID, let document = library.transcripts[videoID] else { return [] }
        return document.segments.flatMap { segment in
            segment.glosses.map {
                VocabularySummaryEntry(
                    videoID: videoID,
                    segmentID: segment.id,
                    gloss: $0,
                    timestamp: segment.start,
                    sourceSentence: segment.original
                )
            }
        }
    }

    func glossEntries(for segmentID: String, videoID: String? = nil) -> [GlossEntry] {
        guard let videoID = videoID ?? currentVideoID,
              let segment = library.transcripts[videoID]?.segments.first(where: { $0.id == segmentID }) else { return [] }
        return segment.glosses
    }

    func glossState(surface: String, segmentID: String, videoID: String? = nil) -> GlossLookupState {
        guard let videoID = videoID ?? currentVideoID else { return .idle }
        let key = vocabularyRequestKey(videoID: videoID, segmentID: segmentID, normalized: VocabularyNormalization.normalizedTerm(surface))
        if glossJobs[key] != nil { return .loading }
        if let error = glossErrors[key] { return .failed(error) }
        return .idle
    }

    func glossState(for segmentID: String, videoID: String? = nil) -> GlossLookupState {
        guard let videoID = videoID ?? currentVideoID else { return .idle }
        let prefix = "\(videoID)|\(segmentID)|"
        if glossJobs.keys.contains(where: { $0.hasPrefix(prefix) }) { return .loading }
        if let key = glossErrors.keys.first(where: { $0.hasPrefix(prefix) }), let error = glossErrors[key] {
            return .failed(error)
        }
        return .idle
    }

    func retryableGlossSurface(for segmentID: String, videoID: String? = nil) -> String? {
        guard let videoID = videoID ?? currentVideoID else { return nil }
        let prefix = "\(videoID)|\(segmentID)|"
        return glossErrors.keys.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count).description
    }

    func detailState(for entry: GlossEntry, segmentID: String, videoID: String? = nil) -> VocabDetailState {
        guard let videoID = videoID ?? currentVideoID else { return .idle }
        let key = vocabularyRequestKey(videoID: videoID, segmentID: segmentID, normalized: entry.normalized)
        if detailJobs[key] != nil { return .loading }
        if let error = detailErrors[key] { return .failed(error) }
        return .idle
    }

    func lookupGloss(
        surface: String,
        in segmentID: String,
        videoID: String? = nil,
        completion: ((Result<GlossEntry, Error>) -> Void)? = nil
    ) {
        lookupGloss(surface: surface, segmentID: segmentID, videoID: videoID, completion: completion)
    }

    func lookupGloss(
        surface: String,
        segmentID: String,
        videoID: String? = nil,
        completion: ((Result<GlossEntry, Error>) -> Void)? = nil
    ) {
        guard let videoID = videoID ?? currentVideoID,
              let video = library.videos.first(where: { $0.id == videoID }),
              let document = library.transcripts[videoID],
              let segment = document.segments.first(where: { $0.id == segmentID }) else {
            completion?(.failure(TranslationError.malformedResponse))
            return
        }
        let normalized = VocabularyNormalization.normalizedTerm(surface)
        guard VocabularyNormalization.isEligibleSurface(surface), !normalized.isEmpty else {
            completion?(.failure(TranslationError.malformedResponse))
            return
        }
        let requestKey = vocabularyRequestKey(videoID: videoID, segmentID: segmentID, normalized: normalized)
        if glossJobs[requestKey] != nil { return }
        let configuration = AppSettings.shared.translationConfiguration
        if let settingsTarget = VocabularyLookupAvailabilityPolicy.settingsTarget(apiKey: configuration.apiKey) {
            glossErrors[requestKey] = TranslationError.notConfigured.localizedDescription
            diagnostics.record("vocabulary.gloss.request.failed", fields: [
                "request_id": UUID().uuidString,
                "video_id": videoID,
                "subtitle_id": segmentID,
                "normalized": normalized,
                "error_type": String(reflecting: TranslationError.notConfigured),
                "error": TranslationError.notConfigured.localizedDescription,
            ])
            postVocabularyChanged()
            requestVocabularySettingsIfNeeded(target: settingsTarget)
            completion?(.failure(TranslationError.notConfigured))
            return
        }
        let jobID = UUID()
        glossJobs[requestKey] = jobID
        glossErrors[requestKey] = nil
        postVocabularyChanged()
        let context = TranslationWorkPlan.context(around: [segment], in: document, radius: 4)
        let requestID = UUID()
        let startedAt = Date()
        diagnostics.record("vocabulary.gloss.request.started", fields: [
            "request_id": requestID.uuidString,
            "video_id": videoID,
            "subtitle_id": segmentID,
            "normalized": normalized,
            "context_count": String(context.count),
            "endpoint_host": URL(string: configuration.baseURL)?.host ?? "invalid",
            "model": configuration.model,
        ])
        translationService.lookupGloss(
            surface: surface,
            segment: segment,
            context: context,
            videoTitle: video.title,
            backgroundCard: library.backgroundCards[videoID],
            configuration: configuration
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.glossJobs[requestKey] == jobID else { return }
                self.glossJobs[requestKey] = nil
                let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
                switch result {
                case .failure(let error):
                    self.glossErrors[requestKey] = error.localizedDescription
                    self.diagnostics.record("vocabulary.gloss.request.failed", fields: [
                        "request_id": requestID.uuidString,
                        "video_id": videoID,
                        "subtitle_id": segmentID,
                        "normalized": normalized,
                        "elapsed_ms": String(elapsedMS),
                        "error_type": String(reflecting: type(of: error)),
                        "error": error.localizedDescription,
                    ])
                    self.postVocabularyChanged()
                    completion?(.failure(error))
                case .success(let generated):
                    guard var document = self.library.transcripts[videoID],
                          let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
                        completion?(.failure(TranslationError.malformedResponse))
                        return
                    }
                    let existingIndex = document.segments[index].glosses.firstIndex { $0.normalized == normalized }
                    let previous = existingIndex.map { document.segments[index].glosses[$0] }
                    var entry = generated
                    entry.id = previous?.id ?? entry.id
                    entry.surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
                    entry.normalized = normalized
                    entry.createdAt = previous?.createdAt ?? entry.createdAt
                    entry.detailCacheKey = VocabDetailCacheKey.make(
                        normalizedTerm: normalized,
                        videoID: videoID,
                        subtitleID: segmentID
                    )
                    if let existingIndex {
                        document.segments[index].glosses[existingIndex] = entry
                    } else {
                        document.segments[index].glosses.append(entry)
                    }
                    self.library.transcripts[videoID] = document
                    self.glossErrors[requestKey] = nil
                    self.persist()
                    self.diagnostics.record("vocabulary.gloss.request.succeeded", fields: [
                        "request_id": requestID.uuidString,
                        "video_id": videoID,
                        "subtitle_id": segmentID,
                        "normalized": normalized,
                        "elapsed_ms": String(elapsedMS),
                        "updated_existing": String(existingIndex != nil),
                    ])
                    self.postVocabularyChanged()
                    completion?(.success(entry))
                }
            }
        }
    }

    func retryGloss(
        surface: String,
        in segmentID: String,
        videoID: String? = nil,
        completion: ((Result<GlossEntry, Error>) -> Void)? = nil
    ) {
        let resolvedVideoID = videoID ?? currentVideoID
        if let resolvedVideoID {
            let key = vocabularyRequestKey(videoID: resolvedVideoID, segmentID: segmentID, normalized: VocabularyNormalization.normalizedTerm(surface))
            glossErrors[key] = nil
        }
        lookupGloss(surface: surface, segmentID: segmentID, videoID: videoID, completion: completion)
    }

    func retryGloss(
        surface: String,
        segmentID: String,
        videoID: String? = nil,
        completion: ((Result<GlossEntry, Error>) -> Void)? = nil
    ) {
        retryGloss(surface: surface, in: segmentID, videoID: videoID, completion: completion)
    }

    @discardableResult
    func removeGloss(id: String, from segmentID: String, videoID: String? = nil) -> Bool {
        guard let videoID = videoID ?? currentVideoID,
              var document = library.transcripts[videoID],
              let segmentIndex = document.segments.firstIndex(where: { $0.id == segmentID }),
              let glossIndex = document.segments[segmentIndex].glosses.firstIndex(where: { $0.id == id }) else { return false }
        let removed = document.segments[segmentIndex].glosses[glossIndex]
        GlossJobInvalidationPolicy.invalidate(
            videoID: videoID,
            segmentID: segmentID,
            normalized: removed.normalized,
            jobs: &glossJobs,
            errors: &glossErrors
        )
        document.segments[segmentIndex].glosses.remove(at: glossIndex)
        library.transcripts[videoID] = document
        persist()
        diagnostics.record("vocabulary.gloss.removed", fields: [
            "video_id": videoID,
            "subtitle_id": segmentID,
            "normalized": removed.normalized,
        ])
        postVocabularyChanged()
        return true
    }

    @discardableResult
    func removeGloss(surface: String, from segmentID: String, videoID: String? = nil) -> Bool {
        guard let entry = glossEntries(for: segmentID, videoID: videoID).first(where: { $0.normalized == VocabularyNormalization.normalizedTerm(surface) }) else { return false }
        return removeGloss(id: entry.id, from: segmentID, videoID: videoID)
    }

    @discardableResult
    func removeGloss(id: String, segmentID: String, videoID: String? = nil) -> Bool {
        removeGloss(id: id, from: segmentID, videoID: videoID)
    }

    func cachedVocabDetail(for entry: GlossEntry, segmentID: String, videoID: String? = nil) -> VocabDetail? {
        guard let videoID = videoID ?? currentVideoID else { return nil }
        let key = VocabDetailCacheKey.make(
            normalizedTerm: entry.normalized,
            videoID: videoID,
            subtitleID: segmentID
        )
        guard let detail = library.detailCache[key] else { return nil }
        return hydratedDetail(detail, videoID: videoID, segmentID: segmentID)
    }

    func detailCacheValue(normalized: String, videoID: String, subtitleID: String) -> VocabDetail? {
        let key = VocabDetailCacheKey.make(normalizedTerm: normalized, videoID: videoID, subtitleID: subtitleID)
        guard let detail = library.detailCache[key] else { return nil }
        return hydratedDetail(detail, videoID: videoID, segmentID: subtitleID)
    }

    func cachedDetail(normalized: String, videoID: String, subtitleID: String) -> VocabDetail? {
        detailCacheValue(normalized: normalized, videoID: videoID, subtitleID: subtitleID)
    }

    func lookupDetail(
        for entry: GlossEntry,
        in segmentID: String,
        videoID: String? = nil,
        completion: ((Result<VocabDetail, Error>) -> Void)? = nil
    ) {
        lookupDetail(surface: entry.surface, normalized: entry.normalized, pos: entry.pos, in: segmentID, videoID: videoID, completion: completion)
    }

    func lookupVocabDetail(
        for entry: GlossEntry,
        in segmentID: String,
        videoID: String? = nil,
        completion: ((Result<VocabDetail, Error>) -> Void)? = nil
    ) {
        lookupDetail(for: entry, in: segmentID, videoID: videoID, completion: completion)
    }

    func lookupDetail(
        surface: String,
        normalized: String? = nil,
        pos: String? = nil,
        in segmentID: String,
        videoID: String? = nil,
        completion: ((Result<VocabDetail, Error>) -> Void)? = nil
    ) {
        guard let videoID = videoID ?? currentVideoID,
              let video = library.videos.first(where: { $0.id == videoID }),
              let document = library.transcripts[videoID],
              let segment = document.segments.first(where: { $0.id == segmentID }) else {
            completion?(.failure(TranslationError.malformedResponse))
            return
        }
        let normalized = VocabularyNormalization.normalizedTerm(normalized ?? surface)
        guard VocabularyNormalization.isEligibleSurface(surface), !normalized.isEmpty else {
            completion?(.failure(TranslationError.malformedResponse))
            return
        }
        let cacheKey = VocabDetailCacheKey.make(normalizedTerm: normalized, videoID: videoID, subtitleID: segmentID)
        if let cached = library.detailCache[cacheKey] {
            diagnostics.record("vocabulary.detail.cache.hit", fields: [
                "video_id": videoID,
                "subtitle_id": segmentID,
                "normalized": normalized,
            ])
            detailErrors[vocabularyRequestKey(videoID: videoID, segmentID: segmentID, normalized: normalized)] = nil
            completion?(.success(hydratedDetail(cached, videoID: videoID, segmentID: segmentID, fallback: segment)))
            if VocabularyDetailRefreshPolicy.shouldPostVocabularyChangedAfterCacheHit() {
                postVocabularyChanged()
            }
            return
        }
        let configuration = AppSettings.shared.translationConfiguration
        let requestKey = vocabularyRequestKey(videoID: videoID, segmentID: segmentID, normalized: normalized)
        if let settingsTarget = VocabularyLookupAvailabilityPolicy.settingsTarget(apiKey: configuration.apiKey) {
            detailErrors[requestKey] = TranslationError.notConfigured.localizedDescription
            diagnostics.record("vocabulary.detail.request.failed", fields: [
                "request_id": UUID().uuidString,
                "video_id": videoID,
                "subtitle_id": segmentID,
                "normalized": normalized,
                "error_type": String(reflecting: TranslationError.notConfigured),
                "error": TranslationError.notConfigured.localizedDescription,
            ])
            postVocabularyChanged()
            requestVocabularySettingsIfNeeded(target: settingsTarget)
            completion?(.failure(TranslationError.notConfigured))
            return
        }
        if detailJobs[requestKey] != nil {
            if let completion {
                detailCompletions[requestKey, default: []].append(completion)
            }
            return
        }
        let jobID = UUID()
        detailJobs[requestKey] = jobID
        detailCompletions[requestKey] = completion.map { [$0] } ?? []
        detailErrors[requestKey] = nil
        postVocabularyChanged()
        let context = TranslationWorkPlan.context(around: [segment], in: document, radius: 4)
        let requestID = UUID()
        let startedAt = Date()
        diagnostics.record("vocabulary.detail.request.started", fields: [
            "request_id": requestID.uuidString,
            "video_id": videoID,
            "subtitle_id": segmentID,
            "normalized": normalized,
            "context_count": String(context.count),
            "endpoint_host": URL(string: configuration.baseURL)?.host ?? "invalid",
            "model": configuration.model,
        ])
        let entry = GlossEntry(surface: surface, normalized: normalized, gloss: "", pos: pos, detailCacheKey: cacheKey)
        translationService.lookupDetail(
            entry: entry,
            segment: segment,
            context: context,
            videoTitle: video.title,
            backgroundCard: library.backgroundCards[videoID],
            configuration: configuration
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.detailJobs[requestKey] == jobID else { return }
                self.detailJobs[requestKey] = nil
                let completions = self.detailCompletions.removeValue(forKey: requestKey) ?? []
                let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
                switch result {
                case .failure(let error):
                    self.detailErrors[requestKey] = error.localizedDescription
                    self.diagnostics.record("vocabulary.detail.request.failed", fields: [
                        "request_id": requestID.uuidString,
                        "video_id": videoID,
                        "subtitle_id": segmentID,
                        "normalized": normalized,
                        "elapsed_ms": String(elapsedMS),
                        "error_type": String(reflecting: type(of: error)),
                        "error": error.localizedDescription,
                    ])
                    self.postVocabularyChanged()
                    completions.forEach { $0(.failure(error)) }
                case .success(let value):
                    var detail = value
                    detail.surface = detail.surface.isEmpty ? surface : detail.surface
                    detail.normalized = normalized
                    detail.pos = detail.pos ?? pos
                    detail = self.hydratedDetail(detail, videoID: videoID, segmentID: segmentID, fallback: segment)
                    self.library.detailCache[cacheKey] = detail
                    self.detailErrors[requestKey] = nil
                    self.persist()
                    self.diagnostics.record("vocabulary.detail.request.succeeded", fields: [
                        "request_id": requestID.uuidString,
                        "video_id": videoID,
                        "subtitle_id": segmentID,
                        "normalized": normalized,
                        "elapsed_ms": String(elapsedMS),
                    ])
                    self.postVocabularyChanged()
                    completions.forEach { $0(.success(detail)) }
                }
            }
        }
    }

    func retryDetail(for entry: GlossEntry, in segmentID: String, videoID: String? = nil, completion: ((Result<VocabDetail, Error>) -> Void)? = nil) {
        let resolvedVideoID = videoID ?? currentVideoID
        if let resolvedVideoID {
            let key = vocabularyRequestKey(videoID: resolvedVideoID, segmentID: segmentID, normalized: entry.normalized)
            detailErrors[key] = nil
        }
        lookupDetail(for: entry, in: segmentID, videoID: videoID, completion: completion)
    }

    @discardableResult
    func saveChineseOverride(for segmentID: String, text: String, videoID: String? = nil) -> Bool {
        guard let videoID = videoID ?? currentVideoID,
              var document = library.transcripts[videoID],
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else { return false }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        document.segments[index].zhUserOverride = value.isEmpty ? nil : value
        library.transcripts[videoID] = document
        persist()
        diagnostics.record("vocabulary.translation_override.saved", fields: [
            "video_id": videoID,
            "subtitle_id": segmentID,
            "is_empty": String(value.isEmpty),
        ])
        NotificationCenter.default.post(name: .echoTranscriptChanged, object: nil)
        postVocabularyChanged()
        return true
    }

    @discardableResult
    func saveTranslationOverride(segmentID: String, text: String, videoID: String? = nil) -> Bool {
        saveChineseOverride(for: segmentID, text: text, videoID: videoID)
    }

    @discardableResult
    func saveChineseTranslationOverride(segmentID: String, text: String, videoID: String? = nil) -> Bool {
        saveChineseOverride(for: segmentID, text: text, videoID: videoID)
    }

    func cancelChineseOverrideEditing(for segmentID: String, videoID: String? = nil) -> String? {
        guard let videoID = videoID ?? currentVideoID else { return nil }
        return library.transcripts[videoID]?.segments.first(where: { $0.id == segmentID })?.effectiveTranslation
    }

    func cancelTranslationOverride(for segmentID: String, videoID: String? = nil) -> String? {
        cancelChineseOverrideEditing(for: segmentID, videoID: videoID)
    }

    @discardableResult
    func clearChineseOverride(for segmentID: String, videoID: String? = nil) -> Bool {
        saveChineseOverride(for: segmentID, text: "", videoID: videoID)
    }

    private func vocabularyRequestKey(videoID: String, segmentID: String, normalized: String) -> String {
        GlossJobInvalidationPolicy.requestKey(videoID: videoID, segmentID: segmentID, normalized: normalized)
    }

    private func hydratedDetail(
        _ detail: VocabDetail,
        videoID: String,
        segmentID: String,
        fallback: SubtitleSegment? = nil
    ) -> VocabDetail {
        let latestSegment = library.transcripts[videoID]?.segments.first(where: { $0.id == segmentID }) ?? fallback
        guard let latestSegment else { return detail }
        return VocabDetailHydrationPolicy.hydrate(detail, with: latestSegment)
    }

    private func requestVocabularySettingsIfNeeded(target: SettingsPresentationTarget) {
        NotificationCenter.default.post(
            name: .echoOpenSettings,
            object: nil,
            userInfo: SettingsPresentationPolicy.userInfo(for: target)
        )
    }

    private func postVocabularyChanged() {
        NotificationCenter.default.post(name: .echoVocabularyChanged, object: nil)
    }
}

private extension Array where Element == GlossEntry {
    subscript(safeVocabulary index: Int) -> GlossEntry? {
        indices.contains(index) ? self[index] : nil
    }
}

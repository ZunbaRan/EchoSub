import Foundation

struct VocabularyGlossResponse: Equatable {
    var surface: String
    var normalized: String
    var contextualGloss: String
    var pos: String?
}

extension TranslationService {
    func lookupGloss(
        surface: String,
        segment: SubtitleSegment,
        context: [SubtitleSegment],
        videoTitle: String,
        backgroundCard: VideoBackgroundCard? = nil,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<GlossEntry, Error>) -> Void
    ) {
        guard !configuration.apiKey.isEmpty else {
            completion(.failure(TranslationError.notConfigured))
            return
        }
        guard let url = vocabularyEndpoint(configuration: configuration) else {
            completion(.failure(TranslationError.invalidEndpoint))
            return
        }
        let normalized = VocabularyNormalization.normalizedTerm(surface)
        guard VocabularyNormalization.isEligibleSurface(surface), !normalized.isEmpty else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        let source = makeVocabularySource(
            surface: surface,
            segment: segment,
            context: context,
            videoTitle: videoTitle,
            backgroundCard: backgroundCard
        )
        guard let sourceJSON = jsonString(source) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }
        let system = """
        You are a concise contextual English vocabulary assistant. Explain the selected word or phrase in the current subtitle sentence, not its first dictionary meaning. Return only compact valid JSON with exactly this shape: {"surface":"selected surface","normalized":"lowercase normalized form","pos":"short part of speech or empty string","contextual_gloss":"short Simplified Chinese contextual meaning"}. Keep the gloss short enough for an inline subtitle annotation. Do not include markdown, thinking, or extra keys.
        """
        var payload: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": sourceJSON],
            ],
        ]
        TranslationRequestPolicy.applyThinkingMode(to: &payload, model: configuration.model, purpose: .gloss)
        performVocabularyRequest(
            payload: payload,
            url: url,
            configuration: configuration,
            timeout: 45,
            purpose: .gloss
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let content):
                guard let response = Self.parseGlossResponse(content),
                      VocabularyNormalization.isEligibleSurface(response.surface),
                      !response.contextualGloss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(TranslationError.malformedResponse))
                    return
                }
                completion(.success(GlossEntry(
                    surface: response.surface,
                    normalized: response.normalized.isEmpty ? normalized : response.normalized,
                    gloss: response.contextualGloss,
                    pos: response.pos
                )))
            }
        }
    }

    func lookupDetail(
        entry: GlossEntry,
        segment: SubtitleSegment,
        context: [SubtitleSegment],
        videoTitle: String,
        backgroundCard: VideoBackgroundCard? = nil,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<VocabDetail, Error>) -> Void
    ) {
        lookupDetail(
            surface: entry.surface,
            normalized: entry.normalized,
            pos: entry.pos,
            segment: segment,
            context: context,
            videoTitle: videoTitle,
            backgroundCard: backgroundCard,
            configuration: configuration,
            completion: completion
        )
    }

    func lookupVocabDetail(
        entry: GlossEntry,
        segment: SubtitleSegment,
        context: [SubtitleSegment],
        videoTitle: String,
        backgroundCard: VideoBackgroundCard? = nil,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<VocabDetail, Error>) -> Void
    ) {
        lookupDetail(
            entry: entry,
            segment: segment,
            context: context,
            videoTitle: videoTitle,
            backgroundCard: backgroundCard,
            configuration: configuration,
            completion: completion
        )
    }

    func lookupDetail(
        surface: String,
        normalized: String? = nil,
        pos: String? = nil,
        segment: SubtitleSegment,
        context: [SubtitleSegment],
        videoTitle: String,
        backgroundCard: VideoBackgroundCard? = nil,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<VocabDetail, Error>) -> Void
    ) {
        guard !configuration.apiKey.isEmpty else {
            completion(.failure(TranslationError.notConfigured))
            return
        }
        guard let url = vocabularyEndpoint(configuration: configuration) else {
            completion(.failure(TranslationError.invalidEndpoint))
            return
        }
        let cleanSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNormalized = VocabularyNormalization.normalizedTerm(normalized ?? cleanSurface)
        guard VocabularyNormalization.isEligibleSurface(cleanSurface), !cleanNormalized.isEmpty else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        let source = makeVocabularySource(
            surface: cleanSurface,
            segment: segment,
            context: context,
            videoTitle: videoTitle,
            backgroundCard: backgroundCard
        )
        guard let sourceJSON = jsonString(source) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }
        let phraseInstruction = VocabularyDetailPromptPolicy.promptInstruction(for: cleanSurface)
        let system = """
        You are a careful English vocabulary teacher. Explain the selected word or phrase in the current subtitle context. Return only valid JSON with these keys: surface, normalized, pos, phonetic, contextual_meaning, forms, explanation, etymology, memory, cognates, synonyms, antonyms, phrases, examples. forms is an array of {"label":"...","value":"...","translation":"..."}; cognates, synonyms, and antonyms are arrays of {"word":"...","translation":"...","pos":"..."}; phrases is an array of {"phrase":"...","translation":"...","note":"..."}; examples is an array of {"sentence":"...","translation":"..."}. Keep absent fields empty or omit them. Contextual meaning must be specific to the supplied current sentence. The current subtitle sentence must be represented by the caller as the first source example; add useful AI examples after it. \(phraseInstruction) Do not include markdown or commentary outside JSON.
        """
        var payload: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": sourceJSON],
            ],
        ]
        TranslationRequestPolicy.applyThinkingMode(to: &payload, model: configuration.model, purpose: .detail)
        performVocabularyRequest(
            payload: payload,
            url: url,
            configuration: configuration,
            timeout: 120,
            purpose: .detail
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let content):
                guard var detail = Self.parseDetailResponse(content) else {
                    completion(.failure(TranslationError.malformedResponse))
                    return
                }
                if detail.surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { detail.surface = cleanSurface }
                detail.normalized = cleanNormalized
                if detail.pos == nil { detail.pos = pos }
                if VocabularyDetailPromptPolicy.omitsFormsAndEtymology(for: cleanSurface) {
                    detail.forms = []
                    detail.etymology = ""
                }
                guard !detail.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(TranslationError.malformedResponse))
                    return
                }
                completion(.success(detail.withSourceExample(segment)))
            }
        }
    }

    static func parseGlossResponse(_ text: String) -> VocabularyGlossResponse? {
        guard let object = jsonObject(from: text) else { return nil }
        let surface = (object["surface"] as? String ?? object["word"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = VocabularyNormalization.normalizedTerm(object["normalized"] as? String ?? surface)
        let gloss = (object["contextual_gloss"] as? String
            ?? object["contextualGloss"] as? String
            ?? object["gloss"] as? String
            ?? object["meaning"] as? String
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pos = (object["pos"] as? String ?? object["part_of_speech"] as? String)
            .flatMap { value in value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value }
        guard VocabularyNormalization.isEligibleSurface(surface), !gloss.isEmpty else { return nil }
        return VocabularyGlossResponse(surface: surface, normalized: normalized, contextualGloss: gloss, pos: pos)
    }

    static func parseDetailResponse(_ text: String) -> VocabDetail? {
        guard let data = extractVocabularyJSON(from: text).data(using: .utf8) else { return nil }
        if let detail = try? JSONDecoder().decode(VocabDetail.self, from: data),
           !detail.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return detail }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nested = object["detail"] as? [String: Any],
              let nestedData = try? JSONSerialization.data(withJSONObject: nested) else { return nil }
        guard let detail = try? JSONDecoder().decode(VocabDetail.self, from: nestedData),
              !detail.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return detail
    }

    private func vocabularyEndpoint(configuration: TranslationConfiguration) -> URL? {
        let base = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/chat/completions")
    }

    private func makeVocabularySource(
        surface: String,
        segment: SubtitleSegment,
        context: [SubtitleSegment],
        videoTitle: String,
        backgroundCard: VideoBackgroundCard?
    ) -> [String: Any] {
        var source: [String: Any] = [
            "video_title": videoTitle,
            "selected_surface": surface,
            "current_segment": [
                "id": segment.id,
                "start": segment.start,
                "end": segment.end,
                "text": segment.original,
                "translation": segment.effectiveTranslation ?? "",
            ],
            "context_segments": context.map { item in
                [
                    "id": item.id,
                    "start": item.start,
                    "end": item.end,
                    "text": item.original,
                    "translation": item.effectiveTranslation ?? "",
                ]
            },
        ]
        if let backgroundCard { source["video_background_card"] = backgroundCard.translationContext }
        return source
    }

    private func jsonString(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private func performVocabularyRequest(
        payload: [String: Any],
        url: URL,
        configuration: TranslationConfiguration,
        timeout: TimeInterval,
        purpose: TranslationRequestPurpose,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = timeout
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                completion(.failure(TranslationError.requestFailed(
                    statusCode: http.statusCode,
                    message: message ?? "词汇请求失败（\(http.statusCode)）。",
                    retryAfter: nil
                )))
                return
            }
            guard let envelope = try? JSONDecoder().decode(VocabularyChatEnvelope.self, from: data),
                  let content = envelope.choices.first?.message.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            _ = purpose
            completion(.success(content))
        }.resume()
    }
}

private struct VocabularyChatEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message
    }
    var choices: [Choice]
}

private extension TranslationService {
    static func extractVocabularyJSON(from text: String) -> String {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else { return text }
        return String(text[first...last])
    }

    static func jsonObject(from text: String) -> [String: Any]? {
        let json = extractVocabularyJSON(from: text)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

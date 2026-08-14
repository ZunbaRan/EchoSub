import Foundation

enum TranslationError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case requestFailed(statusCode: Int, message: String, retryAfter: TimeInterval?)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在设置中配置翻译 API Key。"
        case .invalidEndpoint: return "翻译服务地址无效。"
        case .requestFailed(_, let message, _): return message
        case .malformedResponse: return "翻译服务返回了无法识别的结果。"
        }
    }
}

enum TranslationRetryPolicy {
    static let maximumAttempts = 3

    static func delay(afterFailedAttempt attempt: Int, error: Error) -> TimeInterval? {
        guard attempt < maximumAttempts else { return nil }
        let fallback: TimeInterval = attempt == 1 ? 5 : 15
        if case TranslationError.requestFailed(_, _, let retryAfter) = error, let retryAfter {
            return max(fallback, retryAfter)
        }
        return fallback
    }
}

enum TranslationRequestPurpose {
    case translation
    case backgroundCard
}

enum TranslationRequestPolicy {
    static let batchSize = 12
    static let translationTimeout: TimeInterval = 120
    static let backgroundCardTimeout: TimeInterval = 180

    static func thinkingMode(model: String, purpose: TranslationRequestPurpose) -> Bool? {
        let normalized = model.lowercased()
        let supportsExplicitThinking = normalized.contains("qwen3") || normalized.contains("deepseek-v4")
        guard supportsExplicitThinking else { return nil }
        switch purpose {
        case .translation: return false
        case .backgroundCard: return true
        }
    }

    static func applyThinkingMode(
        to payload: inout [String: Any],
        model: String,
        purpose: TranslationRequestPurpose
    ) {
        guard let enabled = thinkingMode(model: model, purpose: purpose) else { return }
        payload["enable_thinking"] = enabled
        if enabled {
            // DashScope rejects JSON mode while thinking is enabled. The prompt
            // and response decoder still enforce the background-card schema.
            payload["response_format"] = nil
        }
    }
}

final class TranslationService {
    func translate(
        segments: [SubtitleSegment],
        context: [SubtitleSegment],
        videoTitle: String,
        backgroundCard: VideoBackgroundCard? = nil,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        guard !configuration.apiKey.isEmpty else {
            completion(.failure(TranslationError.notConfigured))
            return
        }
        let base = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            completion(.failure(TranslationError.invalidEndpoint))
            return
        }

        let targets = segments.map { ["id": $0.id, "text": $0.original] }
        let targetIDs = Set(segments.map(\.id))
        let contextRows = context.map { segment -> [String: String] in
            var row = ["id": segment.id, "text": segment.original]
            if !targetIDs.contains(segment.id),
               let translation = segment.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translation.isEmpty {
                row["existing_translation"] = translation
            }
            return row
        }
        var source: [String: Any] = [
            "context_segments": contextRows,
            "target_segments": targets,
        ]
        if let backgroundCard {
            source["video_background_card"] = backgroundCard.translationContext
        }
        let sourceData = try? JSONSerialization.data(withJSONObject: source)
        let sourceJSON = sourceData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let system = """
        You are a professional subtitle translator. Translate every target segment into natural, modern Simplified Chinese.
        The video is titled \"\(videoTitle)\". Read context_segments in order to resolve pronouns, incomplete thoughts, terminology, and tone. video_background_card, when present, is a concise analysis of the complete source transcript. Use it for global topic, named entities, terminology, and tone, but never invent information from it. The target source text has highest authority, followed by neighboring source context, then the background card. Existing translations are terminology references only. Translate only target_segments. Preserve proper nouns and common technical terms when natural. Do not merge, split, omit, or reorder target segments.
        Return only valid JSON with exactly this shape: {\"segments\":[{\"id\":\"unchanged-id\",\"text\":\"translated text\"}]}.
        Copy every target id exactly and translate only target text values. Never return context-only ids.
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
        TranslationRequestPolicy.applyThinkingMode(
            to: &payload,
            model: configuration.model,
            purpose: .translation
        )
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = TranslationRequestPolicy.translationTimeout

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DiagnosticLogger.shared.record("translation.http.transport_error", fields: [
                    "model": configuration.model,
                    "endpoint_host": url.host ?? "",
                    "error_type": String(reflecting: type(of: error)),
                    "error": error.localizedDescription,
                ])
                return completion(.failure(error))
            }
            guard let http = response as? HTTPURLResponse, let data else {
                DiagnosticLogger.shared.record("translation.http.missing_response", fields: [
                    "model": configuration.model,
                    "endpoint_host": url.host ?? "",
                ])
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            DiagnosticLogger.shared.record("translation.http.response_received", fields: [
                "model": configuration.model,
                "endpoint_host": url.host ?? "",
                "status_code": String(http.statusCode),
                "response_bytes": String(data.count),
            ])
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                let retryAfter = Self.retryAfter(from: http)
                completion(.failure(TranslationError.requestFailed(
                    statusCode: http.statusCode,
                    message: message ?? "翻译请求失败（\(http.statusCode)）。",
                    retryAfter: retryAfter
                )))
                return
            }
            guard let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data),
                  let content = envelope.choices.first?.message.content,
                  let jsonData = Self.extractJSON(from: content).data(using: .utf8),
                  let translated = try? JSONDecoder().decode(TranslatedBatch.self, from: jsonData) else {
                DiagnosticLogger.shared.record("translation.http.response_decode_failed", fields: [
                    "model": configuration.model,
                    "endpoint_host": url.host ?? "",
                    "status_code": String(http.statusCode),
                    "response_bytes": String(data.count),
                ])
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            let validIDs = Set(segments.map(\.id))
            let pairs: [(String, String)] = translated.segments.compactMap { item in
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard validIDs.contains(item.id), !text.isEmpty else { return nil }
                return (item.id, text)
            }
            let mapping = Dictionary<String, String>(uniqueKeysWithValues: pairs)
            completion(mapping.isEmpty ? .failure(TranslationError.malformedResponse) : .success(mapping))
        }.resume()
    }

    func generateBackgroundCard(
        document: TranscriptDocument,
        video: VideoItem,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<VideoBackgroundCard, Error>) -> Void
    ) {
        guard !configuration.apiKey.isEmpty else {
            completion(.failure(TranslationError.notConfigured))
            return
        }
        let base = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            completion(.failure(TranslationError.invalidEndpoint))
            return
        }

        let transcript = document.segments.map { segment -> [String: Any] in
            [
                "id": segment.id,
                "start": segment.start,
                "end": segment.end,
                "text": segment.original,
            ]
        }
        var videoInfo: [String: Any] = [
            "id": video.id,
            "title": video.title,
            "channel": video.channel,
        ]
        if let duration = video.duration { videoInfo["duration"] = duration }
        guard let sourceData = try? JSONSerialization.data(withJSONObject: [
            "video": videoInfo,
            "source_language": document.sourceLanguage,
            "complete_transcript": transcript,
        ]), let sourceJSON = String(data: sourceData, encoding: .utf8) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        let system = """
        You analyze a COMPLETE video transcript before subtitle translation. Read every cue and return a concise, evidence-grounded background card in Simplified Chinese.
        The overview must cover the whole video's topic progression in 5-8 sentences, not only the opening. Do not invent facts. Chapters must be chronological and use numeric seconds from the supplied cue timestamps. Entities and terminology must include only useful recurring items, with exact source spelling, preferred Simplified Chinese, and evidence cue IDs that really contain the item. Flag only plausible ASR or source ambiguities.
        Return only valid JSON with exactly these top-level keys:
        {"overview":"...","chapters":[{"start":0,"end":120,"title":"..."}],"domain":"...","tone":"...","entities":[{"source":"...","preferred_zh":"...","evidence_ids":["cue-id"]}],"terminology":[{"source":"...","preferred_zh":"...","evidence_ids":["cue-id"]}],"uncertainties":[{"cue_id":"cue-id","note":"..."}]}.
        Keep the entire result compact. The overview and card are reference context, never a license to add content absent from a subtitle line.
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
        TranslationRequestPolicy.applyThinkingMode(
            to: &payload,
            model: configuration.model,
            purpose: .backgroundCard
        )
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = TranslationRequestPolicy.backgroundCardTimeout

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { return completion(.failure(error)) }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                completion(.failure(TranslationError.requestFailed(
                    statusCode: http.statusCode,
                    message: message ?? "视频背景分析失败（\(http.statusCode)）。",
                    retryAfter: Self.retryAfter(from: http)
                )))
                return
            }
            guard let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data),
                  let content = envelope.choices.first?.message.content,
                  let jsonData = Self.extractJSON(from: content).data(using: .utf8),
                  let analysis = try? JSONDecoder().decode(BackgroundCardResponse.self, from: jsonData) else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            let validCueIDs = Set(document.segments.map(\.id))
            let card = analysis.makeCard(
                videoID: video.id,
                segmentCount: document.segments.count,
                validCueIDs: validCueIDs
            )
            guard !card.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            completion(.success(card))
        }.resume()
    }

    func testConnection(configuration: TranslationConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
        let probe = SubtitleSegment(id: "probe", start: 0, end: 1, original: "Hello.", translation: nil)
        translate(segments: [probe], context: [probe], videoTitle: "Connection Test", configuration: configuration) {
            completion($0.map { _ in () })
        }
    }

    private static func extractJSON(from text: String) -> String {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else { return text }
        return String(text[first...last])
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, seconds)
        }
        guard let date = HTTPDateParser.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}

private enum HTTPDateParser {
    static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

private struct ChatEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message
    }
    var choices: [Choice]
}

private struct TranslatedBatch: Decodable {
    struct Item: Decodable { var id: String; var text: String }
    var segments: [Item]
}

private struct BackgroundCardResponse: Decodable {
    struct Chapter: Decodable {
        var start: Double
        var end: Double?
        var title: String
    }

    struct NamedItem: Decodable {
        var source: String
        var preferredZH: String
        var evidenceIDs: [String]

        enum CodingKeys: String, CodingKey {
            case source
            case preferredZH = "preferred_zh"
            case evidenceIDs = "evidence_ids"
        }
    }

    struct Uncertainty: Decodable {
        var cueID: String
        var note: String

        enum CodingKeys: String, CodingKey {
            case cueID = "cue_id"
            case note
        }
    }

    var overview: String
    var chapters: [Chapter]
    var domain: String
    var tone: String
    var entities: [NamedItem]
    var terminology: [NamedItem]
    var uncertainties: [Uncertainty]

    func makeCard(videoID: String, segmentCount: Int, validCueIDs: Set<String>) -> VideoBackgroundCard {
        VideoBackgroundCard(
            videoID: videoID,
            overview: overview.trimmingCharacters(in: .whitespacesAndNewlines),
            chapters: chapters
                .filter { $0.start >= 0 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.start < $1.start }
                .map { BackgroundChapter(start: $0.start, end: $0.end, title: $0.title) },
            domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
            tone: tone.trimmingCharacters(in: .whitespacesAndNewlines),
            entities: entities.compactMap {
                guard !$0.source.isEmpty, !$0.preferredZH.isEmpty else { return nil }
                return BackgroundEntity(
                    source: $0.source,
                    preferredTranslation: $0.preferredZH,
                    evidenceCueIDs: $0.evidenceIDs.filter(validCueIDs.contains)
                )
            },
            terminology: terminology.compactMap {
                guard !$0.source.isEmpty, !$0.preferredZH.isEmpty else { return nil }
                return BackgroundTerm(
                    source: $0.source,
                    preferredTranslation: $0.preferredZH,
                    evidenceCueIDs: $0.evidenceIDs.filter(validCueIDs.contains)
                )
            },
            uncertainties: uncertainties.compactMap {
                guard validCueIDs.contains($0.cueID), !$0.note.isEmpty else { return nil }
                return BackgroundUncertainty(cueID: $0.cueID, note: $0.note)
            },
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: segmentCount
        )
    }
}

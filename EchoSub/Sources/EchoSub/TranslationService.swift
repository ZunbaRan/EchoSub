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
    case gloss
    case detail
}

enum TranslationRequestPolicy {
    static let batchSize = 4
    static let translationTimeout: TimeInterval = 120
    static let backgroundCardTimeout: TimeInterval = 600
    static let backgroundCardResourceTimeout: TimeInterval = 720

    static func thinkingMode(model: String, purpose: TranslationRequestPurpose) -> Bool? {
        let normalized = model.lowercased()
        let supportsExplicitThinking = normalized.contains("qwen3")
            || normalized.contains("qwen-3")
            || normalized.contains("deepseek-v4")
        guard supportsExplicitThinking else { return nil }
        switch purpose {
        case .translation: return false
        case .backgroundCard: return true
        case .gloss: return false
        case .detail: return true
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

enum BackgroundCardRequestPlanner {
    /// DeepSeek v4 and Qwen 3.8 Flash both advertise a 1M-token context window.
    static let modelContextTokens = 1_000_000
    /// Cue JSON is mostly English/punctuation; 4 characters ≈ 1 token.
    static let charactersPerToken = 4
    static let reservedPromptTokens = 4_096
    static let reservedOutputTokens = 8_192
    static let reservedThinkingTokens = 200_000
    static let safetyMarginTokens = 32_768

    static var singlePassTokenBudget: Int {
        modelContextTokens - reservedPromptTokens - reservedOutputTokens - reservedThinkingTokens - safetyMarginTokens
    }

    static var chunkTokenBudget: Int {
        min(singlePassTokenBudget, 500_000)
    }

    static var thinkingInputLimitTokens: Int { singlePassTokenBudget }
    static var singlePassCharacterBudget: Int { singlePassTokenBudget * charactersPerToken }
    static var chunkCharacterBudget: Int { chunkTokenBudget * charactersPerToken }

    struct Plan: Equatable {
        var chunks: [[SubtitleSegment]]
        var characterCount: Int

        var usesSinglePass: Bool { chunks.count <= 1 }
        var estimatedTokens: Int { BackgroundCardRequestPlanner.estimatedTokens(characterCount: characterCount) }
        var disablesThinking: Bool {
            usesSinglePass && shouldDisableThinking(characterCount: characterCount)
        }
    }

    static func estimatedTokens(characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return (characterCount + charactersPerToken - 1) / charactersPerToken
    }

    static func shouldDisableThinking(characterCount: Int) -> Bool {
        estimatedTokens(characterCount: characterCount) > thinkingInputLimitTokens
    }

    static func cuePayload(from segments: [SubtitleSegment]) -> [[String: Any]] {
        segments.map {
            [
                "id": $0.id,
                "start": Int($0.start.rounded()),
                "text": $0.original,
            ]
        }
    }

    static func encodedCharacterCount(for segments: [SubtitleSegment]) -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: cuePayload(from: segments)) else {
            return segments.reduce(0) { $0 + $1.original.count + 48 }
        }
        return data.count
    }

    static func plan(segments: [SubtitleSegment], forceChunked: Bool = false) -> Plan {
        let characterCount = encodedCharacterCount(for: segments)
        guard !segments.isEmpty else {
            return Plan(chunks: [], characterCount: 0)
        }
        let tokens = estimatedTokens(characterCount: characterCount)
        if !forceChunked, tokens <= singlePassTokenBudget {
            return Plan(chunks: [segments], characterCount: characterCount)
        }
        var chunks = split(segments)
        if forceChunked, chunks.count == 1, segments.count > 1 {
            let mid = max(1, segments.count / 2)
            chunks = [Array(segments[..<mid]), Array(segments[mid...])]
        }
        return Plan(chunks: chunks, characterCount: characterCount)
    }

    static func split(_ segments: [SubtitleSegment]) -> [[SubtitleSegment]] {
        var chunks: [[SubtitleSegment]] = []
        var current: [SubtitleSegment] = []
        var currentCount = 2

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(current)
            current.removeAll(keepingCapacity: true)
            currentCount = 2
        }

        for segment in segments {
            let piece = encodedCharacterCount(for: [segment])
            if !current.isEmpty, currentCount + piece + 1 > chunkCharacterBudget {
                flush()
            }
            current.append(segment)
            currentCount += piece + 1
        }
        flush()
        return chunks
    }

    static func isContextOverflow(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        let markers = [
            "context length",
            "context_length",
            "maximum context",
            "max context",
            "too many tokens",
            "token limit",
            "prompt is too long",
            "input length",
            "range of input length",
            "exceeds the model's",
            "exceed context",
            "context window",
        ]
        if markers.contains(where: { text.contains($0) }) { return true }
        if case TranslationError.requestFailed(let statusCode, _, _) = error {
            return statusCode == 413
        }
        return false
    }

    static func isTimeout(_ error: Error) -> Bool {
        if (error as? URLError)?.code == .timedOut { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    static func isRecoverableByChunking(_ error: Error) -> Bool {
        isContextOverflow(error) || isTimeout(error)
    }
}

enum BackgroundCardMerger {
    static func merge(_ cards: [VideoBackgroundCard], videoID: String, segmentCount: Int) -> VideoBackgroundCard {
        let usable = cards.filter { !$0.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let source = usable.isEmpty ? cards : usable
        return VideoBackgroundCard(
            videoID: videoID,
            overview: source.map(\.overview).filter { !$0.isEmpty }.joined(separator: "\n"),
            chapters: source.flatMap(\.chapters).sorted { $0.start < $1.start },
            domain: source.map(\.domain).first(where: { !$0.isEmpty }) ?? "",
            tone: source.map(\.tone).first(where: { !$0.isEmpty }) ?? "",
            entities: mergeNamed(source.flatMap(\.entities)),
            terminology: mergeTerms(source.flatMap(\.terminology)),
            uncertainties: Array(source.flatMap(\.uncertainties).prefix(16)),
            generatedAt: Date(),
            editedAt: nil,
            sourceSegmentCount: segmentCount
        )
    }

    private static func mergeNamed(_ items: [BackgroundEntity]) -> [BackgroundEntity] {
        var result: [BackgroundEntity] = []
        var indexBySource: [String: Int] = [:]
        for item in items {
            let key = item.source.lowercased()
            if let index = indexBySource[key] {
                var existing = result[index]
                existing.evidenceCueIDs = Array(Set(existing.evidenceCueIDs + item.evidenceCueIDs))
                if existing.preferredTranslation.isEmpty {
                    existing.preferredTranslation = item.preferredTranslation
                }
                result[index] = existing
            } else {
                indexBySource[key] = result.count
                result.append(item)
            }
        }
        return result
    }

    private static func mergeTerms(_ items: [BackgroundTerm]) -> [BackgroundTerm] {
        var result: [BackgroundTerm] = []
        var indexBySource: [String: Int] = [:]
        for item in items {
            let key = item.source.lowercased()
            if let index = indexBySource[key] {
                var existing = result[index]
                existing.evidenceCueIDs = Array(Set(existing.evidenceCueIDs + item.evidenceCueIDs))
                if existing.preferredTranslation.isEmpty {
                    existing.preferredTranslation = item.preferredTranslation
                }
                result[index] = existing
            } else {
                indexBySource[key] = result.count
                result.append(item)
            }
        }
        return result
    }
}

final class TranslationService {
    private static let backgroundCardSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TranslationRequestPolicy.backgroundCardTimeout
        configuration.timeoutIntervalForResource = TranslationRequestPolicy.backgroundCardResourceTimeout
        return URLSession(configuration: configuration)
    }()

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
               let translation = segment.effectiveTranslation?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        generateBackgroundCard(
            document: document,
            video: video,
            configuration: configuration,
            forceChunked: false,
            completion: completion
        )
    }

    private func generateBackgroundCard(
        document: TranscriptDocument,
        video: VideoItem,
        configuration: TranslationConfiguration,
        forceChunked: Bool,
        completion: @escaping (Result<VideoBackgroundCard, Error>) -> Void
    ) {
        guard !configuration.apiKey.isEmpty else {
            completion(.failure(TranslationError.notConfigured))
            return
        }
        let plan = BackgroundCardRequestPlanner.plan(segments: document.segments, forceChunked: forceChunked)
        DiagnosticLogger.shared.record("background_card.plan", fields: [
            "video_id": video.id,
            "segments": String(document.segments.count),
            "character_count": String(plan.characterCount),
            "estimated_tokens": String(plan.estimatedTokens),
            "context_window_tokens": String(BackgroundCardRequestPlanner.modelContextTokens),
            "single_pass_token_budget": String(BackgroundCardRequestPlanner.singlePassTokenBudget),
            "chunks": String(plan.chunks.count),
            "force_chunked": String(forceChunked),
            "disable_thinking": String(plan.disablesThinking),
            "timeout_seconds": String(Int(TranslationRequestPolicy.backgroundCardTimeout)),
        ])
        guard !plan.chunks.isEmpty else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }
        if plan.chunks.count == 1 {
            requestBackgroundCard(
                segments: plan.chunks[0],
                document: document,
                video: video,
                configuration: configuration,
                part: nil,
                of: 1
            ) { [weak self] result in
                switch result {
                case .success:
                    completion(result)
                case .failure(let error)
                    where !forceChunked
                    && document.segments.count > 12
                    && BackgroundCardRequestPlanner.isRecoverableByChunking(error):
                    let chunked = BackgroundCardRequestPlanner.plan(segments: document.segments, forceChunked: true)
                    guard chunked.chunks.count > 1 else {
                        completion(.failure(error))
                        return
                    }
                    DiagnosticLogger.shared.record("background_card.retry_chunked", fields: [
                        "video_id": video.id,
                        "error": error.localizedDescription,
                        "chunks": String(chunked.chunks.count),
                    ])
                    self?.generateBackgroundCard(
                        document: document,
                        video: video,
                        configuration: configuration,
                        forceChunked: true,
                        completion: completion
                    )
                case .failure:
                    completion(result)
                }
            }
            return
        }
        generateChunkedBackgroundCard(
            chunks: plan.chunks,
            document: document,
            video: video,
            configuration: configuration,
            completion: completion
        )
    }

    private func generateChunkedBackgroundCard(
        chunks: [[SubtitleSegment]],
        document: TranscriptDocument,
        video: VideoItem,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<VideoBackgroundCard, Error>) -> Void
    ) {
        var remaining = chunks
        var collected: [VideoBackgroundCard] = []
        var lastError: Error = TranslationError.malformedResponse
        let total = chunks.count

        func workNext() {
            guard !remaining.isEmpty else {
                guard !collected.isEmpty else {
                    completion(.failure(lastError))
                    return
                }
                completion(.success(BackgroundCardMerger.merge(
                    collected,
                    videoID: video.id,
                    segmentCount: document.segments.count
                )))
                return
            }
            let chunk = remaining.removeFirst()
            let part = collected.count + 1
            requestBackgroundCard(
                segments: chunk,
                document: document,
                video: video,
                configuration: configuration,
                part: part,
                of: total
            ) { result in
                switch result {
                case .success(let card):
                    collected.append(card)
                    workNext()
                case .failure(let error) where BackgroundCardRequestPlanner.isContextOverflow(error) && chunk.count > 1:
                    let mid = max(1, chunk.count / 2)
                    remaining.insert(contentsOf: [Array(chunk[..<mid]), Array(chunk[mid...])], at: 0)
                    lastError = error
                    workNext()
                case .failure(let error):
                    lastError = error
                    if collected.isEmpty, remaining.isEmpty {
                        completion(.failure(error))
                    } else {
                        workNext()
                    }
                }
            }
        }
        workNext()
    }

    private func requestBackgroundCard(
        segments: [SubtitleSegment],
        document: TranscriptDocument,
        video: VideoItem,
        configuration: TranslationConfiguration,
        part: Int?,
        of totalParts: Int,
        completion: @escaping (Result<VideoBackgroundCard, Error>) -> Void
    ) {
        let base = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            completion(.failure(TranslationError.invalidEndpoint))
            return
        }

        var videoInfo: [String: Any] = [
            "id": video.id,
            "title": video.title,
            "channel": video.channel,
        ]
        if let duration = video.duration { videoInfo["duration"] = duration }
        var source: [String: Any] = [
            "video": videoInfo,
            "source_language": document.sourceLanguage,
            "transcript": BackgroundCardRequestPlanner.cuePayload(from: segments),
        ]
        if let part, totalParts > 1, let first = segments.first, let last = segments.last {
            source["part"] = part
            source["part_count"] = totalParts
            source["part_start"] = first.start
            source["part_end"] = last.end
        }
        guard let sourceData = try? JSONSerialization.data(withJSONObject: source),
              let sourceJSON = String(data: sourceData, encoding: .utf8) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        let coverage: String
        if let part, totalParts > 1, let first = segments.first, let last = segments.last {
            coverage = "This is part \(part) of \(totalParts) of a long video, covering \(Int(first.start))s–\(Int(last.end))s. Analyze only this part. Chapters must stay inside this time range. The overview may be 3-6 sentences for this part."
        } else {
            coverage = "Read every supplied cue. The overview must cover the whole video's topic progression in 5-8 sentences, not only the opening."
        }
        let system = """
        You analyze a video transcript before subtitle translation. Return a concise, evidence-grounded background card in Simplified Chinese.
        \(coverage)
        Do not invent facts. Chapters must be chronological and use numeric seconds from the supplied cue timestamps. Entities and terminology must include only useful recurring items, with exact source spelling, preferred Simplified Chinese, and evidence cue IDs that really contain the item. Flag only plausible ASR or source ambiguities.
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
        let disableThinking = BackgroundCardRequestPlanner.shouldDisableThinking(
            characterCount: BackgroundCardRequestPlanner.encodedCharacterCount(for: segments)
        )
        if disableThinking {
            let normalized = configuration.model.lowercased()
            if normalized.contains("qwen3") || normalized.contains("qwen-3") || normalized.contains("deepseek-v4") {
                payload["enable_thinking"] = false
            }
        } else {
            TranslationRequestPolicy.applyThinkingMode(
                to: &payload,
                model: configuration.model,
                purpose: .backgroundCard
            )
        }
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

        Self.backgroundCardSession.dataTask(with: request) { data, response, error in
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
            let validCueIDs = Set(segments.map(\.id))
            let card = analysis.makeCard(
                videoID: video.id,
                segmentCount: segments.count,
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

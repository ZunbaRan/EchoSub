import Foundation

enum SubtitleFallbackError: LocalizedError {
    case ytDLPNotInstalled
    case ytDLPFailed(String)
    case supadataNotConfigured
    case supadataFailed(String)
    case noUsableTrack
    case allProvidersFailed([String])

    var errorDescription: String? {
        switch self {
        case .ytDLPNotInstalled:
            return "未检测到 yt-dlp。可通过 Homebrew 安装：brew install yt-dlp"
        case .ytDLPFailed(let detail):
            return detail.isEmpty ? "yt-dlp 未能读取这个视频的字幕。" : "yt-dlp：\(detail)"
        case .supadataNotConfigured:
            return "Supadata API Key 未配置（设置 → 字幕来源）。"
        case .supadataFailed(let detail):
            return detail.isEmpty ? "Supadata 未能读取这个视频的字幕。" : "Supadata：\(detail)"
        case .noUsableTrack:
            return "没有找到可用的字幕轨道。"
        case .allProvidersFailed(let messages):
            return messages.joined(separator: "\n")
        }
    }
}

final class YTDLPTranscriptProvider {
    static var executableURL: URL? {
        var candidates: [String] = []
        if let bundled = Bundle.main.path(forResource: "yt-dlp", ofType: nil) { candidates.append(bundled) }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/yt-dlp" })
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
        ])
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    func fetch(videoID: String, completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void) {
        guard let executable = Self.executableURL else {
            completion(.failure(SubtitleFallbackError.ytDLPNotInstalled))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = [
                "--dump-single-json",
                "--skip-download",
                "--no-warnings",
                "--no-playlist",
                "--socket-timeout", "20",
                YouTubeURLParser.canonicalURL(for: videoID),
            ]
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    completion(.failure(SubtitleFallbackError.ytDLPFailed(detail)))
                    return
                }
                guard let info = try? JSONDecoder().decode(YTDLPInfo.self, from: data),
                      let selected = Self.bestTrack(in: info) else {
                    completion(.failure(SubtitleFallbackError.noUsableTrack))
                    return
                }
                self.fetchTrack(
                    selected.format.url,
                    videoID: videoID,
                    language: selected.language,
                    generated: selected.generated,
                    info: info,
                    completion: completion
                )
            } catch {
                completion(.failure(SubtitleFallbackError.ytDLPFailed(error.localizedDescription)))
            }
        }
    }

    private func fetchTrack(
        _ value: String,
        videoID: String,
        language: String,
        generated: Bool,
        info: YTDLPInfo,
        completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void
    ) {
        guard let url = URL(string: value) else {
            completion(.failure(SubtitleFallbackError.noUsableTrack))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(SubtitleFallbackError.ytDLPFailed(error.localizedDescription)))
                return
            }
            guard let data,
                  let root = try? JSONDecoder().decode(YTDLPJSON3Root.self, from: data) else {
                completion(.failure(SubtitleFallbackError.ytDLPFailed("字幕数据格式无法识别。")))
                return
            }
            let cues = root.events.compactMap { event -> RawCaptionCue? in
                let text = SubtitleSegmenter.normalize(event.segs?.compactMap(\.utf8).joined() ?? "")
                guard !text.isEmpty else { return nil }
                return RawCaptionCue(
                    text: text,
                    start: Double(event.tStartMs ?? 0) / 1_000,
                    duration: Double(event.dDurationMs ?? 0) / 1_000
                )
            }
            let segments = SubtitleSegmenter.group(cues)
            guard !segments.isEmpty else {
                completion(.failure(SubtitleFallbackError.noUsableTrack))
                return
            }
            completion(.success(TranscriptFetchResult(
                document: TranscriptDocument(
                    videoID: videoID,
                    sourceLanguage: language,
                    isGenerated: generated,
                    segments: segments,
                    provider: .ytDLP
                ),
                title: info.title ?? "YouTube 视频",
                channel: info.uploader ?? info.channel ?? "YouTube",
                duration: info.duration
            )))
        }.resume()
    }

    private static func bestTrack(in info: YTDLPInfo) -> (language: String, format: YTDLPFormat, generated: Bool)? {
        if let result = bestTrack(in: info.subtitles) { return (result.language, result.format, false) }
        if let result = bestTrack(in: info.automaticCaptions) { return (result.language, result.format, true) }
        return nil
    }

    private static func bestTrack(in tracks: [String: [YTDLPFormat]]?) -> (language: String, format: YTDLPFormat)? {
        guard let tracks else { return nil }
        let languages = tracks.keys.sorted { left, right in
            languageScore(left) > languageScore(right)
        }
        for language in languages {
            if let format = tracks[language]?.first(where: { $0.ext == "json3" && !$0.url.isEmpty }) {
                return (language, format)
            }
        }
        return nil
    }

    private static func languageScore(_ language: String) -> Int {
        let value = language.lowercased()
        if value == "en" { return 300 }
        if value == "en-orig" { return 290 }
        if value.hasPrefix("en-") { return 280 }
        return 0
    }
}

final class SupadataTranscriptProvider {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    func fetch(videoID: String, apiKey: String, completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void) {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(SubtitleFallbackError.supadataNotConfigured))
            return
        }
        var components = URLComponents(string: "https://api.supadata.ai/v1/transcript")!
        components.queryItems = [
            URLQueryItem(name: "url", value: YouTubeURLParser.canonicalURL(for: videoID)),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "text", value: "false"),
            URLQueryItem(name: "mode", value: "native"),
        ]
        guard let url = components.url else {
            completion(.failure(SubtitleFallbackError.supadataFailed("请求地址无效。")))
            return
        }
        perform(url: url, apiKey: apiKey, videoID: videoID, attemptsRemaining: 12, completion: completion)
    }

    func test(apiKey: String, completion: @escaping (Result<Void, Error>) -> Void) {
        fetch(videoID: "M7lc1UVf-VE", apiKey: apiKey) { result in
            completion(result.map { _ in () })
        }
    }

    private func perform(
        url: URL,
        apiKey: String,
        videoID: String,
        attemptsRemaining: Int,
        completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(SubtitleFallbackError.supadataFailed(error.localizedDescription)))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(SubtitleFallbackError.supadataFailed("服务没有返回有效响应。")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? JSONDecoder().decode(SupadataErrorEnvelope.self, from: data).message)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                completion(.failure(SubtitleFallbackError.supadataFailed("\(http.statusCode) · \(detail)")))
                return
            }
            guard let envelope = try? JSONDecoder().decode(SupadataEnvelope.self, from: data) else {
                completion(.failure(SubtitleFallbackError.supadataFailed("返回格式无法识别。")))
                return
            }
            if let content = envelope.content, !content.isEmpty {
                let cues = content.map {
                    RawCaptionCue(text: $0.text, start: $0.offset / 1_000, duration: $0.duration / 1_000)
                }
                let segments = SubtitleSegmenter.group(cues)
                guard !segments.isEmpty else {
                    completion(.failure(SubtitleFallbackError.noUsableTrack))
                    return
                }
                completion(.success(TranscriptFetchResult(
                    document: TranscriptDocument(
                        videoID: videoID,
                        sourceLanguage: envelope.lang ?? "en",
                        isGenerated: false,
                        segments: segments,
                        provider: .supadata
                    ),
                    title: "YouTube 视频",
                    channel: "YouTube",
                    duration: nil
                )))
                return
            }
            guard let jobID = envelope.jobId, attemptsRemaining > 0,
                  let pollURL = URL(string: "https://api.supadata.ai/v1/transcript/\(jobID)") else {
                let detail = envelope.error?.message ?? "任务没有返回字幕。"
                completion(.failure(SubtitleFallbackError.supadataFailed(detail)))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                self?.perform(
                    url: pollURL,
                    apiKey: apiKey,
                    videoID: videoID,
                    attemptsRemaining: attemptsRemaining - 1,
                    completion: completion
                )
            }
        }.resume()
    }
}

private struct YTDLPInfo: Decodable {
    var title: String?
    var uploader: String?
    var channel: String?
    var duration: Double?
    var subtitles: [String: [YTDLPFormat]]?
    var automaticCaptions: [String: [YTDLPFormat]]?

    enum CodingKeys: String, CodingKey {
        case title, uploader, channel, duration, subtitles
        case automaticCaptions = "automatic_captions"
    }
}

private struct YTDLPFormat: Decodable {
    var ext: String
    var url: String
}

private struct YTDLPJSON3Root: Decodable { var events: [YTDLPJSON3Event] }
private struct YTDLPJSON3Event: Decodable {
    var tStartMs: Int?
    var dDurationMs: Int?
    var segs: [YTDLPJSON3Segment]?
}
private struct YTDLPJSON3Segment: Decodable { var utf8: String? }

private struct SupadataEnvelope: Decodable {
    var content: [SupadataChunk]?
    var lang: String?
    var jobId: String?
    var status: String?
    var error: SupadataErrorEnvelope?
}

private struct SupadataChunk: Decodable {
    var text: String
    var offset: Double
    var duration: Double
}

private struct SupadataErrorEnvelope: Decodable {
    var message: String?
}

import Foundation

enum TranscriptServiceError: LocalizedError {
    case invalidWatchPage
    case videoUnavailable(String)
    case noSubtitles
    case malformedResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidWatchPage: return "无法读取 YouTube 视频页面。"
        case .videoUnavailable(let reason): return reason.isEmpty ? "该视频当前不可用。" : reason
        case .noSubtitles: return "这个视频没有可用字幕。"
        case .malformedResponse: return "YouTube 返回了无法识别的字幕数据。"
        case .network(let error): return "网络请求失败：\(error.localizedDescription)"
        }
    }
}

struct TranscriptFetchResult {
    var document: TranscriptDocument
    var title: String
    var channel: String
    var duration: Double?
}

final class YouTubeTranscriptService {
    private let session: URLSession
    private let ytDLPProvider = YTDLPTranscriptProvider()
    private let supadataProvider = SupadataTranscriptProvider()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15",
        ]
        session = URLSession(configuration: config)
    }

    func fetch(videoID: String, completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void) {
        fetchDirect(videoID: videoID) { [weak self] result in
            switch result {
            case .success:
                completion(result)
            case .failure(let directError):
                self?.ytDLPProvider.fetch(videoID: videoID) { ytDLPResult in
                    switch ytDLPResult {
                    case .success:
                        completion(ytDLPResult)
                    case .failure(let ytDLPError):
                        let key = AppSettings.shared.supadataAPIKey
                        self?.supadataProvider.fetch(videoID: videoID, apiKey: key) { supadataResult in
                            switch supadataResult {
                            case .success:
                                completion(supadataResult)
                            case .failure(let supadataError):
                                completion(.failure(SubtitleFallbackError.allProvidersFailed([
                                    "YouTube：\(directError.localizedDescription)",
                                    ytDLPError.localizedDescription,
                                    supadataError.localizedDescription,
                                ])))
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchDirect(videoID: String, completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void) {
        guard let watchURL = URL(string: YouTubeURLParser.canonicalURL(for: videoID)) else {
            completion(.failure(TranscriptServiceError.invalidWatchPage))
            return
        }
        var request = URLRequest(url: watchURL)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        session.dataTask(with: request) { [weak self] data, _, error in
            if let error { return completion(.failure(TranscriptServiceError.network(error))) }
            guard let data, let html = String(data: data, encoding: .utf8) else {
                completion(.failure(TranscriptServiceError.invalidWatchPage))
                return
            }
            if let embedded = Self.embeddedPlayerResponse(in: html),
               embedded.playabilityStatus.status == "OK",
               embedded.captions?.playerCaptionsTracklistRenderer.captionTracks.isEmpty == false {
                self?.finish(videoID: videoID, response: embedded, completion: completion)
                return
            }
            guard let apiKey = Self.firstMatch(#"\"INNERTUBE_API_KEY\":\"([^\"]+)\""#, in: html) else {
                completion(.failure(TranscriptServiceError.invalidWatchPage))
                return
            }
            self?.fetchPlayer(videoID: videoID, apiKey: apiKey, completion: completion)
        }.resume()
    }

    private func fetchPlayer(videoID: String, apiKey: String, completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void) {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)") else {
            completion(.failure(TranscriptServiceError.malformedResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.youtube/20.10.38 (Linux; U; Android 14)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "ANDROID", "clientVersion": "20.10.38", "hl": "en", "gl": "US"]],
            "videoId": videoID,
        ])

        session.dataTask(with: request) { [weak self] data, _, error in
            if let error { return completion(.failure(TranscriptServiceError.network(error))) }
            guard let data,
                  let response = try? JSONDecoder().decode(PlayerResponse.self, from: data) else {
                completion(.failure(TranscriptServiceError.malformedResponse))
                return
            }
            if response.playabilityStatus.status != "OK" {
                completion(.failure(TranscriptServiceError.videoUnavailable(response.playabilityStatus.reason ?? "")))
                return
            }
            self?.finish(videoID: videoID, response: response, completion: completion)
        }.resume()
    }

    private func finish(videoID: String, response: PlayerResponse, completion: @escaping (Result<TranscriptFetchResult, Error>) -> Void) {
        guard let tracks = response.captions?.playerCaptionsTracklistRenderer.captionTracks,
                  let track = Self.bestTrack(from: tracks) else {
            completion(.failure(TranscriptServiceError.noSubtitles))
            return
        }
        fetchCues(track: track) { cueResult in
            switch cueResult {
            case .failure(let error): completion(.failure(error))
            case .success(let cues):
                let segments = SubtitleSegmenter.group(cues)
                guard !segments.isEmpty else {
                    completion(.failure(TranscriptServiceError.noSubtitles))
                    return
                }
                let details = response.videoDetails
                completion(.success(TranscriptFetchResult(
                    document: TranscriptDocument(
                        videoID: videoID,
                        sourceLanguage: track.languageCode,
                        isGenerated: track.kind == "asr",
                        segments: segments,
                        provider: .youtube
                    ),
                    title: details?.title ?? "YouTube 视频",
                    channel: details?.author ?? "YouTube",
                    duration: details?.lengthSeconds.flatMap(Double.init)
                )))
            }
        }
    }

    private func fetchCues(track: CaptionTrack, completion: @escaping (Result<[RawCaptionCue], Error>) -> Void) {
        guard var components = URLComponents(string: track.baseUrl) else {
            completion(.failure(TranscriptServiceError.malformedResponse))
            return
        }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "fmt" }
        query.append(URLQueryItem(name: "fmt", value: "json3"))
        components.queryItems = query
        guard let url = components.url else {
            completion(.failure(TranscriptServiceError.malformedResponse))
            return
        }

        session.dataTask(with: url) { data, _, error in
            if let error { return completion(.failure(TranscriptServiceError.network(error))) }
            guard let data,
                  let root = try? JSONDecoder().decode(JSON3Root.self, from: data) else {
                completion(.failure(TranscriptServiceError.malformedResponse))
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
            completion(cues.isEmpty ? .failure(TranscriptServiceError.noSubtitles) : .success(cues))
        }.resume()
    }

    private static func bestTrack(from tracks: [CaptionTrack]) -> CaptionTrack? {
        tracks.sorted { left, right in
            let leftScore = score(left)
            let rightScore = score(right)
            return leftScore > rightScore
        }.first
    }

    private static func score(_ track: CaptionTrack) -> Int {
        var value = track.languageCode.lowercased().hasPrefix("en") ? 100 : 0
        if track.kind != "asr" { value += 20 }
        return value
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func embeddedPlayerResponse(in html: String) -> PlayerResponse? {
        for marker in ["var ytInitialPlayerResponse = ", "window[\"ytInitialPlayerResponse\"] = ", "\"ytInitialPlayerResponse\":"] {
            guard let markerRange = html.range(of: marker),
                  let objectStart = html[markerRange.upperBound...].firstIndex(of: "{") else { continue }
            var index = objectStart
            var depth = 0
            var inString = false
            var escaped = false
            while index < html.endIndex {
                let character = html[index]
                if inString {
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if character == "\"" { inString = false }
                } else {
                    if character == "\"" { inString = true }
                    else if character == "{" { depth += 1 }
                    else if character == "}" {
                        depth -= 1
                        if depth == 0 {
                            let end = html.index(after: index)
                            let json = String(html[objectStart..<end])
                            return json.data(using: .utf8).flatMap { try? JSONDecoder().decode(PlayerResponse.self, from: $0) }
                        }
                    }
                }
                index = html.index(after: index)
            }
        }
        return nil
    }
}

private struct PlayerResponse: Decodable {
    var playabilityStatus: PlayabilityStatus
    var captions: Captions?
    var videoDetails: VideoDetails?
}

private struct PlayabilityStatus: Decodable {
    var status: String
    var reason: String?
}

private struct Captions: Decodable {
    var playerCaptionsTracklistRenderer: CaptionTrackList
}

private struct CaptionTrackList: Decodable {
    var captionTracks: [CaptionTrack]
}

private struct CaptionTrack: Decodable {
    var baseUrl: String
    var languageCode: String
    var kind: String?
}

private struct VideoDetails: Decodable {
    var title: String?
    var author: String?
    var lengthSeconds: String?
}

private struct JSON3Root: Decodable {
    var events: [JSON3Event]
}

private struct JSON3Event: Decodable {
    var tStartMs: Int?
    var dDurationMs: Int?
    var segs: [JSON3Segment]?
}

private struct JSON3Segment: Decodable {
    var utf8: String?
}

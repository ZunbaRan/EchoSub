import Foundation

enum YouTubeURLParser {
    private static let videoIDPattern = "^[A-Za-z0-9_-]{11}$"

    static func videoID(from input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: videoIDPattern, options: .regularExpression) != nil {
            return value
        }

        let normalized = value.hasPrefix("http") ? value : "https://\(value)"
        guard let components = URLComponents(string: normalized),
              let host = components.host?.lowercased() else { return nil }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return validated(String(components.path.dropFirst()).split(separator: "/").first.map(String.init))
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if components.path == "/watch" {
            return validated(components.queryItems?.first(where: { $0.name == "v" })?.value)
        }

        let parts = components.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["shorts", "embed", "v", "live"].contains(parts[0]) {
            return validated(parts[1])
        }
        return nil
    }

    static func canonicalURL(for videoID: String) -> String {
        "https://www.youtube.com/watch?v=\(videoID)"
    }

    private static func validated(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = String(candidate.prefix(11))
        return trimmed.range(of: videoIDPattern, options: .regularExpression) == nil ? nil : trimmed
    }
}

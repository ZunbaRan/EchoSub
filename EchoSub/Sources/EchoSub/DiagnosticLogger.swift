import Foundation

final class DiagnosticLogger {
    static let shared = DiagnosticLogger(
        fileURL: EchoStorage.directoryURL.appendingPathComponent("diagnostics.jsonl")
    )

    let fileURL: URL
    private let lock = NSLock()
    private let maximumBytes: Int64

    init(fileURL: URL, maximumBytes: Int64 = 4 * 1_024 * 1_024) {
        self.fileURL = fileURL
        self.maximumBytes = maximumBytes
        ensureFileExists()
    }

    func record(_ event: String, fields: [String: String] = [:]) {
        var payload = sanitized(fields)
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        payload["event"] = event

        guard JSONSerialization.isValidJSONObject(payload),
              var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded(appending: Int64(data.count))
        ensureFileExists()
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never interrupt playback or translation.
        }
    }

    private func sanitized(_ fields: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { key, value in
            let normalizedKey = key.lowercased()
            let sensitive = ["api_key", "apikey", "authorization", "password", "secret", "token"]
                .contains { normalizedKey.contains($0) }
            if sensitive { return (key, "<redacted>") }
            if value.localizedCaseInsensitiveContains("Bearer ") { return (key, "<redacted>") }
            return (key, String(value.prefix(1_000)))
        })
    }

    private func ensureFileExists() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func rotateIfNeeded(appending bytes: Int64) {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        guard size + bytes > maximumBytes else { return }
        let previous = fileURL.deletingLastPathComponent().appendingPathComponent("diagnostics.previous.jsonl")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
    }
}

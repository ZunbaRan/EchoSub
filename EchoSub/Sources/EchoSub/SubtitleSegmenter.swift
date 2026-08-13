import Foundation

enum SubtitleSegmenter {
    struct Limits {
        var minimumDuration: Double = 2
        var idealDuration: Double = 5.5
        var maximumDuration: Double = 8
        var maximumCharacters: Int = 150
    }

    static func group(_ cues: [RawCaptionCue], limits: Limits = .init()) -> [SubtitleSegment] {
        let clean = cues
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        guard !clean.isEmpty else { return [] }

        var result: [SubtitleSegment] = []
        var texts: [String] = []
        var start = clean[0].start
        var end = clean[0].end

        func flush() {
            let text = normalize(texts.joined(separator: " "))
            guard !text.isEmpty else { return }
            result.append(SubtitleSegment(
                id: "segment-\(result.count)-\(Int((start * 1_000).rounded()))",
                start: start,
                end: max(end, start + 0.2),
                original: text,
                translation: nil
            ))
            texts.removeAll(keepingCapacity: true)
        }

        for cue in clean {
            if texts.isEmpty {
                start = cue.start
                end = cue.end
            }
            let nextText = normalize(cue.text)
            texts.append(nextText)
            end = max(end, cue.end)

            let merged = normalize(texts.joined(separator: " "))
            let elapsed = end - start
            let sentenceEnd = merged.range(of: #"[.!?。！？][\"'”’）\]]*$"#, options: .regularExpression) != nil
            let clauseEnd = merged.range(of: #"[,;:，；：][\"'”’）\]]*$"#, options: .regularExpression) != nil
            let shouldFlush =
                (sentenceEnd && elapsed >= limits.minimumDuration) ||
                (clauseEnd && elapsed >= limits.idealDuration) ||
                elapsed >= limits.maximumDuration ||
                merged.count >= limits.maximumCharacters
            if shouldFlush { flush() }
        }
        flush()
        return result
    }

    static func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: ">>", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?，。；：！？])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

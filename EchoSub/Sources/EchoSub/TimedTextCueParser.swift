import Foundation

/// YouTube timedtext responses arrive in more than one shape:
/// - JSON3 ("events" array), the format requested with fmt=json3.
/// - XML format 3 (<p t="240" d="5760"><s>The</s>...</p>), which the Android
///   InnerTube client returns even when fmt=json3 is requested.
/// - Older XML (<text start="1.2" dur="3.4">...</text>).
enum TimedTextCueParser {
    static func cues(from data: Data) -> [RawCaptionCue]? {
        if let root = try? JSONDecoder().decode(JSON3Root.self, from: data) {
            return root.events.compactMap { event in
                let text = SubtitleSegmenter.normalize(event.segs?.compactMap(\.utf8).joined() ?? "")
                guard !text.isEmpty else { return nil }
                return RawCaptionCue(
                    text: text,
                    start: Double(event.tStartMs ?? 0) / 1_000,
                    duration: Double(event.dDurationMs ?? 0) / 1_000
                )
            }
        }

        let delegate = XMLCueDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.cues
    }
}

private struct JSON3Root: Decodable { var events: [JSON3Event] }

private struct JSON3Event: Decodable {
    var tStartMs: Int?
    var dDurationMs: Int?
    var segs: [JSON3Segment]?
}

private struct JSON3Segment: Decodable { var utf8: String? }

private final class XMLCueDelegate: NSObject, XMLParserDelegate {
    private(set) var cues: [RawCaptionCue] = []
    private var start: Double?
    private var duration: Double = 0
    private var text = ""
    private var isCollecting = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "p":
            // format 3 uses milliseconds on the <p> element.
            start = Double(attributeDict["t"] ?? "").map { $0 / 1_000 }
            duration = Double(attributeDict["d"] ?? "").map { $0 / 1_000 } ?? 0
            text = ""
            isCollecting = true
        case "text":
            // older timedtext uses seconds.
            start = Double(attributeDict["start"] ?? "")
            duration = Double(attributeDict["dur"] ?? "") ?? 0
            text = ""
            isCollecting = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCollecting else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard isCollecting, elementName == "p" || elementName == "text" else { return }
        isCollecting = false
        let normalized = SubtitleSegmenter.normalize(text)
        guard !normalized.isEmpty, let start else { return }
        cues.append(RawCaptionCue(text: normalized, start: start, duration: duration))
    }
}

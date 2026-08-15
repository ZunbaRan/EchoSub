import Foundation

enum VocabularyNormalization {
    static func normalizedTerm(_ surface: String) -> String {
        let collapsed = surface
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !collapsed.isEmpty else { return "" }

        var value = collapsed
        while let first = value.first, first.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
            value.removeFirst()
        }
        while let last = value.last, last.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isEligibleSurface(_ surface: String) -> Bool {
        let normalized = normalizedTerm(surface)
        guard !normalized.isEmpty else { return false }
        return normalized.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    static func isPhrase(_ surface: String) -> Bool {
        let normalized = normalizedTerm(surface)
        let tokens = normalized.split(separator: " ")
        guard tokens.count > 1 else { return false }
        return tokens.allSatisfy { token in
            token.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }
    }
}

enum VocabularyDetailPromptKind: Equatable {
    case word
    case phrase
}

enum VocabularyDetailPromptPolicy {
    static func kind(for surface: String) -> VocabularyDetailPromptKind {
        VocabularyNormalization.isPhrase(surface) ? .phrase : .word
    }

    static func omitsFormsAndEtymology(for surface: String) -> Bool {
        kind(for: surface) == .phrase
    }

    static func promptInstruction(for surface: String) -> String {
        guard kind(for: surface) == .phrase else { return "" }
        return "The selection is a multi-word phrase. Treat it as one whole phrase: prioritize its contextual meaning, collocations, and useful examples. Return forms and etymology as empty arrays/strings; do not analyze individual word morphology or origins."
    }
}

struct GlossEntry: Codable, Identifiable, Equatable {
    var id: String
    var surface: String
    var normalized: String
    var gloss: String
    var pos: String?
    var createdAt: Date
    var detailCacheKey: String

    init(
        id: String = UUID().uuidString,
        surface: String,
        normalized: String? = nil,
        gloss: String,
        pos: String? = nil,
        createdAt: Date = Date(),
        detailCacheKey: String = ""
    ) {
        self.id = id
        self.surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalized = normalized.map(VocabularyNormalization.normalizedTerm) ?? VocabularyNormalization.normalizedTerm(surface)
        self.gloss = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pos = pos?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.createdAt = createdAt
        self.detailCacheKey = detailCacheKey
    }

    var contextualGloss: String {
        get { gloss }
        set { gloss = newValue }
    }

    var partOfSpeech: String? {
        get { pos }
        set { pos = newValue }
    }

    var normalizedForm: String {
        get { normalized }
        set { normalized = VocabularyNormalization.normalizedTerm(newValue) }
    }

    var contextualMeaning: String {
        get { gloss }
        set { gloss = newValue }
    }

    var detailKey: String {
        get { detailCacheKey }
        set { detailCacheKey = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id, surface, normalized, gloss, contextualGloss, pos, partOfSpeech, createdAt, detailCacheKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let surface = try container.decodeIfPresent(String.self, forKey: .surface) ?? ""
        let gloss = try container.decodeIfPresent(String.self, forKey: .gloss)
            ?? container.decodeIfPresent(String.self, forKey: .contextualGloss)
            ?? ""
        let pos = try container.decodeIfPresent(String.self, forKey: .pos)
            ?? container.decodeIfPresent(String.self, forKey: .partOfSpeech)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            surface: surface,
            normalized: try container.decodeIfPresent(String.self, forKey: .normalized),
            gloss: gloss,
            pos: pos,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            detailCacheKey: try container.decodeIfPresent(String.self, forKey: .detailCacheKey) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(surface, forKey: .surface)
        try container.encode(normalized, forKey: .normalized)
        try container.encode(gloss, forKey: .gloss)
        try container.encodeIfPresent(pos, forKey: .pos)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(detailCacheKey, forKey: .detailCacheKey)
    }
}

struct VocabForm: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    var translation: String?

    init(id: String = UUID().uuidString, label: String, value: String, translation: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.translation = translation
    }

    private enum CodingKeys: String, CodingKey { case id, label, value, translation, meaning }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
            value: try container.decodeIfPresent(String.self, forKey: .value) ?? "",
            translation: try container.decodeIfPresent(String.self, forKey: .translation)
                ?? container.decodeIfPresent(String.self, forKey: .meaning)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(translation, forKey: .translation)
    }
}

struct VocabRelatedWord: Codable, Identifiable, Equatable {
    var id: String
    var word: String
    var translation: String?
    var pos: String?

    init(id: String = UUID().uuidString, word: String, translation: String? = nil, pos: String? = nil) {
        self.id = id
        self.word = word
        self.translation = translation
        self.pos = pos
    }

    private enum CodingKeys: String, CodingKey { case id, word, source, translation, preferredZH, preferred_zh, pos, partOfSpeech }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            word: try container.decodeIfPresent(String.self, forKey: .word)
                ?? container.decodeIfPresent(String.self, forKey: .source) ?? "",
            translation: try container.decodeIfPresent(String.self, forKey: .translation)
                ?? container.decodeIfPresent(String.self, forKey: .preferredZH)
                ?? container.decodeIfPresent(String.self, forKey: .preferred_zh),
            pos: try container.decodeIfPresent(String.self, forKey: .pos)
                ?? container.decodeIfPresent(String.self, forKey: .partOfSpeech)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(pos, forKey: .pos)
    }
}

struct VocabPhrase: Codable, Identifiable, Equatable {
    var id: String
    var phrase: String
    var translation: String?
    var note: String?

    init(id: String = UUID().uuidString, phrase: String, translation: String? = nil, note: String? = nil) {
        self.id = id
        self.phrase = phrase
        self.translation = translation
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case id, phrase, text, translation, meaning, note }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            phrase: try container.decodeIfPresent(String.self, forKey: .phrase)
                ?? container.decodeIfPresent(String.self, forKey: .text) ?? "",
            translation: try container.decodeIfPresent(String.self, forKey: .translation)
                ?? container.decodeIfPresent(String.self, forKey: .meaning),
            note: try container.decodeIfPresent(String.self, forKey: .note)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(phrase, forKey: .phrase)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

struct VocabExample: Codable, Identifiable, Equatable {
    var id: String
    var sentence: String
    var translation: String?
    var timestamp: Double?
    var isSourceExample: Bool

    init(
        id: String = UUID().uuidString,
        sentence: String,
        translation: String? = nil,
        timestamp: Double? = nil,
        isSourceExample: Bool = false
    ) {
        self.id = id
        self.sentence = sentence
        self.translation = translation
        self.timestamp = timestamp
        self.isSourceExample = isSourceExample
    }

    var text: String {
        get { sentence }
        set { sentence = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id, sentence, text, translation, meaning, timestamp, time, isSourceExample, is_source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            sentence: try container.decodeIfPresent(String.self, forKey: .sentence)
                ?? container.decodeIfPresent(String.self, forKey: .text) ?? "",
            translation: try container.decodeIfPresent(String.self, forKey: .translation)
                ?? container.decodeIfPresent(String.self, forKey: .meaning),
            timestamp: try container.decodeIfPresent(Double.self, forKey: .timestamp)
                ?? container.decodeIfPresent(Double.self, forKey: .time),
            isSourceExample: try container.decodeIfPresent(Bool.self, forKey: .isSourceExample)
                ?? container.decodeIfPresent(Bool.self, forKey: .is_source) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sentence, forKey: .sentence)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(isSourceExample, forKey: .isSourceExample)
    }
}

struct VocabDetail: Codable, Equatable {
    var surface: String
    var normalized: String
    var pos: String?
    var phonetic: String?
    var contextualMeaning: String
    var forms: [VocabForm]
    var explanation: String
    var etymology: String
    var memory: String
    var cognates: [VocabRelatedWord]
    var synonyms: [VocabRelatedWord]
    var antonyms: [VocabRelatedWord]
    var phrases: [VocabPhrase]
    var examples: [VocabExample]

    init(
        surface: String = "",
        normalized: String? = nil,
        pos: String? = nil,
        phonetic: String? = nil,
        contextualMeaning: String = "",
        forms: [VocabForm] = [],
        explanation: String = "",
        etymology: String = "",
        memory: String = "",
        cognates: [VocabRelatedWord] = [],
        synonyms: [VocabRelatedWord] = [],
        antonyms: [VocabRelatedWord] = [],
        phrases: [VocabPhrase] = [],
        examples: [VocabExample] = []
    ) {
        self.surface = surface
        self.normalized = normalized.map(VocabularyNormalization.normalizedTerm) ?? VocabularyNormalization.normalizedTerm(surface)
        self.pos = pos?.nonEmpty
        self.phonetic = phonetic?.nonEmpty
        self.contextualMeaning = contextualMeaning
        self.forms = forms
        self.explanation = explanation
        self.etymology = etymology
        self.memory = memory
        self.cognates = cognates
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.phrases = phrases
        self.examples = examples
    }

    init(
        surface: String = "",
        normalized: String? = nil,
        pos: String? = nil,
        phonetic: String? = nil,
        contextual: String,
        forms: [VocabForm] = [],
        explanation: String = "",
        etymology: String = "",
        memory: String = "",
        cognates: [VocabRelatedWord] = [],
        synonyms: [VocabRelatedWord] = [],
        antonyms: [VocabRelatedWord] = [],
        phrases: [VocabPhrase] = [],
        examples: [VocabExample] = []
    ) {
        self.init(
            surface: surface,
            normalized: normalized,
            pos: pos,
            phonetic: phonetic,
            contextualMeaning: contextual,
            forms: forms,
            explanation: explanation,
            etymology: etymology,
            memory: memory,
            cognates: cognates,
            synonyms: synonyms,
            antonyms: antonyms,
            phrases: phrases,
            examples: examples
        )
    }

    var contextual: String {
        get { contextualMeaning }
        set { contextualMeaning = newValue }
    }

    var contextualGloss: String {
        get { contextualMeaning }
        set { contextualMeaning = newValue }
    }

    func withSourceExample(_ segment: SubtitleSegment) -> VocabDetail {
        var copy = self
        let source = VocabExample(
            sentence: segment.original,
            translation: segment.effectiveTranslation,
            timestamp: segment.start,
            isSourceExample: true
        )
        copy.examples.removeAll { $0.isSourceExample || $0.sentence == segment.original }
        copy.examples.insert(source, at: 0)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case surface, normalized, pos, phonetic, contextualMeaning, contextual, contextual_meaning
        case forms, explanation, etymology, memory, cognates, synonyms, antonyms, phrases, examples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            surface: try container.decodeIfPresent(String.self, forKey: .surface) ?? "",
            normalized: try container.decodeIfPresent(String.self, forKey: .normalized),
            pos: try container.decodeIfPresent(String.self, forKey: .pos),
            phonetic: try container.decodeIfPresent(String.self, forKey: .phonetic),
            contextualMeaning: try container.decodeIfPresent(String.self, forKey: .contextualMeaning)
                ?? container.decodeIfPresent(String.self, forKey: .contextual)
                ?? container.decodeIfPresent(String.self, forKey: .contextual_meaning) ?? "",
            forms: try container.decodeIfPresent([VocabForm].self, forKey: .forms) ?? [],
            explanation: try container.decodeIfPresent(String.self, forKey: .explanation) ?? "",
            etymology: try container.decodeIfPresent(String.self, forKey: .etymology) ?? "",
            memory: try container.decodeIfPresent(String.self, forKey: .memory) ?? "",
            cognates: try container.decodeIfPresent([VocabRelatedWord].self, forKey: .cognates) ?? [],
            synonyms: try container.decodeIfPresent([VocabRelatedWord].self, forKey: .synonyms) ?? [],
            antonyms: try container.decodeIfPresent([VocabRelatedWord].self, forKey: .antonyms) ?? [],
            phrases: try container.decodeIfPresent([VocabPhrase].self, forKey: .phrases) ?? [],
            examples: try container.decodeIfPresent([VocabExample].self, forKey: .examples) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encode(normalized, forKey: .normalized)
        try container.encodeIfPresent(pos, forKey: .pos)
        try container.encodeIfPresent(phonetic, forKey: .phonetic)
        try container.encode(contextualMeaning, forKey: .contextualMeaning)
        try container.encode(forms, forKey: .forms)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(etymology, forKey: .etymology)
        try container.encode(memory, forKey: .memory)
        try container.encode(cognates, forKey: .cognates)
        try container.encode(synonyms, forKey: .synonyms)
        try container.encode(antonyms, forKey: .antonyms)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(examples, forKey: .examples)
    }
}

enum VocabDetailCacheKey {
    private static let separator = "|"

    static func make(normalizedTerm: String, videoID: String, subtitleID: String) -> String {
        [VocabularyNormalization.normalizedTerm(normalizedTerm), videoID, subtitleID].joined(separator: separator)
    }

    static func components(_ key: String) -> (normalizedTerm: String, videoID: String, subtitleID: String)? {
        let pieces = key.components(separatedBy: separator)
        guard pieces.count == 3 else { return nil }
        return (pieces[0], pieces[1], pieces[2])
    }

    static func belongsToVideo(_ key: String, videoID: String) -> Bool {
        components(key)?.videoID == videoID
    }
}

enum VocabDetailHydrationPolicy {
    static func hydrate(_ detail: VocabDetail, with segment: SubtitleSegment) -> VocabDetail {
        detail.withSourceExample(segment)
    }
}

struct VocabDetailRequestIdentity: Equatable {
    let videoID: String
    let segmentID: String
    let normalized: String
    let presentationID: UUID
    let requestID: UUID

    func matches(
        videoID: String,
        segmentID: String,
        normalized: String,
        presentationID: UUID,
        requestID: UUID
    ) -> Bool {
        self.videoID == videoID
            && self.segmentID == segmentID
            && self.normalized == normalized
            && self.presentationID == presentationID
            && self.requestID == requestID
    }
}

enum GlossJobInvalidationPolicy {
    static func requestKey(videoID: String, segmentID: String, normalized: String) -> String {
        "\(videoID)|\(segmentID)|\(VocabularyNormalization.normalizedTerm(normalized))"
    }

    static func invalidate(
        videoID: String,
        segmentID: String,
        normalized: String,
        jobs: inout [String: UUID],
        errors: inout [String: String]
    ) {
        let key = requestKey(videoID: videoID, segmentID: segmentID, normalized: normalized)
        jobs[key] = nil
        errors[key] = nil
    }

    static func matches(
        videoID: String,
        segmentID: String,
        normalized: String,
        jobID: UUID,
        jobs: [String: UUID]
    ) -> Bool {
        jobs[requestKey(videoID: videoID, segmentID: segmentID, normalized: normalized)] == jobID
    }
}

enum VocabularyLookupAvailability: Equatable {
    case configured
    case openSettings
}

enum VocabularyLookupAvailabilityPolicy {
    static func decision(apiKey: String) -> VocabularyLookupAvailability {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .openSettings : .configured
    }

    static func settingsTarget(apiKey: String) -> SettingsPresentationTarget? {
        decision(apiKey: apiKey) == .configured ? nil : .translation
    }
}

enum SettingsPresentationTarget: String, Equatable {
    case defaultTab
    case translation
}

enum SettingsPresentationPolicy {
    private static let targetKey = "EchoSub.settingsTarget"

    static func userInfo(for target: SettingsPresentationTarget) -> [AnyHashable: Any] {
        [targetKey: target.rawValue]
    }

    static func target(from userInfo: [AnyHashable: Any]?) -> SettingsPresentationTarget {
        guard let rawValue = userInfo?[targetKey] as? String,
              let target = SettingsPresentationTarget(rawValue: rawValue) else {
            return .defaultTab
        }
        return target
    }
}

struct VocabularySummaryEntry: Identifiable, Equatable {
    var id: String { "\(videoID)|\(segmentID)|\(gloss.id)" }
    let videoID: String
    let segmentID: String
    let gloss: GlossEntry
    let timestamp: Double
    let sourceSentence: String
}

enum GlossLookupState: Equatable {
    case idle
    case loading
    case failed(String)
}

enum VocabDetailState: Equatable {
    case idle
    case loading
    case failed(String)
}

enum VocabularyDetailRefreshPolicy {
    static func shouldPostVocabularyChangedAfterCacheHit() -> Bool { false }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

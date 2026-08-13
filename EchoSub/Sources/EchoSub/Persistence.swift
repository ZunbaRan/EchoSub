import Foundation

enum EchoStorage {
    static let directoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("EchoSub", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}

final class LibraryStore {
    private let fileURL: URL

    init() {
        fileURL = EchoStorage.directoryURL.appendingPathComponent("library.json")
    }

    func load() -> AppLibrary {
        guard let data = try? Data(contentsOf: fileURL),
              let library = try? JSONDecoder.echo.decode(AppLibrary.self, from: data) else {
            return AppLibrary()
        }
        return library
    }

    func save(_ library: AppLibrary) {
        guard let data = try? JSONEncoder.echo.encode(library) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func fileSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
    }
}

extension JSONEncoder {
    static let echo: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let echo: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

final class PlaintextCredentialStore {
    static let shared = PlaintextCredentialStore(
        fileURL: EchoStorage.directoryURL.appendingPathComponent("credentials.json")
    )

    private struct Credentials: Codable {
        var translationAPIKey: String
        var supadataAPIKey: String

        init(translationAPIKey: String = "", supadataAPIKey: String = "") {
            self.translationAPIKey = translationAPIKey
            self.supadataAPIKey = supadataAPIKey
        }

        private enum CodingKeys: String, CodingKey {
            case translationAPIKey, supadataAPIKey
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            translationAPIKey = try container.decodeIfPresent(String.self, forKey: .translationAPIKey) ?? ""
            supadataAPIKey = try container.decodeIfPresent(String.self, forKey: .supadataAPIKey) ?? ""
        }
    }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadTranslationAPIKey() -> String {
        load().translationAPIKey
    }

    func saveTranslationAPIKey(_ value: String) {
        var credentials = load()
        credentials.translationAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        save(credentials)
    }

    func loadSupadataAPIKey() -> String {
        load().supadataAPIKey
    }

    func saveSupadataAPIKey(_ value: String) {
        var credentials = load()
        credentials.supadataAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        save(credentials)
    }

    private func load() -> Credentials {
        guard let data = try? Data(contentsOf: fileURL),
              let credentials = try? JSONDecoder.echo.decode(Credentials.self, from: data) else {
            return Credentials()
        }
        return credentials
    }

    private func save(_ credentials: Credentials) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.echo.encode(credentials) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Settings remain usable; a later save can retry if the local directory was temporarily unavailable.
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    var subtitleMode: SubtitleDisplayMode {
        get {
            guard defaults.object(forKey: "subtitleMode") != nil else { return .bilingual }
            return SubtitleDisplayMode(rawValue: defaults.integer(forKey: "subtitleMode")) ?? .bilingual
        }
        set { defaults.set(newValue.rawValue, forKey: "subtitleMode"); changed() }
    }

    var autoFollow: Bool {
        get { defaults.object(forKey: "autoFollow") == nil ? true : defaults.bool(forKey: "autoFollow") }
        set { defaults.set(newValue, forKey: "autoFollow"); changed() }
    }

    var translationBaseURL: String {
        get { defaults.string(forKey: "translationBaseURL") ?? "https://api.openai.com/v1" }
        set { defaults.set(newValue, forKey: "translationBaseURL"); changed() }
    }

    var translationModel: String {
        get { defaults.string(forKey: "translationModel") ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: "translationModel"); changed() }
    }

    var overlayFontSize: Double {
        get { defaults.object(forKey: "overlayFontSize") == nil ? 20 : defaults.double(forKey: "overlayFontSize") }
        set { defaults.set(newValue, forKey: "overlayFontSize"); changed() }
    }

    var desktopEnglishFontSize: Double {
        get { defaults.object(forKey: "desktopEnglishFontSize") == nil ? 27 : defaults.double(forKey: "desktopEnglishFontSize") }
        set { defaults.set(min(48, max(12, newValue)), forKey: "desktopEnglishFontSize"); changed() }
    }

    var desktopChineseFontSize: Double {
        get { defaults.object(forKey: "desktopChineseFontSize") == nil ? 18 : defaults.double(forKey: "desktopChineseFontSize") }
        set { defaults.set(min(48, max(12, newValue)), forKey: "desktopChineseFontSize"); changed() }
    }

    var overlayPlateEnabled: Bool {
        get { defaults.object(forKey: "overlayPlateEnabled") == nil ? true : defaults.bool(forKey: "overlayPlateEnabled") }
        set { defaults.set(newValue, forKey: "overlayPlateEnabled"); changed() }
    }

    var desktopLyricsBackgroundOpacity: Double {
        get {
            guard defaults.object(forKey: "desktopLyricsBackgroundOpacity") != nil else { return 0.72 }
            return min(1, max(0, defaults.double(forKey: "desktopLyricsBackgroundOpacity")))
        }
        set { defaults.set(min(1, max(0, newValue)), forKey: "desktopLyricsBackgroundOpacity"); changed() }
    }

    var floatingBackgroundOpacity: Double {
        get {
            guard defaults.object(forKey: "floatingBackgroundOpacity") != nil else { return 0.96 }
            return min(1, max(0, defaults.double(forKey: "floatingBackgroundOpacity")))
        }
        set { defaults.set(min(1, max(0, newValue)), forKey: "floatingBackgroundOpacity"); changed() }
    }

    var subtitlePaletteID: String {
        get { defaults.string(forKey: "subtitlePaletteID") ?? SubtitlePalette.defaultPalette.id }
        set { defaults.set(newValue, forKey: "subtitlePaletteID"); changed() }
    }

    var englishColorHex: String {
        get { defaults.string(forKey: "englishColorHex") ?? defaults.string(forKey: "englishFillHex") ?? SubtitlePalette.defaultPalette.englishColor }
        set { defaults.set(newValue, forKey: "englishColorHex"); changed() }
    }

    var chineseColorHex: String {
        get { defaults.string(forKey: "chineseColorHex") ?? defaults.string(forKey: "chineseFillHex") ?? SubtitlePalette.defaultPalette.chineseColor }
        set { defaults.set(newValue, forKey: "chineseColorHex"); changed() }
    }

    func applySubtitlePalette(_ palette: SubtitlePalette) {
        defaults.set(palette.id, forKey: "subtitlePaletteID")
        defaults.set(palette.englishColor, forKey: "englishColorHex")
        defaults.set(palette.chineseColor, forKey: "chineseColorHex")
        changed()
    }

    var floatPinned: Bool {
        get { defaults.object(forKey: "floatPinned") == nil ? true : defaults.bool(forKey: "floatPinned") }
        set { defaults.set(newValue, forKey: "floatPinned"); changed() }
    }

    var showsOnAllSpaces: Bool {
        get { defaults.object(forKey: "showsOnAllSpaces") == nil ? true : defaults.bool(forKey: "showsOnAllSpaces") }
        set { defaults.set(newValue, forKey: "showsOnAllSpaces"); changed() }
    }

    var translationConfiguration: TranslationConfiguration {
        TranslationConfiguration(
            baseURL: translationBaseURL,
            model: translationModel,
            apiKey: PlaintextCredentialStore.shared.loadTranslationAPIKey()
        )
    }

    var supadataAPIKey: String { PlaintextCredentialStore.shared.loadSupadataAPIKey() }

    func reset() {
        ["subtitleMode", "autoFollow", "translationBaseURL", "translationModel", "overlayFontSize", "desktopEnglishFontSize", "desktopChineseFontSize", "overlayPlateEnabled", "desktopLyricsBackgroundOpacity", "floatingBackgroundOpacity", "subtitlePaletteID", "englishColorHex", "chineseColorHex", "englishFillHex", "englishEdgeHex", "chineseFillHex", "chineseEdgeHex", "floatPinned", "showsOnAllSpaces", "mainPlaylistWidth", "mainSubtitleWidth"].forEach(defaults.removeObject(forKey:))
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .echoSettingsChanged, object: nil)
    }
}

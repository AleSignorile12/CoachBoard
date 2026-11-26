import Foundation
#if canImport(MLKitTranslate)
import MLKitTranslate
#endif

/// Google ML Kit on-device translation. Apple's Translation framework has no Croatian, so ML Kit it is.
/// Each language model (~30 MB) downloads once; after that everything runs offline.
///
/// A struct rather than an enum so every ML Kit language fits without 59 cases. It still saves as the bare
/// language code ("it"), exactly like the old enum did, so saved phrases and settings keep loading.
nonisolated struct AppLanguage: RawRepresentable, Hashable, Identifiable, Codable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }

    static let english = AppLanguage(rawValue: "en")
    static let italian = AppLanguage(rawValue: "it")
    static let croatian = AppLanguage(rawValue: "hr")

    /// Every language ML Kit translates, with the country whose flag stands for it.
    private static let regions: [String: String] = [
        "af": "ZA", "sq": "AL", "ar": "SA", "be": "BY", "bn": "BD", "bg": "BG", "ca": "AD", "zh": "CN",
        "hr": "HR", "cs": "CZ", "da": "DK", "nl": "NL", "en": "GB", "eo": "", "et": "EE", "fi": "FI",
        "fr": "FR", "gl": "ES", "ka": "GE", "de": "DE", "el": "GR", "gu": "IN", "ht": "HT", "he": "IL",
        "hi": "IN", "hu": "HU", "is": "IS", "id": "ID", "ga": "IE", "it": "IT", "ja": "JP", "kn": "IN",
        "ko": "KR", "lv": "LV", "lt": "LT", "mk": "MK", "ms": "MY", "mt": "MT", "mr": "IN", "no": "NO",
        "fa": "IR", "pl": "PL", "pt": "PT", "ro": "RO", "ru": "RU", "sk": "SK", "sl": "SI", "es": "ES",
        "sw": "KE", "sv": "SE", "tl": "PH", "ta": "IN", "te": "IN", "th": "TH", "tr": "TR", "uk": "UA",
        "ur": "PK", "vi": "VN", "cy": "GB",
    ]

    /// All 59 languages, sorted by name in the phone's language.
    static let allCases: [AppLanguage] = regions.keys.map(AppLanguage.init(rawValue:))
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// Voice locale for reading text aloud.
    var speechCode: String {
        switch rawValue {
        case "no": "nb-NO"
        case "tl": "fil-PH"
        case "ca", "gl": "\(rawValue)-ES"
        case "eo": "eo"
        default: "\(rawValue)-\(Self.regions[rawValue] ?? "")"
        }
    }

    var name: String {
        Locale.current.localizedString(forLanguageCode: rawValue)?.localizedCapitalized ?? rawValue
    }

    /// The language's name in itself ("Hrvatski"), shown under the name in the pickers.
    var nativeName: String {
        Locale(identifier: rawValue).localizedString(forLanguageCode: rawValue)?.localizedCapitalized ?? name
    }

    var flag: String {
        switch rawValue {
        case "eo": "🌍"
        case "cy": "🏴\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}" // Wales
        default: Country.flag(Self.regions[rawValue] ?? "")
        }
    }
}

enum TranslationError: LocalizedError {
    case engineMissing

    var errorDescription: String? {
        String(localized: "Translation engine not installed. Run `pod install` and open Tracker.xcworkspace.")
    }
}

@Observable
final class TranslationEngine {
    private(set) var downloaded: Set<AppLanguage> = []
    private(set) var downloading: Set<AppLanguage> = []

#if canImport(MLKitTranslate)
    private let conditions = ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: true)

    private func mlLanguage(_ language: AppLanguage) -> TranslateLanguage {
        // ML Kit's language constants are the same BCP-47 codes used as raw values here.
        TranslateLanguage(rawValue: language.rawValue)
    }

    private func model(_ language: AppLanguage) -> TranslateRemoteModel {
        TranslateRemoteModel.translateRemoteModel(language: mlLanguage(language))
    }

    func refresh() {
        // English is the pivot every ML Kit model translates through, so it is always on the device.
        downloaded = Set(AppLanguage.allCases.filter { $0 == .english || ModelManager.modelManager().isModelDownloaded(model($0)) })
    }

    /// Downloads the language model (English pivot model ships with ML Kit). No-op when already on device.
    func download(_ language: AppLanguage) async throws {
        guard language != .english else { return }
        downloading.insert(language)
        defer { downloading.remove(language); refresh() }
        let translator = Translator.translator(options: TranslatorOptions(sourceLanguage: mlLanguage(language), targetLanguage: .english))
        try await prepare(translator)
    }

    func delete(_ language: AppLanguage) async {
        guard language != .english else { return }
        await withCheckedContinuation { continuation in
            ModelManager.modelManager().deleteDownloadedModel(model(language)) { _ in continuation.resume() }
        }
        refresh()
    }

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let translator = Translator.translator(options: TranslatorOptions(sourceLanguage: mlLanguage(source), targetLanguage: mlLanguage(target)))
        try await prepare(translator)
        refresh()
        return try await withCheckedThrowingContinuation { continuation in
            translator.translate(text) { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.featureUnsupported))
                }
            }
        }
    }

    private func prepare(_ translator: Translator) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            translator.downloadModelIfNeeded(with: conditions) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
#else
    func refresh() {}
    func download(_ language: AppLanguage) async throws { throw TranslationError.engineMissing }
    func delete(_ language: AppLanguage) async {}
    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        throw TranslationError.engineMissing
    }
#endif
}

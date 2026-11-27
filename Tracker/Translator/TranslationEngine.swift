import Foundation
#if canImport(MLKitTranslate)
import MLKitTranslate
#else
import Translation
#endif

/// On iPhone: Google ML Kit on-device translation. Apple's Translation framework has no Croatian, so ML Kit it is.
/// Each language model (~30 MB) downloads once; after that everything runs offline.
/// On the Mac, where ML Kit doesn't exist: Apple's translator for the languages it has, and the free MyMemory
/// service online for the rest (Croatian among them).
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
    case offline
    case dailyLimit
    case onlineFailed

    var errorDescription: String? {
        switch self {
        case .engineMissing: String(localized: "Translation engine not installed. Run `pod install` and open Tracker.xcworkspace.")
        case .offline: String(localized: "This language is translated online. Connect to the internet and try again.")
        case .dailyLimit: String(localized: "Today's free online translations are used up. They come back tomorrow.")
        case .onlineFailed: String(localized: "The online translation didn't work. Try again in a moment.")
        }
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

    /// Always false on iPhone: every language runs on the device.
    func isOnline(_ language: AppLanguage) -> Bool { false }

    /// The languages of this pair that still have to be downloaded before it translates.
    func missing(_ source: AppLanguage, _ target: AppLanguage) -> [AppLanguage] {
        [source, target].filter { !downloaded.contains($0) }
    }
#else
    /// Languages Apple's translator has on this Mac. The others are translated online.
    private(set) var appleLanguages: Set<AppLanguage> = []
    /// Set while an Apple language is being downloaded; the Offline Languages sheet shows Apple's download prompt for it.
    var preparation: TranslationSession.Configuration?
    private var preparationDone: CheckedContinuation<Void, Never>?

    func isOnline(_ language: AppLanguage) -> Bool { !appleLanguages.contains(language) }

    /// The languages of this pair that still have to be downloaded. A pair with an online language goes
    /// online as a whole, so nothing needs downloading for it.
    func missing(_ source: AppLanguage, _ target: AppLanguage) -> [AppLanguage] {
        guard !isOnline(source), !isOnline(target) else { return [] }
        return [source, target].filter { !downloaded.contains($0) }
    }

    /// Apple's code for a language, where it differs from ML Kit's.
    private func appleCode(_ language: AppLanguage) -> String {
        switch language.rawValue {
        case "no": "nb"
        case "pt": "pt-PT"
        case "ar": "ar-SA"
        default: language.rawValue
        }
    }

    private func locale(_ language: AppLanguage) -> Locale.Language { Locale.Language(identifier: appleCode(language)) }

    /// The language Apple pairs with this one to check whether it's downloaded.
    private func partner(_ language: AppLanguage) -> AppLanguage { language == .english ? .italian : .english }

    func refresh() {
        Task { await reload() }
    }

    private func reload() async {
        let availability = LanguageAvailability()
        let supported = Set(await availability.supportedLanguages.map(\.minimalIdentifier))
        var apple: Set<AppLanguage> = []
        var installed: Set<AppLanguage> = []
        for language in AppLanguage.allCases where supported.contains(appleCode(language)) {
            apple.insert(language)
            if await availability.status(from: locale(language), to: locale(partner(language))) == .installed {
                installed.insert(language)
            }
        }
        appleLanguages = apple
        // Online languages need no download, so they count as ready.
        downloaded = installed.union(AppLanguage.allCases.filter { !apple.contains($0) })
    }

    /// Shows Apple's download prompt for the language (through the Offline Languages sheet) and waits for it.
    func download(_ language: AppLanguage) async throws {
        guard appleLanguages.contains(language), preparation == nil else { return }
        downloading.insert(language)
        defer { downloading.remove(language) }
        await withCheckedContinuation { continuation in
            preparationDone = continuation
            preparation = TranslationSession.Configuration(source: locale(language), target: locale(partner(language)))
        }
        await reload()
    }

    /// Called by the sheet once Apple's prompt is done (downloaded or cancelled).
    func preparationFinished() {
        preparation = nil
        preparationDone?.resume()
        preparationDone = nil
    }

    /// macOS manages downloaded languages itself (System Settings), so there's nothing to delete here.
    func delete(_ language: AppLanguage) async {}

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        if appleLanguages.contains(source) && appleLanguages.contains(target) {
            let session = TranslationSession(installedSource: locale(source), target: locale(target))
            return try await session.translate(text).targetText
        }
        return try await OnlineTranslator.translate(text, from: source.rawValue, to: target.rawValue)
    }
#endif
}

#if !canImport(MLKitTranslate)
/// MyMemory (api.mymemory.translated.net): free, no account or key, about 5,000 characters a day per user.
/// It takes up to 500 bytes per request, so longer text goes sentence by sentence.
nonisolated enum OnlineTranslator {
    static func translate(_ text: String, from source: String, to target: String) async throws -> String {
        var result: [String] = []
        for chunk in chunks(text) {
            result.append(try await translateChunk(chunk, from: source, to: target))
        }
        return result.joined(separator: " ")
    }

    private static func translateChunk(_ text: String, from source: String, to target: String) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "langpair", value: "\(source)|\(target)")]
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: components.url!)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            throw TranslationError.offline
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranslationError.onlineFailed }
        if json["quotaFinished"] as? Bool == true { throw TranslationError.dailyLimit }
        let status = (json["responseStatus"] as? Int) ?? Int(json["responseStatus"] as? String ?? "") ?? 0
        if status == 429 { throw TranslationError.dailyLimit }
        guard status == 200, let reply = json["responseData"] as? [String: Any],
              let translated = reply["translatedText"] as? String, !translated.isEmpty else {
            throw TranslationError.onlineFailed
        }
        return decodeEntities(translated)
    }

    /// Pieces of at most ~450 bytes, cut between sentences (or between words for a very long sentence).
    static func chunks(_ text: String, limit: Int = 450) -> [String] {
        var pieces: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            if sentence.utf8.count <= limit {
                pieces.append(sentence)
            } else {
                var line = ""
                for word in sentence.split(separator: " ") {
                    if !line.isEmpty, line.utf8.count + word.utf8.count + 1 > limit {
                        pieces.append(line)
                        line = ""
                    }
                    line += line.isEmpty ? String(word) : " " + word
                }
                if !line.isEmpty { pieces.append(line) }
            }
        }
        // Join short sentences back together, so a few lines still go in one request.
        var merged: [String] = []
        for piece in pieces {
            if let last = merged.last, last.utf8.count + piece.utf8.count + 1 <= limit {
                merged[merged.count - 1] = last + " " + piece
            } else {
                merged.append(piece)
            }
        }
        return merged.isEmpty ? [text] : merged
    }

    /// MyMemory sometimes returns HTML entities (&#39; for an apostrophe).
    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
#endif

import Foundation
#if canImport(MLKitTranslate)
import MLKitTranslate
#endif

/// Google ML Kit on-device translation. Apple's Translation framework has no Croatian, so ML Kit it is.
/// Each language model (~30 MB) downloads once; after that everything runs offline.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en", italian = "it", turkish = "tr", croatian = "hr", french = "fr", portuguese = "pt"

    var id: String { rawValue }

    /// Voice locale for reading text aloud.
    var speechCode: String {
        switch self {
        case .english: "en-GB"
        case .italian: "it-IT"
        case .turkish: "tr-TR"
        case .croatian: "hr-HR"
        case .french: "fr-FR"
        case .portuguese: "pt-PT"
        }
    }

    var name: String {
        Locale.current.localizedString(forLanguageCode: rawValue)?.localizedCapitalized ?? rawValue
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .italian: "🇮🇹"
        case .turkish: "🇹🇷"
        case .croatian: "🇭🇷"
        case .french: "🇫🇷"
        case .portuguese: "🇵🇹"
        }
    }
}

enum TranslationError: LocalizedError {
    case engineMissing

    var errorDescription: String? {
        "Translation engine not installed. Run `pod install` and open Tracker.xcworkspace."
    }
}

@Observable
final class TranslationEngine {
    private(set) var downloaded: Set<AppLanguage> = []
    private(set) var downloading: Set<AppLanguage> = []

#if canImport(MLKitTranslate)
    private let conditions = ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: true)

    private func mlLanguage(_ language: AppLanguage) -> TranslateLanguage {
        switch language {
        case .english: .english
        case .italian: .italian
        case .turkish: .turkish
        case .croatian: .croatian
        case .french: .french
        case .portuguese: .portuguese
        }
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

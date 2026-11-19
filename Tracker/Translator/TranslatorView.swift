import SwiftUI
import SwiftData
import UIKit
import AVFoundation

struct SavedPhrase: Codable, Identifiable, Hashable {
    var id = UUID()
    let source: AppLanguage
    let target: AppLanguage
    let text: String
    let translation: String
}

struct TranslatorView: View {
    @State private var engine = TranslationEngine()
    @AppStorage("sourceLanguage") private var source: AppLanguage = .italian
    @AppStorage("targetLanguage") private var target: AppLanguage = .croatian
    @State private var input = ""
    @State private var output = ""
    @State private var errorText: String?
    @State private var isTranslating = false
    @State private var showProfile = false
    @State private var showLanguages = false
    @State private var showCalendar = false
    @State private var swapTurns = 0
    @State private var speaker = AVSpeechSynthesizer()
    @AppStorage("savedPhrases") private var savedData = Data()

    private var needsDownload: Bool {
        !engine.downloaded.contains(source) || !engine.downloaded.contains(target)
    }

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var saved: [SavedPhrase] {
        (try? JSONDecoder().decode([SavedPhrase].self, from: savedData)) ?? []
    }

    private var isSaved: Bool {
        saved.contains { $0.source == source && $0.target == target && $0.text == trimmedInput }
    }

    var body: some View {
        NavigationStack {
            // A List (not a ScrollView) so saved phrases get the standard swipe-to-delete.
            List {
                Section { languageBar }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if needsDownload {
                    Section { downloadHint }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section { inputCard }
                Section { outputCard }
                savedSection
            }
            .listSectionSpacing(14)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Translator")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Offline Languages", systemImage: "arrow.down.circle") { showLanguages = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Practice Calendar", systemImage: "calendar") { showCalendar = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: { ProfileIcon() }
                        .accessibilityLabel("My Profile")
                }
            }
            .sheet(isPresented: $showCalendar) { PracticeCalendarSheet() }
            .sheet(isPresented: $showProfile) { CoachProfileSheet() }
            .sheet(isPresented: $showLanguages) { LanguagesSheet(engine: engine) }
            .task(id: "\(source.rawValue)>\(target.rawValue):\(input)") { await translate() }
            .onAppear { engine.refresh() }
        }
    }

    // MARK: Pieces

    private var languageBar: some View {
        HStack(spacing: 8) {
            languageMenu(source) { setSource($0) }
            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .rotationEffect(.degrees(Double(swapTurns) * 180))
            }
            .accessibilityLabel("Swap languages")
            .font(.headline)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .light), trigger: swapTurns)
            languageMenu(target) { setTarget($0) }
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
    }

    private func languageMenu(_ selected: AppLanguage, onPick: @escaping (AppLanguage) -> Void) -> some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    onPick(language)
                } label: {
                    if language == selected {
                        Label("\(language.flag) \(language.name)", systemImage: "checkmark")
                    } else {
                        Text("\(language.flag) \(language.name)")
                    }
                }
            }
        } label: {
            Text("\(selected.flag) \(selected.name)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.capsule)
        }
        .tint(.primary)
    }

    private var downloadHint: some View {
        Button {
            showLanguages = true
        } label: {
            Label("Download \(source.name) and \(target.name) to translate offline", systemImage: "wifi.slash")
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16))
        .tint(.orange)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            TextField("Enter text", text: $input, axis: .vertical)
                .font(.title3)
                .lineLimit(3...12)
            if !input.isEmpty {
                HStack(spacing: 18) {
                    Button("Read Aloud", systemImage: "speaker.wave.2") { speak(input, source) }
                    Spacer()
                    Button("Clear", systemImage: "xmark.circle.fill") { input = "" }
                        .foregroundStyle(.secondary)
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(target.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                if isTranslating { ProgressView() }
            }
            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            } else if output.isEmpty {
                Text("Translation").font(.title3).foregroundStyle(.tertiary)
            } else {
                Text(output).font(.title3).textSelection(.enabled)
                HStack(spacing: 18) {
                    Button("Read Aloud", systemImage: "speaker.wave.2") { speak(output, target) }
                    Spacer()
                    Button(isSaved ? "Remove from Saved" : "Save Phrase", systemImage: isSaved ? "star.fill" : "star") {
                        toggleSaved()
                    }
                    .foregroundStyle(isSaved ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                    .sensoryFeedback(.selection, trigger: isSaved)
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = output }
                    ShareLink(item: output) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }

    private var savedSection: some View {
        Section {
            if saved.isEmpty {
                Text("Tap the star on a translation to keep it here, ready for training.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(saved) { phrase in
                    HStack(spacing: 12) {
                        Button { load(phrase) } label: {
                            HStack(spacing: 12) {
                                Text("\(phrase.source.flag)\n\(phrase.target.flag)")
                                    .font(.callout)
                                    .lineSpacing(2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phrase.text).font(.subheadline.weight(.semibold))
                                    Text(phrase.translation).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Button("Read Aloud", systemImage: "speaker.wave.2") { speak(phrase.translation, phrase.target) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            setSaved(saved.filter { $0.id != phrase.id })
                        }
                    }
                }
            }
        } header: {
            Label("Saved Phrases", systemImage: "star.fill")
                .foregroundStyle(.secondary, .yellow)
        } footer: {
            if !saved.isEmpty { Text("Swipe left on a phrase to delete it.") }
        }
    }

    // MARK: Actions

    private func setSource(_ language: AppLanguage) {
        if language == target { target = source }
        source = language
    }

    private func setTarget(_ language: AppLanguage) {
        if language == source { source = target }
        target = language
    }

    private func swap() {
        withAnimation(.snappy) { swapTurns += 1 }
        (source, target) = (target, source)
        if !output.isEmpty { input = output }
    }

    private func speak(_ text: String, _ language: AppLanguage) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        speaker.speak(utterance)
    }

    private func setSaved(_ phrases: [SavedPhrase]) {
        if let data = try? JSONEncoder().encode(phrases) { savedData = data }
    }

    private func toggleSaved() {
        if isSaved {
            setSaved(saved.filter { !($0.source == source && $0.target == target && $0.text == trimmedInput) })
        } else {
            setSaved([SavedPhrase(source: source, target: target, text: trimmedInput, translation: output)] + saved)
        }
    }

    private func load(_ phrase: SavedPhrase) {
        source = phrase.source
        target = phrase.target
        input = phrase.text
        output = phrase.translation
    }

    private func translate() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            output = ""
            errorText = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(450)) // debounce typing
        guard !Task.isCancelled else { return }
        isTranslating = true
        defer { isTranslating = false }
        do {
            let result = try await engine.translate(text, from: source, to: target)
            guard !Task.isCancelled else { return }
            output = result
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Offline languages

struct LanguagesSheet: View {
    let engine: TranslationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppLanguage.allCases) { language in
                        HStack(spacing: 12) {
                            Text(language.flag).font(.title2)
                            Text(language.name)
                            Spacer()
                            status(language)
                        }
                        .swipeActions {
                            if engine.downloaded.contains(language) && language != .english {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await engine.delete(language) }
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Each language is about 30 MB. Download once on Wi-Fi, then translation works with no internet. Swipe to remove a language.")
                }

                if AppLanguage.allCases.contains(where: { !engine.downloaded.contains($0) }) {
                    Section {
                        Button("Download All", systemImage: "arrow.down.circle.fill") {
                            Task {
                                for language in AppLanguage.allCases where !engine.downloaded.contains(language) {
                                    await download(language)
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Offline Languages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onAppear { engine.refresh() }
        }
    }

    @ViewBuilder
    private func status(_ language: AppLanguage) -> some View {
        if language == .english {
            Text("Built in").foregroundStyle(.secondary)
        } else if engine.downloading.contains(language) {
            ProgressView()
        } else if engine.downloaded.contains(language) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Downloaded")
        } else {
            Button("Download \(language.name)", systemImage: "arrow.down.circle") {
                Task { await download(language) }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
        }
    }

    private func download(_ language: AppLanguage) async {
        do {
            try await engine.download(language)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// The coach's photo as the toolbar profile icon (falls back to the generic symbol).
/// Its own view so typing in the translator doesn't re-decode the photo.
private struct ProfileIcon: View {
    @Query private var coaches: [Coach]

    var body: some View {
        if let data = coaches.first?.photo,
           let image = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 72, height: 72)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                // Same visual size as the SF Symbols next to it (calendar icon).
                .frame(width: 24, height: 24)
                .clipShape(.circle)
        } else {
            Image(systemName: "person.crop.circle")
        }
    }
}

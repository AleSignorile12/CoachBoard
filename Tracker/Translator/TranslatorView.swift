import SwiftUI
#if !canImport(MLKitTranslate)
import Translation
#endif
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
#if targetEnvironment(macCatalyst)
    @Environment(\.inMacShell) private var inMacShell
#else
    private let inMacShell = false
#endif
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
    @State private var picking: LanguageSide?
    @State private var speaker = AVSpeechSynthesizer()
    @State private var speech = SpeechInput()
    @AppStorage("savedPhrases") private var savedData = Data()

    private var missing: [AppLanguage] { engine.missing(source, target) }

    private var needsDownload: Bool { !missing.isEmpty }

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
                if inMacShell {
                    sideBySide
                } else {
                    Section { inputCard }
                        .cardBackground()
                    Section { outputCard }
                        .cardBackground()
                }
                savedSection
            }
            .listSectionSpacing(14)
#if targetEnvironment(macCatalyst)
            // The same 32-point margins as the other Mac pages, using the whole width.
            .contentMargins(.horizontal, inMacShell ? 32 : 0, for: .scrollContent)
#endif
            .macSidebarInset(inMacShell)
            .ambientBackground(macWidth: inMacShell ? .infinity : 760)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Translator")
#if targetEnvironment(macCatalyst)
            .macHidesToolbarTitle()
            .safeAreaInset(edge: .top) {
                MacPageHeader(title: "Translator") {
                    MacHeaderButton(title: LanguagesSheet.title, symbol: LanguagesSheet.symbol) { showLanguages = true }
                }
                    .padding(.horizontal, 32)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity)
                    .macSidebarInset(inMacShell)
            }
#endif
            .toolbar {
                // On the Mac the left of the toolbar is the sidebar's, so it goes right.
                ToolbarItem(placement: inMacShell ? .topBarTrailing : .topBarLeading) {
                    Button(LanguagesSheet.title, systemImage: LanguagesSheet.symbol) { showLanguages = true }
                }
                // On the Mac these two live in the sidebar.
                if !inMacShell {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Practice Calendar", systemImage: "calendar") { showCalendar = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showProfile = true } label: { ProfileIcon() }
                            .accessibilityLabel("My Profile")
                    }
                }
            }
            .sheet(isPresented: $showCalendar) { PracticeCalendarSheet() }
            .sheet(isPresented: $showProfile) { CoachProfileSheet() }
            .sheet(isPresented: $showLanguages) { LanguagesSheet(engine: engine) }
            .sheet(item: $picking) { side in
                LanguagePickerSheet(selected: side == .source ? source : target, engine: engine) { language in
                    side == .source ? setSource(language) : setTarget(language)
                }
            }
            .task(id: "\(source.rawValue)>\(target.rawValue):\(input)") { await translate() }
            .onChange(of: source) { speech.stop() }
            .onDisappear { speech.stop() }
            .onAppear { engine.refresh() }
        }
    }

    // MARK: Pieces

    private var languageBar: some View {
        HStack(spacing: 8) {
            languageButton(source, side: .source)
            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .rotationEffect(.degrees(Double(swapTurns) * 180))
            }
            .accessibilityLabel("Swap languages")
            .font(.headline)
            .popButton()
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .light), trigger: swapTurns)
            languageButton(target, side: .target)
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
    }

    /// Opens the searchable list of all languages (59 is too many for a menu).
    private func languageButton(_ selected: AppLanguage, side: LanguageSide) -> some View {
        Button { picking = side } label: {
            Text("\(selected.flag) \(selected.name)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.capsule)
        }
        .tint(.primary)
        .accessibilityLabel(side == .source ? "From \(selected.name)" : "To \(selected.name)")
        .accessibilityHint("Choose a language")
    }

    private var downloadHint: some View {
        Button {
            showLanguages = true
        } label: {
            Group {
                if missing.count == 1, let language = missing.first {
                    Label("Download \(language.name) to translate offline", systemImage: "wifi.slash")
                } else {
                    Label("Download \(source.name) and \(target.name) to translate offline", systemImage: "wifi.slash")
                }
            }
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16))
        .tint(.orange)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(source.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                micButton
            }
            TextField(speech.isListening ? "Speak now…" : "Enter text", text: $input, axis: .vertical)
                .font(.title3)
                .lineLimit(3...12)
            if speech.isListening {
                Label("Listening in \(source.name)…", systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .transition(.opacity)
            } else if let problem = speech.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if !input.isEmpty {
                HStack(spacing: 18) {
                    if source.voice != nil {
                        Button("Read Aloud", systemImage: "speaker.wave.2") { speak(input, source) }
                    }
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

    /// Mac: the text and its translation next to each other, like two pages.
    @ViewBuilder private var sideBySide: some View {
#if targetEnvironment(macCatalyst)
        Section {
            HStack(alignment: .top, spacing: 16) {
                inputCard
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                    .macPanel()
                outputCard
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                    .macPanel()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
#endif
    }

    /// Speak instead of typing, in the "from" language. Red with a stop square while listening.
    private var micButton: some View {
        Button(action: toggleListening) {
            Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(speech.isListening ? Color.red : Color.brand, in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .overlay {
                    if speech.isListening {
                        // A ring that keeps swelling and fading out, like a sound wave.
                        Circle().stroke(Color.red.opacity(0.5), lineWidth: 3)
                            .phaseAnimator([false, true]) { ring, out in
                                ring.scaleEffect(out ? 1.5 : 1).opacity(out ? 0 : 1)
                            } animation: { out in out ? .easeOut(duration: 1.1) : .linear(duration: 0) }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isListening ? "Stop Listening" : "Speak")
        .help(speech.isListening ? "Stop Listening" : "Speak")
        .sensoryFeedback(.start, trigger: speech.isListening) { _, new in new }
        .sensoryFeedback(.stop, trigger: speech.isListening) { old, _ in old }
        .animation(.snappy, value: speech.isListening)
    }

    private func toggleListening() {
        if speech.isListening {
            speech.stop()
            return
        }
        // What was already typed stays; the spoken words come after it.
        let typed = trimmedInput
        Task {
            await speech.start(source) { spoken in
                input = typed.isEmpty ? spoken : "\(typed) \(spoken)"
            }
        }
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
                    if target.voice != nil {
                        Button("Read Aloud", systemImage: "speaker.wave.2") { speak(output, target) }
                    }
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
        let section = Section {
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
                        if phrase.target.voice != nil {
                            Button("Read Aloud", systemImage: "speaker.wave.2") { speak(phrase.translation, phrase.target) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
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
        return section.cardBackground()
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
        utterance.voice = language.voice
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

// MARK: - Language picker

enum LanguageSide: Identifiable {
    case source, target
    var id: Self { self }
}

extension AppLanguage {
    /// iOS voice for reading aloud, or nil when the phone has none for this language.
    var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: speechCode) ?? AVSpeechSynthesisVoice(language: rawValue)
    }
}

/// One language row: flag, name, the name in that language, and whatever goes on the right.
struct LanguageRow<Accessory: View>: View {
    let language: AppLanguage
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Text(language.flag).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(language.name).foregroundStyle(.primary)
                if language.nativeName != language.name {
                    Text(language.nativeName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            accessory
        }
        .contentShape(.rect)
    }
}

/// Searchable list of every language, downloaded ones first.
struct LanguagePickerSheet: View {
    let selected: AppLanguage
    let engine: TranslationEngine
    let onPick: (AppLanguage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [AppLanguage] {
        search.isEmpty ? AppLanguage.allCases : AppLanguage.allCases.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.nativeName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let onPhone = matches.filter { engine.downloaded.contains($0) }
                if !onPhone.isEmpty {
                    Section("On This iPhone") { ForEach(onPhone) { row($0) } }
                }
                Section {
                    ForEach(matches.filter { !engine.downloaded.contains($0) }) { row($0) }
                } header: {
                    Text("All Languages")
                } footer: {
                    Text("These download the first time you translate with them (about 30 MB each).")
                }
            }
            .overlay { if matches.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search languages")
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .onAppear { engine.refresh() }
        }
    }

    private func row(_ language: AppLanguage) -> some View {
        Button {
            onPick(language)
            dismiss()
        } label: {
            LanguageRow(language: language) {
                if language == selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.brand).fontWeight(.semibold)
                }
            }
        }
        // Black names, not the blue a List gives button labels.
        .tint(.primary)
        .accessibilityAddTraits(language == selected ? .isSelected : [])
    }
}

// MARK: - Offline languages

struct LanguagesSheet: View {
    let engine: TranslationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var search = ""

    private var matches: [AppLanguage] {
        search.isEmpty ? AppLanguage.allCases : AppLanguage.allCases.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.nativeName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
                let onDevice = matches.filter { engine.downloaded.contains($0) && !engine.isOnline($0) }
                let online = matches.filter { engine.isOnline($0) }
                let available = matches.filter { !engine.downloaded.contains($0) }
                if !onDevice.isEmpty { onDeviceSection(onDevice) }
                if !available.isEmpty || !Self.onMac { availableSection(available) }
                if !online.isEmpty { onlineSection(online) }
            }
            .overlay { if matches.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search languages")
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onAppear { engine.refresh() }
#if !canImport(MLKitTranslate)
            // Apple's download prompt for the language the coach picked (Mac only).
            .translationTask(engine.preparation) { session in
                try? await session.prepareTranslation()
                engine.preparationFinished()
            }
#endif
        }
    }

#if targetEnvironment(macCatalyst)
    private static let onMac = true
#else
    private static let onMac = false
#endif

    /// On the Mac the list also holds the online languages, so it isn't only "offline".
    static let title: LocalizedStringKey = onMac ? "Languages" : "Offline Languages"
    static let symbol = onMac ? "globe" : "arrow.down.circle"

    private func onDeviceSection(_ languages: [AppLanguage]) -> some View {
        Section {
            ForEach(languages) { language in
                LanguageRow(language: language) { status(language) }
                    .swipeActions {
                        if language != .english && !Self.onMac {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await engine.delete(language) }
                            }
                        }
                    }
            }
        } header: {
            Text(Self.onMac ? "On This Mac" : "On This iPhone")
        } footer: {
            Text(Self.onMac
                 ? "These work with no internet. To remove one, go to System Settings › General › Language & Region › Translation Languages."
                 : "These work with no internet. Swipe left to remove one.")
        }
    }

    private func availableSection(_ languages: [AppLanguage]) -> some View {
        Section {
            ForEach(languages) { language in
                LanguageRow(language: language) { status(language) }
            }
        } header: {
            Text("Available")
        } footer: {
            Text(Self.onMac
                 ? "macOS downloads these once and shares them with its other apps. Then they work with no internet."
                 : "Each language is about 30 MB. Download on Wi-Fi before training, then translate anywhere.")
        }
    }

    private func onlineSection(_ languages: [AppLanguage]) -> some View {
        Section {
            ForEach(languages) { language in
                LanguageRow(language: language) { status(language) }
            }
        } header: {
            Text("Online")
        } footer: {
            Text("The Mac's own translator doesn't have these, so they're translated online by MyMemory, a free service with no account. It needs the internet and allows about 5,000 characters a day.")
        }
    }

    @ViewBuilder
    private func status(_ language: AppLanguage) -> some View {
        if engine.isOnline(language) {
            Label("Online", systemImage: "cloud")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
        } else if language == .english && !Self.onMac {
            Text("Built in").foregroundStyle(.secondary)
        } else if engine.downloading.contains(language) {
            ProgressView()
        } else if engine.downloaded.contains(language) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
                .accessibilityLabel("Downloaded")
        } else {
            Button("Download \(language.name)", systemImage: "arrow.down.circle") {
                Task { await download(language) }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonStyle(.borderless)
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
        if let data = coaches.first?.photo, let image = Self.round(data) {
            // A finished round picture at its final size (not a resizable image): toolbars, the Mac's above all,
            // stretch a resizable image to the button's shape.
            Image(uiImage: image)
                .renderingMode(.original)
                .accessibilityLabel("My Profile")
        } else {
            Image(systemName: "person.crop.circle")
        }
    }

    /// The photo cropped to a circle with a thin blue ring, the same visual size as the SF Symbols next to it.
    private static func round(_ data: Data) -> UIImage? {
        guard let photo = UIImage(data: data) else { return nil }
        let side: CGFloat = 26
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            // Fill the circle without stretching: scale the shorter side to fit, centre the longer one.
            let scale = side / min(photo.size.width, photo.size.height)
            let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            let circle = UIBezierPath(ovalIn: bounds)
            circle.addClip()
            photo.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
            let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            (UIColor(named: "AccentColor") ?? .systemBlue).setStroke()
            ring.stroke()
        }
    }
}

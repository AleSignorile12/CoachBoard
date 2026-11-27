import SwiftUI
import SwiftData
import UserNotifications

/// First-launch setup, laid out like Apple's own setup screens: a welcome page listing what the app does, then
/// one step per page (name, training days, translator languages, birthday reminders). It's a single screen: the pages
/// sit side by side and slide across, while the dots and the Continue button stay in place. Every step can be skipped
/// and changed later. Shown as a sheet; it can be opened again from the profile.
struct OnboardingView: View {
    /// Opened again from the profile: a close button instead of Skip.
    var isReplay = false
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var coaches: [Coach]
    @AppStorage(TrainingDays.storageKey) private var trainingRaw = TrainingDays.defaultValue
    @AppStorage("sourceLanguage") private var source: AppLanguage = .italian
    @AppStorage("targetLanguage") private var target: AppLanguage = .croatian
    @State private var step = Step.welcome
    @State private var name = ""
    @State private var picking: LanguageSide?
    @State private var engine = TranslationEngine()
    @State private var reminders: UNAuthorizationStatus = .notDetermined
    @State private var finished = false
    @FocusState private var nameFocused: Bool

    enum Step: Int, CaseIterable { case welcome, name, training, languages, birthdays }

    private var trainingDays: Binding<Set<Int>> {
        Binding { TrainingDays.decode(trainingRaw) } set: { trainingRaw = TrainingDays.encode($0) }
    }

    private var askingForReminders: Bool { step == .birthdays && reminders == .notDetermined }

    var body: some View {
        NavigationStack {
            // All the pages side by side; the row glides over by one page width at each step.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(Step.allCases, id: \.self) { item in
                        ScrollView {
                            page(item)
                                .padding(.horizontal, 28)
                                .padding(.top, 12)
                                .padding(.bottom, 24)
                                .frame(maxWidth: .infinity)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollDismissesKeyboard(.interactively)
                        .frame(width: geometry.size.width)
                        // The neighbours fade a little as they slide out, so the current page stands out.
                        .opacity(item == step ? 1 : 0.3)
                        .allowsHitTesting(item == step)
                        .accessibilityHidden(item != step)
                    }
                }
                .offset(x: -CGFloat(step.rawValue) * geometry.size.width)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55), value: step)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.backward") { move(by: -1) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isReplay {
                        Button(role: .close, action: finish)
                    } else {
                        Button("Skip", action: finish)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: finished)
        .sheet(item: $picking) { side in
            LanguagePickerSheet(selected: side == .source ? source : target, engine: engine) { language in
                if side == .source {
                    if language == target { target = source }
                    source = language
                } else {
                    if language == source { source = target }
                    target = language
                }
            }
        }
        .task {
            name = coaches.first?.firstName ?? ""
            reminders = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    // MARK: Sliding

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return finish() }
        if step == .name { saveName() }
        nameFocused = false
        step = next
        // Bring up the keyboard once the name page has slid in.
        if next == .name {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { nameFocused = true }
        }
    }

    // MARK: Pages

    @ViewBuilder private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: welcome
        case .name: namePage
        case .training: training
        case .languages: languages
        case .birthdays: birthdays
        }
    }

    private var welcome: some View {
        VStack(spacing: 36) {
            VStack(spacing: 16) {
                Image("OnboardingIcon")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)
                Text("Welcome to CoachBoard")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(symbol: "person.3.fill", title: "Your Team",
                           text: "Every kid with age, nationality, parents and notes.")
                FeatureRow(symbol: "eurosign.circle.fill", title: "Payments",
                           text: "Monthly fees and registrations, month by month.")
                FeatureRow(symbol: "checkmark.seal.fill", title: "Documents",
                           text: "Medical certificates and IDs, always with you.")
                FeatureRow(symbol: "translate", title: "Translator",
                           text: "Talk to every kid in their language, even offline.")
            }
        }
    }

    private var namePage: some View {
        VStack(spacing: 28) {
            StepHeader(symbol: "person.crop.circle.fill", title: "What's your name?",
                       text: "So the app knows who's in charge. You can add the rest later in your profile.")
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.next)
                .focused($nameFocused)
                .onSubmit { move(by: 1) }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        }
    }

    private var training: some View {
        VStack(spacing: 28) {
            StepHeader(symbol: "calendar", title: "When do you train?",
                       text: "Only these days can be marked in the practice calendar. You can change them there anytime.")
            VStack(spacing: 12) {
                SportPicker(standalone: true)
                    .padding(.bottom, 2)
                Divider()
                WeekdayPicker(days: trainingDays)
                Text(trainingDays.wrappedValue.isEmpty ? String(localized: "No days picked yet")
                     : TrainingDays.list(trainingDays.wrappedValue, type: .and))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        }
    }

    private var languages: some View {
        VStack(spacing: 28) {
            StepHeader(symbol: "translate", title: "Which languages?",
                       text: "Pick yours and the one the kids speak. The translator knows 59 and works offline once a language is downloaded.")
            VStack(spacing: 0) {
                languageRow("You speak", source, side: .source)
                Divider().padding(.leading, 16)
                languageRow("The kids speak", target, side: .target)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        }
    }

    private var birthdays: some View {
        VStack(spacing: 28) {
            StepHeader(symbol: "birthday.cake.fill", title: "Never miss a birthday",
                       text: "A reminder a week before, two days before and on the day, plus a little party when you open the app.")
            switch reminders {
            case .authorized, .provisional, .ephemeral:
                Label("Reminders are on", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            case .denied:
                Text("Notifications are off for CoachBoard. You can turn them on in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            default:
                EmptyView()
            }
        }
    }

    // MARK: Bottom bar (stays put while the pages slide)

    private var bottomBar: some View {
        VStack(spacing: 14) {
            PageDots(current: step.rawValue, count: Step.allCases.count)
                .padding(.bottom, 4)
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            // Same height on every step, so the button doesn't jump while the text under it changes.
            ZStack {
                if step == .welcome {
                    // Change the app's language before reading the rest (opens Tracker's page in Settings).
                    Button("App Language: \(AppLanguageSetting.currentName)") { openURL(AppLanguageSetting.settingsURL) }
                        .transition(.opacity)
                } else if askingForReminders {
                    Button("Not Now", action: finish)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 22)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.4), value: step)
    }

    private var primaryTitle: LocalizedStringKey {
        if step != .birthdays { return "Continue" }
        return reminders == .notDetermined ? "Turn On Reminders" : "Get Started"
    }

    private func primaryAction() {
        if askingForReminders {
            Task { await askForReminders() }
        } else {
            move(by: 1)
        }
    }

    // MARK: Pieces

    private func languageRow(_ title: LocalizedStringKey, _ language: AppLanguage, side: LanguageSide) -> some View {
        Button { picking = side } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(language.flag) \(language.name)").foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    // MARK: Actions

    private func finish() {
        saveName()
        finished = true
        onFinish()
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let coach = coaches.first {
            coach.firstName = trimmed
        } else {
            let coach = Coach()
            coach.firstName = trimmed
            context.insert(coach)
        }
    }

    private func askForReminders() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        reminders = await center.notificationSettings().authorizationStatus
        finish()
    }
}

/// Symbol, title and explanation at the top of a step.
private struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .frame(height: 64)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// A line of the welcome page: blue symbol, bold title, short explanation.
private struct FeatureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The page dots: the current one is a longer blue capsule that glides along as the pages slide.
private struct PageDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.smooth(duration: 0.5), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

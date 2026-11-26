import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrackerApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        #if DEBUG
        SelfCheck.run()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Self.container)
    }

    static let iCloudContainer = "iCloud.com.alessandrosignorile.Tracker"
    /// False when this build can't use iCloud (then everything stays on this iPhone, as before).
    private(set) static var syncsWithICloud = false

    /// Same store file as before (so existing data is kept), now mirrored to the coach's private iCloud database.
    /// Without an iCloud account it keeps working on this iPhone and syncs once the coach signs in.
    static let container: ModelContainer = {
        let types: [any PersistentModel.Type] = [Kid.self, Coach.self, StoredFile.self, PaymentEntry.self, PracticeDay.self]
        #if DEBUG
        CloudKitSchema.initializeIfAsked(types: types, container: iCloudContainer)
        #endif
        let schema = Schema(types)
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                schema: schema, cloudKitDatabase: .private(iCloudContainer)))
            syncsWithICloud = true
            return container
        } catch {
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
            } catch {
                fatalError("Couldn't open the data store: \(error)")
            }
        }
    }()
}

private struct RootView: View {
    @Query private var kids: [Kid]
    @Environment(\.scenePhase) private var scenePhase
    @State private var celebrating: [String]?
    @AppStorage("didOnboard") private var didOnboard = false
    /// The animated whistle at launch; the onboarding sheet waits for it to finish.
    @State private var showSplash = true
    @Query private var paymentEntries: [PaymentEntry]
    @AppStorage(TrainingDays.storageKey) private var trainingRaw = TrainingDays.defaultValue

    /// What the Home and Lock Screen widgets show (rebuilt whenever kids, payments, training days or the date change).
    private var widgetSnapshot: WidgetSnapshot {
        WidgetSnapshot(kids: kids, entries: paymentEntries, trainingRaw: trainingRaw)
    }

    private var birthdays: [BirthdayReminders.Person] {
        kids.filter { !$0.birthDateUnknown }.map {
            .init(firstName: $0.firstName.isEmpty ? $0.fullName : $0.firstName, birthDate: $0.birthDate)
        }
    }

    var body: some View {
        TabView {
            Tab("Translator", systemImage: "translate") { TranslatorView() }
            Tab("Kids", systemImage: "person.3") { KidsView() }
            Tab("Payments", systemImage: "eurosign.circle") { PaymentsView() }
            Tab("Certifications", systemImage: "checkmark.seal") { CertificationsView() }
        }
        .background { KeepTabBarTinted() }
        .sheet(isPresented: Binding { !didOnboard && !showSplash } set: { didOnboard = !$0 }) {
            OnboardingView { didOnboard = true }
                // First launch: closed with Skip or Let's Go, not by an accidental swipe.
                .interactiveDismissDisabled()
        }
        .overlay {
            if let names = celebrating {
                CelebrationOverlay(names: names) { celebrating = nil }
            }
        }
        .overlay {
            if showSplash { LaunchSplash { showSplash = false } }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in AppLock.shared.scenePhaseChanged(phase) }
        .task(id: widgetSnapshot) { widgetSnapshot.publish() }
        // Runs at launch and again whenever a name or birthday changes.
        .task(id: birthdays) { await BirthdayReminders.reschedule(birthdays) }
        // Every time the app is opened on someone's birthday.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, celebrating == nil else { return }
            let names = kids.filter(\.isBirthdayToday).map { $0.firstName.isEmpty ? $0.fullName : $0.firstName }
            if !names.isEmpty { celebrating = names.sorted() }
        }
    }
}

/// Shows birthday notifications as banners even while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

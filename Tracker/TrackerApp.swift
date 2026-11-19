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
        .modelContainer(for: [Kid.self, Coach.self, StoredFile.self, PaymentEntry.self, PracticeDay.self])
    }
}

private struct RootView: View {
    @Query private var kids: [Kid]
    @Environment(\.scenePhase) private var scenePhase
    @State private var celebrating: [String]?

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
        .overlay {
            if let names = celebrating {
                CelebrationOverlay(names: names) { celebrating = nil }
            }
        }
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

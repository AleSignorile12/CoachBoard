import Foundation

/// Keeps the club's settings (fee plans and amounts, registration, season, currency, tracked certificates,
/// training days, sport, report language) the same on the coach's iPhone and Mac, through iCloud's key-value
/// store. Kids, payments and documents already sync through iCloud with SwiftData; these live in UserDefaults
/// (read with @AppStorage), so each change is copied to iCloud and changes from the other device are copied back.
/// Device preferences (app language, Face ID lock, translator languages) stay on each device.
enum SettingsSync {
    static let keys = [
        FeePlans.storageKey, FeeAmounts.registrationKey, SeasonSettings.registrationOnKey, SeasonSettings.startKey,
        Money.storageKey, CertificationTypes.storageKey, TrainingDays.storageKey, Sport.storageKey,
        ReportLanguage.storageKey,
        // The amounts from before fee plans: still read until the coach first edits the plans.
        FeeAmounts.standardKey, FeeAmounts.siblingKey, FeeAmounts.friendKey,
    ]

    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        cloud.synchronize()

        // First run on a device: what's already in iCloud wins (a new Mac takes the iPhone's settings), and
        // whatever iCloud doesn't have yet is sent up.
        for key in keys {
            if let value = cloud.object(forKey: key) {
                local.set(value, forKey: key)
            } else if let value = local.object(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }

        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloud, queue: .main) { note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? keys
            for key in changed where keys.contains(key) {
                if let value = cloud.object(forKey: key) {
                    if !same(local.object(forKey: key), value) { local.set(value, forKey: key) }
                } else {
                    local.removeObject(forKey: key)
                }
            }
        }

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: local, queue: .main) { _ in
            for key in keys {
                guard let value = local.object(forKey: key) else { continue }
                if !same(cloud.object(forKey: key), value) { cloud.set(value, forKey: key) }
            }
        }
    }

    private static func same(_ a: Any?, _ b: Any) -> Bool {
        guard let a = a as? NSObject, let b = b as? NSObject else { return false }
        return a.isEqual(b)
    }
}

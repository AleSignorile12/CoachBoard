import Foundation

// This file is copied as-is into TrackerWidget/Snapshot.swift: keep the two the same.

/// What the widgets show, saved by the app into the shared App Group whenever kids, payments or training days
/// change. The widgets can't open the app's database, so they read this small summary instead.
nonisolated struct WidgetSnapshot: Codable, Equatable {
    struct Birthday: Codable, Equatable {
        var name: String
        var birthDate: Date
    }

    var birthdays: [Birthday] = []
    /// Month of the payment numbers (yyyymm) and its name in the app's language.
    var month: Int = 0
    var monthTitle: String = ""
    var paid: Int = 0
    var total: Int = 0
    /// First names of the kids who haven't paid this month, A–Z.
    var unpaid: [String] = []
    /// Training weekdays (Sunday = 1).
    var trainingWeekdays: [Int] = []

    static let appGroup = "group.com.alessandrosignorile.Tracker"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot; returns true when it changed (so the widgets only reload when needed).
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL, Self.load() != self, let data = try? JSONEncoder().encode(self) else { return false }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    // MARK: Dates the widgets need

    /// Next time each kid has a birthday, soonest first (today counts as next).
    func upcomingBirthdays(from now: Date, calendar: Calendar = .current) -> [(name: String, date: Date, age: Int)] {
        let today = calendar.startOfDay(for: now)
        return birthdays.compactMap { birthday in
            let parts = calendar.dateComponents([.month, .day], from: birthday.birthDate)
            guard let next = calendar.nextDate(after: today.addingTimeInterval(-1), matching: parts,
                                               matchingPolicy: .nextTimePreservingSmallerComponents) else { return nil }
            let age = calendar.dateComponents([.year], from: birthday.birthDate, to: next).year ?? 0
            return (birthday.name, next, age)
        }
        .sorted { $0.date < $1.date }
    }

    /// The next training day from today (today included), or nil when no days are set.
    func nextPractice(from now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        return (0..<7).lazy
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .first { trainingWeekdays.contains(calendar.component(.weekday, from: $0)) }
    }
}

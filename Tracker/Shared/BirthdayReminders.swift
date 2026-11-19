import Foundation
import UserNotifications

/// Birthday notifications: a week before and 2 days before (10:00), then on the day at 00:00, 09:00 and 13:00.
/// shortcut: iOS keeps at most 64 pending notifications per app, so only the soonest 60 are scheduled and the
/// list is rebuilt whenever the app opens or a kid changes. Upgrade to a push server if you ever need more.
enum BirthdayReminders {
    struct Person: Hashable {
        /// Notifications use the first name only.
        let firstName: String
        let birthDate: Date
    }

    struct Reminder {
        let date: Date
        let title: String
        let body: String
    }

    private static let prefix = "birthday-"

    static func reschedule(_ people: [Person]) async {
        // Debounce: typing a name changes `people` on every keystroke.
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !people.isEmpty,
              (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let now = Date.now
        let soonest = people.flatMap { upcoming(for: $0, after: now) }.sorted { $0.date < $1.date }.prefix(60)
        for reminder in soonest {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let request = UNNotificationRequest(identifier: prefix + UUID().uuidString, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    /// Reminders for the next two birthdays that are still in the future.
    static func upcoming(for person: Person, after now: Date, calendar: Calendar = .current) -> [Reminder] {
        let monthDay = calendar.dateComponents([.month, .day], from: person.birthDate)
        var from = calendar.startOfDay(for: now).addingTimeInterval(-1)
        var result: [Reminder] = []
        for _ in 0..<2 {
            // 29 February falls back to 28 February in non-leap years.
            guard let birthday = calendar.nextDate(after: from, matching: monthDay,
                                                   matchingPolicy: .previousTimePreservingSmallerComponents) else { break }
            from = birthday
            // Calendar years only: the stored birth date also carries a time of day, which made
            // "from birth to midnight of the birthday" one year short.
            let age = calendar.component(.year, from: birthday) - calendar.component(.year, from: person.birthDate)
            let day = birthday.formatted(.dateTime.weekday(.wide).day().month(.wide))
            let name = person.firstName
            func at(_ daysBefore: Int, _ hour: Int) -> Date {
                let date = calendar.date(byAdding: .day, value: -daysBefore, to: birthday) ?? birthday
                return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            }
            result += [
                Reminder(date: at(7, 10), title: "🎂 \(name)'s birthday in one week",
                         body: "\(name) turns \(age) on \(day)."),
                Reminder(date: at(2, 10), title: "🎂 \(name)'s birthday in 2 days",
                         body: "\(name) turns \(age) on \(day)."),
                Reminder(date: at(0, 0), title: "🎂 Today is \(name)'s birthday!",
                         body: "\(name) turns \(age) today."),
                Reminder(date: at(0, 9), title: "🎂 \(name) turns \(age) today",
                         body: "Don't forget to wish \(name) a happy birthday!"),
                Reminder(date: at(0, 13), title: "🎂 Birthday reminder",
                         body: "\(name) turns \(age) today 🎉"),
            ]
        }
        return result.filter { $0.date > now }
    }

    /// Age on a given day, by calendar date only (the birth date's time of day is ignored).
    static func age(born: Date, on date: Date, calendar: Calendar = .current) -> Int {
        let b = calendar.dateComponents([.year, .month, .day], from: born)
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        let reached = (d.month ?? 0, d.day ?? 0) >= (b.month ?? 0, b.day ?? 0)
        return (d.year ?? 0) - (b.year ?? 0) - (reached ? 0 : 1)
    }

    /// True on the birthday (29 February counts on 28 February in non-leap years).
    static func isBirthday(born: Date, on date: Date, calendar: Calendar = .current) -> Bool {
        let b = calendar.dateComponents([.month, .day], from: born)
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        if b.month == d.month && b.day == d.day { return true }
        let leapYear = calendar.range(of: .day, in: .year, for: date)?.count == 366
        return b.month == 2 && b.day == 29 && !leapYear && d.month == 2 && d.day == 28
    }
}

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// One entry per day for the next week (birthday countdowns and "next practice" change at midnight).
/// The app also asks for a reload whenever its data changes.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .sample) : (WidgetSnapshot.load() ?? WidgetSnapshot())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let today = Calendar.current.startOfDay(for: .now)
        let entries = [SnapshotEntry(date: .now, snapshot: snapshot)] + (1...7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: today).map { SnapshotEntry(date: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery before the app has saved anything.
    static let sample = WidgetSnapshot(
        birthdays: [Birthday(name: "Sofia", birthDate: Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.date(byAdding: .year, value: -9, to: .now)!)!),
                    Birthday(name: "Luka", birthDate: Calendar.current.date(byAdding: .day, value: 12, to: Calendar.current.date(byAdding: .year, value: -10, to: .now)!)!)],
        month: 0, monthTitle: Date.now.formatted(.dateTime.month(.wide).year()),
        paid: 12, total: 15, unpaid: ["Emre", "Inês", "Amara"], trainingWeekdays: [3, 5])
}

/// "Today", "Tomorrow" or "In 5 days".
private func countdown(to date: Date, from now: Date) -> String {
    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: date).day ?? 0
    switch days {
    case ...0: return String(localized: "Today")
    case 1: return String(localized: "Tomorrow")
    default: return String(localized: "In \(days) days")
    }
}

/// Soft blue wash behind the Home Screen widgets, like the app's background.
private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.04)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .background(Color(.systemBackground))
    }
}

private struct WidgetTitle: View {
    let text: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .lineLimit(1)
    }
}

// MARK: - Birthdays

struct BirthdaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Birthdays", provider: SnapshotProvider()) { entry in
            BirthdaysView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Next Birthdays")
        .description("The kids who have a birthday coming up.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct BirthdaysView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var upcoming: [(name: String, date: Date, age: Int)] {
        entry.snapshot.upcomingBirthdays(from: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let next = upcoming.first {
                Label("\(next.name) · \(countdown(to: next.date, from: entry.date))", systemImage: "birthday.cake")
            } else {
                Label("No birthdays", systemImage: "birthday.cake")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Birthday", systemImage: "birthday.cake.fill").font(.caption.weight(.semibold))
                if let next = upcoming.first {
                    Text(next.name).font(.headline).widgetAccentable()
                    Text("\(countdown(to: next.date, from: entry.date)) · turns \(next.age)").font(.caption)
                } else {
                    Text("Add birth dates in Tracker").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetTitle(text: "Birthdays", symbol: "birthday.cake.fill")
                if upcoming.isEmpty {
                    Spacer()
                    Text("Add birth dates in Tracker").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { index, birthday in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(birthday.name)
                                .font(index == 0 ? .headline : .subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(countdown(to: birthday.date, from: entry.date)) · turns \(birthday.age)")
                                .font(.caption)
                                .foregroundStyle(index == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Payments

struct PaymentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Payments", provider: SnapshotProvider()) { entry in
            PaymentsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Payments")
        .description("Who paid this month's fee and who still has to.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct PaymentsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(snapshot.paid), in: 0...Double(max(snapshot.total, 1))) {
                Image(systemName: "eurosign")
            } currentValueLabel: {
                Text("\(snapshot.paid)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Payments", systemImage: "eurosign.circle.fill").font(.caption.weight(.semibold))
                Text("\(snapshot.paid) of \(snapshot.total) paid").font(.headline).widgetAccentable()
                Text(snapshot.unpaid.isEmpty ? String(localized: "Everyone paid") : snapshot.unpaid.formatted(.list(type: .and)))
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetTitle(text: "Payments", symbol: "eurosign.circle.fill")
                Text(snapshot.monthTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(snapshot.paid)").font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("/ \(snapshot.total)").font(.headline).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(snapshot.paid), total: Double(max(snapshot.total, 1)))
                if snapshot.total > 0 {
                    Text(snapshot.unpaid.isEmpty ? String(localized: "Everyone paid") : snapshot.unpaid.formatted(.list(type: .and)))
                        .font(.caption)
                        .foregroundStyle(snapshot.unpaid.isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
                        .lineLimit(2)
                } else {
                    Text("No kids on this month's list").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Practice

struct PracticeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Practice", provider: SnapshotProvider()) { entry in
            PracticeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Next Practice")
        .description("When the team trains next.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct PracticeWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var next: Date? { entry.snapshot.nextPractice(from: entry.date) }

    private var dayText: String {
        guard let next else { return String(localized: "No training days") }
        if Calendar.current.isDate(next, inSameDayAs: entry.date) { return String(localized: "Today") }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: entry.date),
           Calendar.current.isDate(next, inSameDayAs: tomorrow) { return String(localized: "Tomorrow") }
        return next.formatted(.dateTime.weekday(.wide)).localizedCapitalized
    }

    private var weekdays: String {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return entry.snapshot.trainingWeekdays.map { symbols[$0 - 1] }.formatted(.list(type: .and))
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Practice: \(dayText)", systemImage: "figure.run")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Next Practice", systemImage: "figure.run").font(.caption.weight(.semibold))
                Text(dayText).font(.headline).widgetAccentable()
                if let next { Text(next.formatted(.dateTime.day().month(.wide))).font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetTitle(text: "Next Practice", symbol: "figure.run")
                Spacer(minLength: 0)
                Text(dayText)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let next {
                    Text(next.formatted(.dateTime.day().month(.wide))).font(.subheadline).foregroundStyle(.secondary)
                }
                if !weekdays.isEmpty {
                    Text(weekdays).font(.caption).foregroundStyle(.tint).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

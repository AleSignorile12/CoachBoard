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
struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.04)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .background(Color(.systemBackground))
    }
}

/// Every Home Screen widget starts the same way: symbol and title in the app's blue, optional detail on the right.
private struct WidgetHeader: View {
    let text: LocalizedStringKey
    let symbol: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text).lineLimit(1)
            Spacer(minLength: 4)
            if let detail {
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
        .widgetAccentable()
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
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
                    Text(next.name).font(.headline).widgetAccentable().lineLimit(1)
                    Text("\(countdown(to: next.date, from: entry.date)) · turns \(next.age)").font(.caption).lineLimit(1)
                } else {
                    Text("Add birth dates in CoachBoard").font(.caption).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(text: "Birthdays", symbol: "birthday.cake.fill")
                if upcoming.isEmpty {
                    Spacer(minLength: 0)
                    emptyText
                } else {
                    Spacer(minLength: 6)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { index, birthday in
                            row(birthday, highlighted: index == 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                WidgetHeader(text: "Birthdays", symbol: "birthday.cake.fill")
                Spacer(minLength: 0)
                if let next = upcoming.first {
                    Text(next.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(countdown(to: next.date, from: entry.date)) · turns \(next.age)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if upcoming.count > 1 {
                        let then = upcoming[1]
                        Text("Then \(then.name), \(countdown(to: then.date, from: entry.date).lowercased(with: .current))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.top, 4)
                    }
                } else {
                    emptyText
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyText: some View {
        Text("Add birth dates in CoachBoard").font(.footnote).foregroundStyle(.secondary).lineLimit(3)
    }

    /// A date badge (day and month, like a tear-off calendar) next to the name and countdown.
    private func row(_ birthday: (name: String, date: Date, age: Int), highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: -2) {
                Text(birthday.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 8, weight: .bold))
                Text(birthday.date.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .frame(width: 34, height: 30)
            .background(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14)), in: .rect(cornerRadius: 8))
            .widgetAccentable()
            Text(birthday.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(countdown(to: birthday.date, from: entry.date)) · turns \(birthday.age)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// How much of the month's list has paid, as a ring.
private struct PaidRing: View {
    let paid: Int
    let total: Int
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(paid) / CGFloat(total) : 0)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }
}

struct PaymentsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var month: String {
        guard snapshot.month > 0, let date = Calendar.current.date(from: DateComponents(year: snapshot.month / 100, month: snapshot.month % 100))
        else { return snapshot.monthTitle }
        return date.formatted(.dateTime.month(.abbreviated))
    }
    private var stillToPay: String {
        snapshot.unpaid.isEmpty ? String(localized: "Everyone paid") : snapshot.unpaid.formatted(.list(type: .and))
    }

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
                Text(stillToPay).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(text: "Payments", symbol: "eurosign.circle.fill", detail: snapshot.monthTitle)
                Spacer(minLength: 8)
                HStack(spacing: 16) {
                    ZStack {
                        PaidRing(paid: snapshot.paid, total: snapshot.total, lineWidth: 9)
                        VStack(spacing: -2) {
                            Text("\(snapshot.paid)").font(.system(.title, design: .rounded).weight(.bold))
                            Text("/ \(snapshot.total)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        if snapshot.total == 0 {
                            Text("No kids on this month's list").font(.subheadline).foregroundStyle(.secondary)
                        } else if snapshot.unpaid.isEmpty {
                            Label("Everyone paid", systemImage: "checkmark.circle.fill")
                                .font(.headline).foregroundStyle(.tint)
                        } else {
                            Text("Still to pay").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(snapshot.unpaid.prefix(3), id: \.self) { name in
                                Label {
                                    Text(name).lineLimit(1)
                                } icon: {
                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                }
                                .font(.subheadline.weight(.medium))
                            }
                            if snapshot.unpaid.count > 3 {
                                Text("+\(snapshot.unpaid.count - 3)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(text: "Payments", symbol: "eurosign.circle.fill", detail: month)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(snapshot.paid)").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("/ \(snapshot.total)").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                Capsule()
                    .fill(.tint.opacity(0.18))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule().fill(.tint)
                                .frame(width: snapshot.total > 0 ? geometry.size.width * CGFloat(snapshot.paid) / CGFloat(snapshot.total) : 0)
                                .widgetAccentable()
                        }
                    }
                    .padding(.bottom, 8)
                Text(snapshot.total > 0 ? stillToPay : String(localized: "No kids on this month's list"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(snapshot.total == 0 ? AnyShapeStyle(.secondary)
                                     : snapshot.unpaid.isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
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

    /// The next seven days starting today, for the week strip.
    private var week: [Date] {
        let today = Calendar.current.startOfDay(for: entry.date)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func trains(on day: Date) -> Bool {
        entry.snapshot.trainingWeekdays.contains(Calendar.current.component(.weekday, from: day))
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
        case .systemMedium:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(text: "Next Practice", symbol: "figure.run")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(dayText)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let next {
                        Text(next.formatted(.dateTime.day().month(.wide)))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.bottom, 10)
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        dayCell(day, large: true).frame(maxWidth: .infinity)
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(text: "Next Practice", symbol: "figure.run")
                Spacer(minLength: 0)
                Text(dayText)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let next {
                    Text(next.formatted(.dateTime.day().month(.wide))).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        dayCell(day, large: false).frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One day of the strip: its initial (and date on the medium widget); filled on the next practice, ringed on
    /// the other training days.
    private func dayCell(_ day: Date, large: Bool) -> some View {
        let isNext = next.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        let training = trains(on: day)
        let size: CGFloat = large ? 30 : 19
        return VStack(spacing: 3) {
            if large {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(large ? day.formatted(.dateTime.day()) : day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: large ? 13 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(isNext ? AnyShapeStyle(.white) : training ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .background {
                    if isNext {
                        Circle().fill(.tint).widgetAccentable()
                    } else if training {
                        Circle().strokeBorder(.tint, lineWidth: 1.5).widgetAccentable()
                    }
                }
        }
    }
}

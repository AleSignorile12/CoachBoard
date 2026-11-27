#if targetEnvironment(macCatalyst)
import SwiftUI
import SwiftData

/// The Mac's first screen: the team at a glance, this month's money and what still needs doing.
struct MacOverview: View {
    @Binding var section: MacSection?
    @Environment(MacModals.self) private var modals
    @Query(sort: [SortDescriptor(\Kid.firstName), SortDescriptor(\Kid.lastName)]) private var kids: [Kid]
    @Query private var entries: [PaymentEntry]
    @Query private var coaches: [Coach]
    @AppStorage(TrainingDays.storageKey) private var trainingRaw = TrainingDays.defaultValue

    private let month = Month.key(.now)

    private var monthEntries: [PaymentEntry] { entries.filter { $0.month == month && $0.kid != nil } }
    private var total: Int { monthEntries.reduce(0) { $0 + $1.lineTotal } }
    private var collected: Int { monthEntries.reduce(0) { $0 + $1.collected } }
    private var unpaid: [PaymentEntry] {
        monthEntries.filter { !$0.settled }.sorted { $0.kidName.localizedStandardCompare($1.kidName) == .orderedAscending }
    }
    private var incomplete: [Kid] { kids.filter { !$0.certificationsComplete } }
    private var birthdays: [Kid] {
        kids.filter { $0.hasBirthday(inMonth: month) }
            .sorted { Calendar.current.component(.day, from: $0.birthDate) < Calendar.current.component(.day, from: $1.birthDate) }
    }

    /// The next training day from today on.
    private var nextPractice: Date? {
        let days = TrainingDays.decode(trainingRaw)
        guard !days.isEmpty else { return nil }
        let calendar = Calendar.current
        return (0..<8).lazy
            .compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: .now)) }
            .first { days.contains(calendar.component(.weekday, from: $0)) }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = coaches.first?.firstName ?? ""
        let hello = hour < 12 ? String(localized: "Good morning") : hour < 18 ? String(localized: "Good afternoon") : String(localized: "Good evening")
        return name.isEmpty ? hello : "\(hello), \(name)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MacPageHeader(title: "Overview",
                                  subtitle: "\(greeting) · \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))")
                    stats
                    // Two columns that each stack their own panels, so a short panel never leaves a hole under it.
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            toCollect
                            birthdaysPanel
                        }
                        documents
                    }
                }
                // Same left edge as the other pages, using the whole width.
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .macPage()
            .navigationTitle("Overview")
            .macHidesToolbarTitle()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var stats: some View {
        // All five numbers in one row, sharing the full width as the window grows.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 5), spacing: 20) {
            MacStat(title: "Kids", symbol: "person.3", value: "\(kids.count)",
                    detail: String(localized: "\(Set(kids.map(\.countryCode)).count) nationalities"))
                .macOpens("Open Kids") { section = .kids }
            MacStat(title: "Collected", symbol: Money.icon, value: collected.euros,
                    detail: String(localized: "of \(total.euros) in \(Month.title(month))"),
                    color: .brand, progress: total == 0 ? 0 : Double(collected) / Double(total))
                .macOpens("Open Payments") { section = .payments }
            MacStat(title: "Missing", symbol: "hourglass", value: (total - collected).euros,
                    detail: String(localized: "\(unpaid.count) kids still to pay"),
                    color: total == collected ? .secondary : .orange)
                .macOpens("Open Payments") { section = .payments }
            MacStat(title: "Certifications", symbol: "checkmark.seal",
                    value: "\(kids.count - incomplete.count)/\(kids.count)",
                    detail: String(localized: "kids with every document"),
                    progress: kids.isEmpty ? 0 : Double(kids.count - incomplete.count) / Double(kids.count))
                .macOpens("Open Certifications") { section = .certifications }
            MacStat(title: "Next Practice", symbol: "calendar",
                    value: nextPractice.map { Calendar.current.isDateInToday($0) ? String(localized: "Today") : $0.formatted(.dateTime.weekday(.abbreviated).day()) } ?? "—",
                    detail: TrainingDays.list(TrainingDays.decode(trainingRaw), type: .and))
                .macOpens("Practice Calendar") { modals.present(PracticeCalendarSheet()) }
        }
    }

    private var toCollect: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacPanelHeader(title: String(localized: "To Collect in \(Month.title(month))"), symbol: Money.icon,
                           action: ("Open Payments", { section = .payments }))
            if monthEntries.isEmpty {
                empty("No list for this month yet.")
            } else if unpaid.isEmpty {
                empty("Everyone has paid. 🎉")
            } else {
                ForEach(unpaid.prefix(8)) { entry in
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.snappy) {
                                entry.paid = true
                                entry.charges?.forEach { $0.paid = true }
                            }
                        } label: {
                            Image(systemName: "circle").font(.title3).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Mark as Paid")
                        .accessibilityLabel("Mark as Paid")
                        FlagBadge(code: entry.kid?.countryCode ?? "", size: 26)
                        Text(entry.kidName).lineLimit(1)
                        Spacer()
                        Text(entry.feeTitle).font(.caption).foregroundStyle(.secondary)
                        Text((entry.lineTotal - entry.collected).euros).monospacedDigit().fontWeight(.semibold)
                    }
                    .contentShape(.rect)
                    .onTapGesture { section = .payments }
                    if entry !== unpaid.prefix(8).last { Divider() }
                }
                if unpaid.count > 8 {
                    Text("and \(unpaid.count - 8) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macPanel()
    }

    private var documents: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacPanelHeader(title: String(localized: "Missing Documents"), symbol: "doc.badge.clock",
                           action: ("Open Certifications", { section = .certifications }))
            if kids.isEmpty {
                empty("No kids yet.")
            } else if incomplete.isEmpty {
                empty("Every document is in. ✅")
            } else {
                ForEach(incomplete.prefix(8)) { kid in
                    HStack(spacing: 10) {
                        FlagBadge(code: kid.countryCode, size: 26)
                        Text(kid.fullName).lineLimit(1)
                        Spacer()
                        ForEach(FileKind.certifications, id: \.self) { kind in
                            Image(systemName: kind.icon)
                                .foregroundStyle(kid.file(kind) == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.quaternary))
                                .help(kid.file(kind) == nil ? String(localized: "\(kind.title) missing") : kind.title)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { section = .certifications }
                    if kid !== incomplete.prefix(8).last { Divider() }
                }
                if incomplete.count > 8 {
                    Text("and \(incomplete.count - 8) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macPanel()
    }

    private var birthdaysPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacPanelHeader(title: String(localized: "Birthdays in \(Month.title(month))"), symbol: "birthday.cake")
            if birthdays.isEmpty {
                empty("No birthdays this month.")
            } else {
                ForEach(birthdays) { kid in
                    HStack(spacing: 10) {
                        FlagBadge(code: kid.countryCode, size: 26)
                        Text(kid.fullName).lineLimit(1)
                        Spacer()
                        Text(kid.birthDate, format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(.secondary)
                        Text("turns \(kid.age + (birthdayPassed(kid) ? 0 : 1))")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.brand.opacity(0.15), in: .capsule)
                    }
                    .contentShape(.rect)
                    .onTapGesture { section = .kids }
                    if kid !== birthdays.last { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macPanel()
    }

    private func birthdayPassed(_ kid: Kid) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.day, from: kid.birthDate) <= calendar.component(.day, from: .now)
    }

    private func empty(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
#endif

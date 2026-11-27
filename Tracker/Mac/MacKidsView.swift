#if targetEnvironment(macCatalyst)
import SwiftUI
import SwiftData

/// The team as a table: sort by any column, search in the toolbar, click a kid to open the profile.
struct MacKidsView: View {
    @Environment(\.modelContext) private var context
    @Query private var kids: [Kid]
    @State private var sortOrder = [KeyPathComparator(\Kid.fullName)]
    @State private var selection = Set<Kid.ID>()
    @State private var search = ""
    @State private var nationality: String?
    @State private var age: Int?
    @Environment(MacModals.self) private var modals

    private let month = Month.key(.now)

    private var rows: [Kid] {
        kids.filter { kid in
            (nationality == nil || kid.countryCode == nationality)
                && (age == nil || (!kid.birthDateUnknown && kid.age == age))
                && (search.isEmpty
                    || kid.fullName.localizedCaseInsensitiveContains(search)
                    || kid.countryName.localizedCaseInsensitiveContains(search)
                    || kid.parents.localizedCaseInsensitiveContains(search))
        }
        .sorted(using: sortOrder)
    }

    private var nationalities: [String] {
        Set(kids.map(\.countryCode)).sorted { Country.name($0) < Country.name($1) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                MacPageHeader(title: "Kids") {
                    MacSearchField(prompt: "Search by name, country or parent", text: $search)
                    MacHeaderButton(title: "Add Kid", symbol: "plus", prominent: true, action: add)
                }
                MacStatRow {
                    MacStat(title: "Kids", symbol: "person.3", value: "\(kids.count)",
                            detail: String(localized: "\(nationalities.count) nationalities"))
                    MacStat(title: "Average Age", symbol: "birthday.cake",
                            value: kids.isEmpty ? "—" : String(format: "%.1f", Double(kids.map(\.age).reduce(0, +)) / Double(kids.count)),
                            detail: kids.isEmpty ? nil : String(localized: "from \(kids.map(\.age).min() ?? 0) to \(kids.map(\.age).max() ?? 0) years"))
                    MacStat(title: "Birthdays", symbol: "gift", value: "\(kids.filter { $0.hasBirthday(inMonth: month) }.count)",
                            detail: Month.title(month))
                }
                filterBar
                table
            }
            .padding(32)
            .macPage()
            .navigationTitle("Kids")
            .macHidesToolbarTitle()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.fullName) { kid in
                MacKidCell(kid: kid, month: month)
            }
            .width(min: 170, ideal: 260)
            TableColumn("Age", value: \.age) { kid in
                Text(kid.birthDateUnknown ? "—" : "\(kid.age)").monospacedDigit()
            }
            .width(min: 36, ideal: 48, max: 64)
            TableColumn("Born", value: \.birthDate) { kid in
                if kid.birthDateUnknown {
                    Label("TBD", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                } else {
                    Text(kid.birthDate, format: .dateTime.day().month(.abbreviated).year())
                }
            }
            .width(min: 80, ideal: 110)
            TableColumn("Nationality", value: \.countryName) { kid in
                Text(kid.countryName)
            }
            .width(min: 76, ideal: 110)
            TableColumn("Parents", value: \.parents) { kid in
                Text(kid.parents.isEmpty ? "—" : kid.parents).foregroundStyle(kid.parents.isEmpty ? .tertiary : .primary)
            }
            .width(min: 90, ideal: 200)
            TableColumn("Documents", value: \.certificationCount) { kid in
                MacDocumentDots(kid: kid)
            }
            .width(min: 70, ideal: 96, max: 120)
            TableColumn("This Month", value: \.monthRank) { kid in
                MacMonthStatus(entry: kid.entry(month: month))
            }
            .width(min: 70, ideal: 100, max: 130)
        }
        .contextMenu(forSelectionType: Kid.ID.self) { ids in
            if let kid = kids.first(where: { ids.contains($0.id) }) {
                Button("Open Profile", systemImage: "person.text.rectangle") { open(kid) }
            }
        } primaryAction: { ids in
            if let kid = kids.first(where: { ids.contains($0.id) }) { open(kid) }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if kids.isEmpty {
                ContentUnavailableView {
                    Label("Your Team Starts Here", systemImage: "figure.run")
                } description: {
                    Text("Add the first kid. Payments, documents and birthdays follow from there.")
                } actions: {
                    Button("Add Kid", systemImage: "plus", action: add).popButton()
                }
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .macPanel(padding: 12)
    }

    private var ages: [Int] { Set(kids.filter { !$0.birthDateUnknown }.map(\.age)).sorted() }

    /// What the table is sorted by, read from the clicked column (or the Sort menu).
    private var sortName: String {
        switch sortOrder.first?.keyPath {
        case \Kid.age: String(localized: "Age")
        case \Kid.birthDate: String(localized: "Born")
        case \Kid.countryName: String(localized: "Nationality")
        case \Kid.createdAt: String(localized: "Newest Added")
        case \Kid.parents: String(localized: "Parents")
        case \Kid.certificationCount: String(localized: "Documents")
        case \Kid.monthRank: String(localized: "This Month")
        default: String(localized: "Name")
        }
    }

    /// Sort and filter in plain sight: what the list is sorted by, and filters by nationality and age.
    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Section("Sort By") {
                    sortButton("Name", \Kid.fullName)
                    sortButton("Age", \Kid.age)
                    sortButton("Nationality", \Kid.countryName)
                    sortButton("This Month", \Kid.monthRank)
                    sortButton("Newest Added", \Kid.createdAt, order: .reverse)
                }
            } label: {
                chip(String(localized: "Sort: \(sortName)"), "arrow.up.arrow.down", active: false)
            }
            .menuIndicator(.hidden)
            Menu {
                Button("All Nationalities") { nationality = nil }
                Divider()
                ForEach(nationalities, id: \.self) { code in
                    Button("\(Country.flag(code)) \(Country.name(code))") { nationality = code }
                }
            } label: {
                chip(nationality.map { "\(Country.flag($0)) \(Country.name($0))" } ?? String(localized: "All Nationalities"), "flag", active: nationality != nil)
            }
            .menuIndicator(.hidden)
            Menu {
                Button("All Ages") { age = nil }
                Divider()
                ForEach(ages, id: \.self) { value in
                    Button(String(localized: "\(value) years")) { age = value }
                }
            } label: {
                chip(age.map { String(localized: "\($0) years") } ?? String(localized: "All Ages"), "birthday.cake", active: age != nil)
            }
            .menuIndicator(.hidden)
            if nationality != nil || age != nil || !search.isEmpty {
                Button("Clear Filters", systemImage: "xmark.circle.fill") {
                    nationality = nil
                    age = nil
                    search = ""
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            Text("\(rows.count) of \(kids.count) kids · click a column title to sort")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(.snappy, value: nationality)
        .animation(.snappy, value: age)
    }

    /// A Sort menu entry, ticked when the table is sorted that way.
    private func sortButton(_ title: String, _ keyPath: KeyPath<Kid, some Comparable>, order: SortOrder = .forward) -> some View {
        let current = sortName == String(localized: String.LocalizationValue(title))
        return Button {
            sortOrder = [KeyPathComparator(keyPath, order: order)]
        } label: {
            if current {
                Label(String(localized: String.LocalizationValue(title)), systemImage: "checkmark")
            } else {
                Text(String(localized: String.LocalizationValue(title)))
            }
        }
    }

    private func chip(_ title: String, _ symbol: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(active ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(active ? Color.brand : .clear, in: .capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(.capsule)
    }

    private func add() {
        let kid = Kid()
        context.insert(kid)
        // A new kid closes only with Cancel or Done, as on iPhone (Cancel removes the empty kid again).
        modals.present(KidProfileSheet(kid: kid, isNew: true), closesOnOutsideClick: false)
    }

    private func open(_ kid: Kid) {
        modals.present(KidProfileSheet(kid: kid, isNew: false))
    }
}

/// The three certification documents as small symbols: blue when in, faint when missing.
struct MacDocumentDots: View {
    let kid: Kid

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FileKind.certifications, id: \.self) { kind in
                Image(systemName: kind.icon)
                    .foregroundStyle(kid.file(kind) == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.brand))
                    .help(kind.title)
            }
            Text("\(kid.certificationCount)/\(FileKind.certifications.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Paid, owing or not on this month's list.
struct MacMonthStatus: View {
    let entry: PaymentEntry?

    var body: some View {
        if let entry {
            Text(entry.paid ? String(localized: "Paid") : String(localized: "Owes \(entry.amount.euros)"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(entry.paid ? Color.brand : .orange)
                .background((entry.paid ? Color.brand : .orange).opacity(0.15), in: .capsule)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}
#endif

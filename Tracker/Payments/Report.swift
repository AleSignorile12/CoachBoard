import SwiftUI
import SwiftData

/// PDF reports for the club: one month (payments + practice log) or a whole season (September to August, a grid
/// of kids by month). Built from SwiftUI views, one A4 page at a time, always in light colors.
enum Report: Hashable {
    case month(Int)
    case season(Int)

    var title: String {
        switch self {
        case .month(let key): tr("Monthly Report · \(monthTitle(key))")
        case .season(let season): tr("Season Report · \(Month.seasonTitle(season))")
        }
    }

    /// File name without characters iOS won't put in one ("/").
    private var fileName: String {
        switch self {
        case .month(let key): "Tracker \(monthTitle(key)).pdf"
        case .season(let season):
            "Tracker \(tr("Season \(Month.seasonTitle(season))").replacingOccurrences(of: "/", with: "-")).pdf"
        }
    }

    /// Writes the PDF to a temporary file and returns its URL (nil if it couldn't be written).
    func makePDF(context: ModelContext, language: ReportLanguage) -> URL? {
        ReportText.language = language
        let data = ReportData(context: context)
        let pages: [[ReportBlock]]
        let size: CGSize
        switch self {
        case .month(let key):
            size = CGSize(width: 595, height: 842)          // A4 portrait
            pages = ReportLayout.paginate(monthBlocks(key, data), usableHeight: size.height - 2 * ReportStyle.margin - 24)
        case .season(let season):
            size = CGSize(width: 842, height: 595)          // A4 landscape: 12 month columns
            pages = ReportLayout.paginate(seasonBlocks(season, data), usableHeight: size.height - 2 * ReportStyle.margin - 24)
        }

        let folder = FileManager.default.temporaryDirectory.appending(path: "Reports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        var box = CGRect(origin: .zero, size: size)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for (index, blocks) in pages.enumerated() {
            let page = ReportPage(blocks: blocks, footer: title, number: index + 1, count: pages.count, size: size)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(size)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }

    // MARK: Monthly

    private func monthBlocks(_ key: Int, _ data: ReportData) -> [ReportSection] {
        let entries = data.entries(month: key)
        let registrations = entries.filter(\.registrationPaid).count
        let total = entries.reduce(0) { $0 + $1.fee.amount } + registrations * Fee.registration
        let collected = entries.filter(\.paid).reduce(0) { $0 + $1.fee.amount } + registrations * Fee.registration
        let days = data.practiceDays(month: key)
        let held = days.filter { $0.logged && $0.held }.count
        let missed = days.filter { $0.logged && !$0.held }.count

        var sections = [ReportSection(rows: [
            ReportHeader(kicker: tr("Monthly Report"), title: monthTitle(key), coach: data.coachName).block,
            ReportTotals(items: [
                (tr("Collected"), "\(collected) €"),
                (tr("Missing"), "\(total - collected) €"),
                (tr("Total"), "\(total) €"),
                (tr("Paid"), "\(entries.filter(\.paid).count)/\(entries.count)"),
                (tr("Practices"), "\(held)"),
            ]).block,
        ])]

        let columns: [ReportColumn] = [
            .init(tr("Kid"), width: nil),
            .init(tr("Fee"), width: 110),
            .init(tr("Amount"), width: 60, alignment: .trailing),
            .init(tr("Monthly Fee"), width: 90),
            .init(tr("Registration"), width: 90),
        ]
        sections.append(ReportSection(
            title: ReportSectionTitle(text: tr("Payments")).block,
            header: ReportRow(columns: columns, cells: columns.map { .text($0.title) }, isHeader: true).block,
            rows: entries.isEmpty
                ? [ReportNote(text: tr("No kids on this month's list.")).block]
                : entries.map { entry in
                    ReportRow(columns: columns, cells: [
                        .text(entry.kid.map { "\($0.flag) \($0.fullName)" } ?? ""),
                        .text(feeTitle(entry.fee)),
                        .text("\(entry.fee.amount) €"),
                        entry.paid ? .good(tr("Paid")) : .bad(tr("Not paid")),
                        entry.registrationPaid ? .good("\(Fee.registration) €") : .text("–"),
                    ]).block
                }
        ))

        let practiceColumns: [ReportColumn] = [
            .init(tr("Day"), width: 120),
            .init(tr("Practice"), width: 100),
            .init(tr("Note"), width: nil),
        ]
        sections.append(ReportSection(
            title: ReportSectionTitle(text: tr("Practice · \(held) held · \(missed) missed")).block,
            header: ReportRow(columns: practiceColumns, cells: practiceColumns.map { .text($0.title) }, isHeader: true).block,
            rows: days.isEmpty
                ? [ReportNote(text: tr("Nothing logged in the practice calendar this month.")).block]
                : days.map { day in
                    ReportRow(columns: practiceColumns, cells: [
                        .text(ReportData.date(day.day).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(ReportText.locale))),
                        !day.logged ? .text("–") : day.held ? .good(tr("Held")) : .bad(tr("No Practice")),
                        .text(day.note),
                    ], allowsTwoLines: !day.note.isEmpty).block
                }
        ))
        return sections
    }

    // MARK: Season

    private func seasonBlocks(_ season: Int, _ data: ReportData) -> [ReportSection] {
        let months = (0..<12).map { Month.add($0, to: season * 100 + 9) }
        let entries = data.entries(season: season)
        let byKid = Dictionary(grouping: entries.filter { $0.kid != nil }, by: { $0.kid!.persistentModelID })
        let kids = byKid.values.compactMap(\.first?.kid)
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        let registrations = entries.filter(\.registrationPaid).count
        let total = entries.reduce(0) { $0 + $1.fee.amount } + registrations * Fee.registration
        let collected = entries.filter(\.paid).reduce(0) { $0 + $1.fee.amount } + registrations * Fee.registration
        let practice = months.map { key in
            let days = data.practiceDays(month: key)
            return (held: days.filter { $0.logged && $0.held }.count, missed: days.filter { $0.logged && !$0.held }.count)
        }

        var sections = [ReportSection(rows: [
            ReportHeader(kicker: tr("Season Report"), title: Month.seasonTitle(season), coach: data.coachName).block,
            ReportTotals(items: [
                (tr("Collected"), "\(collected) €"),
                (tr("Missing"), "\(total - collected) €"),
                (tr("Total"), "\(total) €"),
                (tr("Registrations"), "\(registrations)"),
                (tr("Practices"), "\(practice.reduce(0) { $0 + $1.held })"),
            ]).block,
        ])]

        let monthWidth: CGFloat = 40
        let columns: [ReportColumn] = [.init(tr("Kid"), width: nil)]
            + months.map { .init(monthShort($0), width: monthWidth, alignment: .center) }
            + [.init(tr("Reg."), width: 48, alignment: .center),
               .init(tr("Paid"), width: 56, alignment: .trailing)]
        var rows: [ReportBlock] = kids.map { kid in
            let mine = byKid[kid.persistentModelID] ?? []
            let paid = mine.filter(\.paid).reduce(0) { $0 + $1.fee.amount } + (mine.contains(where: \.registrationPaid) ? Fee.registration : 0)
            let registration = mine.first(where: \.registrationPaid).map { monthShort($0.month) }
            return ReportRow(columns: columns, cells: [.text("\(kid.flag) \(kid.fullName)")]
                + months.map { key in
                    guard let entry = mine.first(where: { $0.month == key }) else { return .text("") }
                    return entry.paid ? .good("✓") : .bad("✗")
                }
                + [registration.map { .good($0) } ?? .text("–"), .text("\(paid) €")]).block
        }
        if kids.isEmpty { rows = [ReportNote(text: tr("No payments recorded this season.")).block] }
        sections.append(ReportSection(
            title: ReportSectionTitle(text: tr("Payments · ✓ paid · ✗ not paid")).block,
            header: ReportRow(columns: columns, cells: columns.map { .text($0.title) }, isHeader: true).block,
            rows: rows
        ))

        let perMonth: [ReportColumn] = [.init("", width: nil)] + months.map { .init(monthShort($0), width: monthWidth, alignment: .center) } + [.init("", width: 110, alignment: .trailing)]
        // Months that haven't started yet stay blank instead of showing zeros.
        let current = Month.key(.now)
        func cell(_ key: Int, _ value: Int, good: Bool = false, bad: Bool = false) -> ReportCell {
            if key > current { return .text("") }
            if good { return .good("\(value)") }
            if bad && value > 0 { return .bad("\(value)") }
            return .text("\(value)")
        }
        func monthTotal(_ key: Int, paidOnly: Bool) -> Int {
            entries.filter { $0.month == key && (!paidOnly || $0.paid) }.reduce(0) { $0 + $1.fee.amount }
                + entries.filter { $0.month == key && $0.registrationPaid }.count * Fee.registration
        }
        sections.append(ReportSection(
            title: ReportSectionTitle(text: tr("Month by Month")).block,
            header: ReportRow(columns: perMonth, cells: perMonth.map { .text($0.title) }, isHeader: true).block,
            rows: [
                ReportRow(columns: perMonth, cells: [.text(tr("Collected (€)"))] + months.map { cell($0, monthTotal($0, paidOnly: true)) } + [.text("\(collected) €")]).block,
                ReportRow(columns: perMonth, cells: [.text(tr("Total (€)"))] + months.map { cell($0, monthTotal($0, paidOnly: false)) } + [.text("\(total) €")]).block,
                ReportRow(columns: perMonth, cells: [.text(tr("Practices held"))] + zip(months, practice).map { cell($0, $1.held, good: true) } + [.text("\(practice.reduce(0) { $0 + $1.held })")]).block,
                ReportRow(columns: perMonth, cells: [.text(tr("Practices missed"))] + zip(months, practice).map { cell($0, $1.missed, bad: true) } + [.text("\(practice.reduce(0) { $0 + $1.missed })")]).block,
            ]
        ))
        return sections
    }
}

// MARK: - Language

/// The language a report is written in, picked in the Report menu: the club may want it in Italian while the app
/// is in English, or the other way round.
enum ReportLanguage: String, CaseIterable, Identifiable {
    case english = "en", italian = "it"

    static let storageKey = "reportLanguage"
    /// Italian when the app is in Italian, English otherwise.
    static var automatic: ReportLanguage { Bundle.main.preferredLocalizations.first == "it" ? .italian : .english }

    var id: String { rawValue }
    /// Each name in its own language, like the system's language lists.
    var name: String { self == .english ? "English" : "Italiano" }
    /// The report's language with the phone's region (so dates keep the local order).
    var locale: Locale { Locale(languageCode: .init(rawValue), languageRegion: Locale.current.region) }
}

/// The language of the report being written (reports are built one at a time, on the main thread).
@MainActor
enum ReportText {
    static var language = ReportLanguage.automatic
    static var locale: Locale { language.locale }
}

/// A report string in the report's language instead of the app's.
@MainActor
private func tr(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = ReportText.locale
    return String(localized: resource)
}

/// "November 2026" / "Novembre 2026": capitalized even in languages that write month names in lowercase, since it's a heading.
@MainActor private func monthTitle(_ key: Int) -> String {
    let title = Month.date(key).formatted(.dateTime.month(.wide).year().locale(ReportText.locale))
    return title.prefix(1).uppercased(with: ReportText.locale) + title.dropFirst()
}

@MainActor private func monthShort(_ key: Int) -> String {
    Month.date(key).formatted(.dateTime.month(.abbreviated).locale(ReportText.locale))
}

@MainActor private func feeTitle(_ fee: Fee) -> String {
    switch fee {
    case .standard: tr("Standard")
    case .sibling: tr("With sibling")
    case .friend: tr("With friend")
    }
}

// MARK: - Data

/// Everything a report reads, fetched once.
@MainActor
private struct ReportData {
    let payments: [PaymentEntry]
    let practice: [PracticeDay]
    let coachName: String

    init(context: ModelContext) {
        payments = ((try? context.fetch(FetchDescriptor<PaymentEntry>())) ?? []).filter { $0.kid != nil }
        practice = (try? context.fetch(FetchDescriptor<PracticeDay>(sortBy: [SortDescriptor(\.day)]))) ?? []
        let coach = (try? context.fetch(FetchDescriptor<Coach>()))?.first
        let name = "\(coach?.firstName ?? "") \(coach?.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        coachName = name.isEmpty ? tr("Coach") : name
    }

    /// Same order as the Payments tab: unpaid first, then A–Z.
    func entries(month: Int) -> [PaymentEntry] {
        payments.filter { $0.month == month }.sorted { a, b in
            if a.paid != b.paid { return !a.paid }
            return (a.kid?.fullName ?? "").localizedStandardCompare(b.kid?.fullName ?? "") == .orderedAscending
        }
    }

    func entries(season: Int) -> [PaymentEntry] {
        payments.filter { Month.season($0.month) == season }
    }

    func practiceDays(month: Int) -> [PracticeDay] {
        practice.filter { $0.day / 100 == month && ($0.logged || !$0.note.isEmpty) }
    }

    static func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: day / 10000, month: day / 100 % 100, day: day % 100)) ?? .now
    }
}

// MARK: - Layout

enum ReportStyle {
    static let margin: CGFloat = 36
    static let good = Color(red: 0.102, green: 0.435, blue: 0.769)   // the app's blue (light mode)
    static let bad = Color(red: 0.85, green: 0.42, blue: 0.0)
}

/// A piece of a page with a known height, so pages can be filled without measuring.
struct ReportBlock {
    let height: CGFloat
    let view: AnyView
}

/// A run of blocks; when a table continues on the next page its header row is repeated there.
struct ReportSection {
    var title: ReportBlock?
    var header: ReportBlock?
    var rows: [ReportBlock]

    init(title: ReportBlock? = nil, header: ReportBlock? = nil, rows: [ReportBlock]) {
        self.title = title
        self.header = header
        self.rows = rows
    }
}

enum ReportLayout {
    static func paginate(_ sections: [ReportSection], usableHeight: CGFloat) -> [[ReportBlock]] {
        var pages: [[ReportBlock]] = [[]]
        var used: CGFloat = 0
        func newPage() { pages.append([]); used = 0 }
        func place(_ block: ReportBlock) { pages[pages.count - 1].append(block); used += block.height }

        for section in sections {
            let lead = [section.title, section.header].compactMap { $0 }
            let leadHeight = lead.reduce(0) { $0 + $1.height }
            // Keep a title and header together with at least one row.
            if used > 0 && used + leadHeight + (section.rows.first?.height ?? 0) > usableHeight { newPage() }
            lead.forEach(place)
            for row in section.rows {
                if used + row.height > usableHeight {
                    newPage()
                    if let header = section.header { place(header) }
                }
                place(row)
            }
        }
        return pages
    }
}

private struct ReportPage: View {
    let blocks: [ReportBlock]
    let footer: String
    let number: Int
    let count: Int
    let size: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { blocks[$0].view.frame(height: blocks[$0].height, alignment: .top) }
            Spacer(minLength: 0)
            HStack {
                Text(verbatim: "Tracker · \(footer)")
                Spacer()
                Text(verbatim: tr("Page \(number) of \(count)"))
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
            .frame(height: 24, alignment: .bottom)
        }
        .padding(ReportStyle.margin)
        .frame(width: size.width, height: size.height)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

private struct ReportHeader: View {
    let kicker: String
    let title: String
    let coach: String

    var block: ReportBlock { ReportBlock(height: 74, view: AnyView(self)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ReportStyle.good)
            Text(title)
                .font(.system(size: 24, weight: .bold))
            Text(verbatim: "\(coach) · \(Date.now.formatted(.dateTime.day().month(.wide).year().locale(ReportText.locale)))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReportTotals: View {
    let items: [(String, String)]

    var block: ReportBlock { ReportBlock(height: 62, view: AnyView(self)) }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 2) {
                    Text(items[index].0).font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(items[index].1).font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(Color(white: 0.95), in: .rect(cornerRadius: 8))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ReportSectionTitle: View {
    let text: String

    var block: ReportBlock { ReportBlock(height: 30, view: AnyView(self)) }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 6)
    }
}

private struct ReportNote: View {
    let text: String

    var block: ReportBlock { ReportBlock(height: 22, view: AnyView(self)) }

    var body: some View {
        Text(text).font(.system(size: 9)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ReportColumn {
    let title: String
    let width: CGFloat?
    let alignment: Alignment

    init(_ title: String, width: CGFloat?, alignment: Alignment = .leading) {
        self.title = title
        self.width = width
        self.alignment = alignment
    }
}

enum ReportCell {
    case text(String), good(String), bad(String)
}

private struct ReportRow: View {
    let columns: [ReportColumn]
    let cells: [ReportCell]
    var isHeader = false
    var allowsTwoLines = false

    var block: ReportBlock { ReportBlock(height: allowsTwoLines ? 30 : 19, view: AnyView(self)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(columns.indices, id: \.self) { index in
                    cell(cells.indices.contains(index) ? cells[index] : .text(""))
                        .lineLimit(allowsTwoLines ? 2 : 1)
                        .frame(maxWidth: columns[index].width ?? .infinity, alignment: columns[index].alignment)
                        .frame(width: columns[index].width)
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(Color(white: isHeader ? 0.75 : 0.9)).frame(height: 0.5)
        }
    }

    @ViewBuilder private func cell(_ cell: ReportCell) -> some View {
        switch cell {
        case .text(let text):
            Text(text)
                .font(.system(size: isHeader ? 8 : 9, weight: isHeader ? .semibold : .regular))
                .foregroundStyle(isHeader ? .secondary : .primary)
        case .good(let text):
            Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(ReportStyle.good)
        case .bad(let text):
            Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(ReportStyle.bad)
        }
    }
}

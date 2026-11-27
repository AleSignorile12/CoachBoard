#if targetEnvironment(macCatalyst)
import SwiftUI
import SwiftData
import QuickLook

/// A month's fees as a ledger: totals at the top, one row per kid with fee, registration and total, the month
/// switcher and the PDF reports in the toolbar.
struct MacPaymentsView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [PaymentEntry]
    @State private var month = Month.key(.now)
    @State private var sortOrder = [KeyPathComparator(\PaymentEntry.paidRank), KeyPathComparator(\PaymentEntry.kidName)]
    @State private var selection = Set<PaymentEntry.ID>()
    @Environment(MacModals.self) private var modals
    @State private var showMonthPicker = false
    @State private var reportURL: URL?
    @AppStorage(ReportLanguage.storageKey) private var reportLanguage = ReportLanguage.automatic
    private var settings = MoneySettings()

    private var monthEntries: [PaymentEntry] { entries.filter { $0.month == month && $0.kid != nil } }
    private var rows: [PaymentEntry] { monthEntries.sorted(using: sortOrder) }
    private var total: Int { monthEntries.reduce(0) { $0 + $1.lineTotal } }
    private var collected: Int { monthEntries.reduce(0) { $0 + $1.collected } }
    private var settledCount: Int { monthEntries.filter(\.settled).count }
    private var registrations: [PaymentEntry] { monthEntries.filter(\.registrationPaid) }
    private var templateMonth: Int? { entries.filter { $0.month < month }.map(\.month).max() }
    private var fullyPaidMonths: Set<Int> {
        let byMonth = Dictionary(grouping: entries.filter { $0.kid != nil }, by: \.month)
        return Set(byMonth.filter { $0.value.allSatisfy(\.settled) }.keys)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                MacPageHeader(title: "Payments") {
                    reportMenu
                    MacHeaderButton(title: "Add a one-off charge, like a kit or a tournament", symbol: "tag") { addCharge() }
                        .disabled(monthEntries.isEmpty)
                    MacHeaderButton(title: "Add Kids", symbol: "person.badge.plus", prominent: true) { addKids() }
                }
                monthSwitcher
                MacStatRow {
                    MacStat(title: "Collected", symbol: Money.icon, value: collected.euros,
                            detail: String(localized: "\(settledCount) of \(monthEntries.count) paid"),
                            color: .brand, progress: total == 0 ? 0 : Double(collected) / Double(total))
                    MacStat(title: "Missing", symbol: "hourglass", value: (total - collected).euros,
                            detail: String(localized: "\(monthEntries.count - settledCount) kids still to pay"),
                            color: total == collected ? .secondary : .orange)
                    MacStat(title: "Total", symbol: "sum", value: total.euros, detail: Month.title(month))
                    if settings.registrationOn {
                        MacStat(title: "Registrations", symbol: "signature",
                                value: registrations.reduce(0) { $0 + $1.registrationTotal }.euros,
                                detail: String(localized: "Season \(Month.seasonTitle(Month.season(month)))"))
                    }
                }
                table
                Text("Click the circle to mark a fee as paid, and a charge to tick it. Right-click rows for more, like a new plan or a charge for several kids at once. Set the plans and amounts in My Profile › Fees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .macPage()
            .navigationTitle("Payments")
            .macHidesToolbarTitle()
            .navigationBarTitleDisplayMode(.inline)
            .quickLookPreview($reportURL)
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Paid", value: \.paidRank) { entry in
                Button {
                    withAnimation(.snappy) { entry.paid.toggle() }
                } label: {
                    Image(systemName: entry.paid ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(entry.paid ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.paid ? "Paid" : "Not paid")
            }
            .width(52)
            TableColumn("Kid", value: \.kidName) { entry in
                if let kid = entry.kid { MacKidCell(kid: kid, month: entry.month) }
            }
            .width(min: 130, ideal: 220)
            TableColumn("Fee", value: \.feeTitle) { entry in
                MacFeePicker(entry: entry)
            }
            .width(min: 190, ideal: 220)
            if settings.registrationOn {
                TableColumn("Registration") { entry in
                    MacRegistrationCell(entry: entry)
                }
                .width(min: 110, ideal: 150, max: 170)
            }
            TableColumn("Extras", value: \.chargesTotal) { entry in
                MacChargesCell(entry: entry)
            }
            .width(min: 64, ideal: 140)
            TableColumn("Total", value: \.lineTotal) { entry in
                Text(entry.lineTotal.euros)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(entry.settled ? Color.brand : .primary)
            }
            .width(66)
        }
        .contextMenu(forSelectionType: PaymentEntry.ID.self) { ids in
            let chosen = monthEntries.filter { ids.contains($0.id) }
            if !chosen.isEmpty {
                Button("Mark as Paid", systemImage: "checkmark.circle") {
                    chosen.forEach { entry in
                        entry.paid = true
                        entry.charges?.forEach { $0.paid = true }
                    }
                }
                Button("Mark as Not Paid", systemImage: "circle") { chosen.forEach { $0.paid = false } }
                Menu("Fee", systemImage: "person.2") {
                    ForEach(Fee.allCases) { fee in
                        Button("\(fee.title) · \(fee.amount.euros)") { chosen.forEach { $0.fee = fee } }
                    }
                }
                Button(chosen.count > 1 ? "Add Charge to Selected Kids" : "Add Charge", systemImage: "tag") {
                    addCharge(Set(chosen.map(\.persistentModelID)))
                }
                Divider()
                Button("Remove from \(Month.title(month))", systemImage: "person.badge.minus", role: .destructive) {
                    chosen.forEach { context.delete($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if monthEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Kids This Month", systemImage: Money.icon)
                } description: {
                    Text("Add the kids who train in \(Month.title(month)).")
                } actions: {
                    if let templateMonth {
                        Button("Copy \(Month.title(templateMonth))", systemImage: "doc.on.doc") { copy(from: templateMonth) }
                            .buttonStyle(.glassProminent)
                    }
                    Button("Add Kids", systemImage: "person.badge.plus") { addKids() }
                        .buttonStyle(.glass)
                }
            }
        }
        .macPanel(padding: 12)
    }

    /// The month switcher: big arrows either side of the month (click it for the year's months), plus a way
    /// back to this month and how many have paid.
    private var monthSwitcher: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                monthArrow("Previous Month", "chevron.left", -1)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button { showMonthPicker = true } label: {
                    HStack(spacing: 8) {
                        Text(Month.title(month))
                            .font(.title2.bold())
                            .foregroundStyle(fullyPaidMonths.contains(month) ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.primary))
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Choose Month")
                .popover(isPresented: $showMonthPicker) {
                    MonthPickerSheet(month: $month, monthsWithKids: Set(entries.map(\.month)), fullyPaid: fullyPaidMonths)
                        .frame(width: 380, height: 440)
                }
                monthArrow("Next Month", "chevron.right", 1)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .padding(5)
            .glassEffect(.regular, in: .capsule)
            if month != Month.key(.now) {
                Button("This Month", systemImage: "arrow.uturn.backward") { month = Month.key(.now) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if !monthEntries.isEmpty {
                let paid = settledCount
                Label(paid == monthEntries.count ? String(localized: "Everyone has paid. 🎉") : String(localized: "\(paid) of \(monthEntries.count) paid"),
                      systemImage: paid == monthEntries.count ? "checkmark.seal.fill" : "person.2")
                    .font(.headline)
                    .foregroundStyle(paid == monthEntries.count ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .animation(.snappy, value: month)
    }

    private func monthArrow(_ title: LocalizedStringKey, _ symbol: String, _ step: Int) -> some View {
        Button { month = Month.add(step, to: month) } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(MacCardButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    private var reportMenu: some View {
        Menu {
            Section("Report as PDF") {
                Button(Month.title(month), systemImage: "calendar") {
                    reportURL = Report.month(month).makePDF(context: context, language: reportLanguage)
                }
                Button("Season \(Month.seasonTitle(Month.season(month)))", systemImage: "calendar.badge.clock") {
                    reportURL = Report.season(Month.season(month)).makePDF(context: context, language: reportLanguage)
                }
            }
            Picker(selection: $reportLanguage) {
                ForEach(ReportLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
            } label: {
                Label("Report Language", systemImage: "globe")
            }
            .pickerStyle(.menu)
        } label: {
            MacHeaderIcon(symbol: "doc.text")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Report")
        .accessibilityLabel("Report")
    }

    private func addCharge(_ preselected: Set<PersistentIdentifier> = []) {
        modals.present(AddChargeSheet(month: month, preselected: preselected), closesOnOutsideClick: false)
    }

    private func addKids() {
        modals.present(AddToMonthSheet(month: month, existing: Set(monthEntries.compactMap { $0.kid?.persistentModelID })))
    }

    private func copy(from template: Int) {
        for old in entries where old.month == template {
            guard let kid = old.kid else { continue }
            let entry = PaymentEntry(month: month, fee: old.fee.orFirst)
            context.insert(entry)
            entry.kid = kid
        }
    }
}

private struct MacFeePicker: View {
    @Bindable var entry: PaymentEntry
    private var settings = MoneySettings()

    init(entry: PaymentEntry) { self.entry = entry }

    var body: some View {
        Picker("Fee", selection: $entry.fee) {
            // "With sibling · 25 €": the plan and what it costs this month, also in the closed picker.
            ForEach(Fee.choices(including: entry.fee)) { fee in
                let title = fee == entry.fee ? entry.feeName : fee.title
                let amount = fee == entry.fee ? entry.amount : fee.amount(inMonth: entry.month)
                Label("\(title) · \(amount.euros)", systemImage: fee.icon).tag(fee)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        // Shrinks with its column (the name shortens) instead of running into the next one.
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(entry.fee == Fee.first ? .primary : .purple)
    }
}

/// The one-off charges of a row, each ticked on its own; a dash when there are none.
private struct MacChargesCell: View {
    let entry: PaymentEntry

    var body: some View {
        if entry.sortedCharges.isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 10) {
                ForEach(entry.sortedCharges) { ChargeChip(charge: $0) }
            }
        }
    }
}

/// Registration, once per season: a button while unpaid, then the seal with the month it was paid in
/// (in that month it can be undone).
private struct MacRegistrationCell: View {
    @Bindable var entry: PaymentEntry

    var body: some View {
        let season = Month.season(entry.month)
        if let kid = entry.kid {
            if let paid = kid.registrationEntry(season: season) {
                let badge = Label("\(Month.shortTitle(paid.month)) · \(paid.registrationAmount.euros)", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.brand)
                if paid === entry {
                    // Paid in this month: the same badge, and clicking it offers Undo.
                    Menu {
                        Button("Undo Registration \(Month.seasonTitle(season))", systemImage: "arrow.uturn.backward", role: .destructive) {
                            entry.registrationPaid = false
                        }
                    } label: { badge }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                } else {
                    badge
                }
            } else {
                Button {
                    entry.registrationPaid = true
                } label: {
                    Label("Add \(entry.registrationAmount.euros)", systemImage: "plus.circle")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
#endif

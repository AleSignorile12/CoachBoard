import SwiftUI
import SwiftData
import QuickLook

struct PaymentsView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [PaymentEntry]
    @State private var month = Month.key(.now)
    @State private var showAdd = false
    @State private var showMonthPicker = false
    @State private var reportURL: URL?
    @AppStorage(ReportLanguage.storageKey) private var reportLanguage = ReportLanguage.automatic

    /// Like checked items in Notes: still to pay on top, paid at the bottom, each group A–Z.
    private var monthEntries: [PaymentEntry] {
        entries
            .filter { $0.month == month && $0.kid != nil }
            .sorted { a, b in
                if a.paid != b.paid { return !a.paid }
                return (a.kid?.fullName ?? "").localizedStandardCompare(b.kid?.fullName ?? "") == .orderedAscending
            }
    }

    /// Latest earlier month that has a list, offered as a template for an empty month.
    private var templateMonth: Int? {
        entries.filter { $0.month < month }.map(\.month).max()
    }

    /// Registrations paid this month (already-received money, so it counts in both collected and total).
    private var registrations: Int { monthEntries.filter(\.registrationPaid).count }
    private var total: Int { monthEntries.reduce(0) { $0 + $1.fee.amount } + registrations * Fee.registration }
    private var collected: Int {
        monthEntries.filter(\.paid).reduce(0) { $0 + $1.fee.amount } + registrations * Fee.registration
    }

    var body: some View {
        NavigationStack {
            List {
                if !monthEntries.isEmpty {
                    Section { summary }
                    Section {
                        ForEach(monthEntries) { PaymentRow(entry: $0) }
                    } header: {
                        Text("\(monthEntries.filter(\.paid).count) of \(monthEntries.count) paid")
                    } footer: {
                        Text("Tap the circle to mark as paid. Tap the fee to switch between standard (30 €) and reduced (25 €) for siblings or friends. Tap Registration when a kid pays the 30 € registration, once per season (\(Month.seasonTitle(Month.season(month))), September to August): a seal with the paid month then appears under the fee. Tap it in the month it was paid to undo it. Swipe to remove a kid from this month.")
                    }
                }
            }
            .overlay {
                if monthEntries.isEmpty { emptyState }
            }
            .safeAreaInset(edge: .bottom) { monthSwitcher }
            .ambientBackground()
            .navigationTitle("Payments")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                        Label("Report", systemImage: "doc.text")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Kids", systemImage: "person.badge.plus") { showAdd = true }
                        .popButton()
                }
            }
            // Quick Look shows the PDF with the system share button (Mail, WhatsApp, Files, print…).
            .quickLookPreview($reportURL)
            .sheet(isPresented: $showAdd) {
                AddToMonthSheet(month: month, existing: Set(monthEntries.compactMap { $0.kid?.persistentModelID }))
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthPickerSheet(month: $month, monthsWithKids: Set(entries.map(\.month)), fullyPaid: fullyPaidMonths)
            }
            .onAppear(perform: moveOldRegistrations)
        }
    }

    /// Months where every kid on the list paid the monthly fee (registration not counted).
    private var fullyPaidMonths: Set<Int> {
        let byMonth = Dictionary(grouping: entries.filter { $0.kid != nil }, by: \.month)
        return Set(byMonth.filter { $0.value.allSatisfy(\.paid) }.keys)
    }

    /// The previous version stored one registration per kid (`Kid.registrationMonth`). Move it onto
    /// that month's entry so it counts for that season, then clear the old field.
    private func moveOldRegistrations() {
        for entry in entries where entry.kid?.registrationMonth == entry.month {
            entry.registrationPaid = true
        }
        for kid in entries.compactMap(\.kid) where kid.registrationMonth != nil {
            kid.registrationMonth = nil
        }
    }

    // MARK: Pieces

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                stat("Collected", collected, .accentColor)
                Spacer()
                stat("Missing", total - collected, total == collected ? .secondary : .orange)
                Spacer()
                stat("Total", total, .primary)
            }
            ProgressView(value: Double(collected), total: Double(max(total, 1)))
                .tint(Color.accentColor)
            if registrations > 0 {
                Label("Registrations included: \(registrations) (\(registrations * Fee.registration) €)",
                      systemImage: "signature")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: LocalizedStringKey, _ euros: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(euros, format: .currency(code: "EUR").precision(.fractionLength(0)))
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Kids This Month", systemImage: "eurosign.circle")
        } description: {
            Text("Add the kids who train in \(Month.title(month)).")
        } actions: {
            if let templateMonth {
                Button("Copy \(Month.title(templateMonth))", systemImage: "doc.on.doc") { copy(from: templateMonth) }
                    .buttonStyle(.glassProminent)
            }
            Button("Add Kids", systemImage: "person.badge.plus") { showAdd = true }
                .buttonStyle(.glass)
        }
    }

    // Separate glass buttons: one interactive glass shape around several buttons swallowed their taps.
    private var monthSwitcher: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button("Previous Month", systemImage: "chevron.left") { month = Month.add(-1, to: month) }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(Month.title(month)).contentTransition(.numericText())
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    }
                    .font(.headline)
                    .foregroundStyle(fullyPaidMonths.contains(month) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    .frame(minWidth: 160)
                }
                .accessibilityHint("Choose a month")
                Button("Next Month", systemImage: "chevron.right") { month = Month.add(1, to: month) }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(.primary)
        }
        .padding(.bottom, 8)
        .animation(.snappy, value: month)
        .sensoryFeedback(.selection, trigger: month)
    }

    private func copy(from template: Int) {
        for old in entries where old.month == template {
            guard let kid = old.kid else { continue }
            let entry = PaymentEntry(month: month, fee: old.fee)
            context.insert(entry)
            entry.kid = kid
        }
    }
}

private struct PaymentRow: View {
    @Bindable var entry: PaymentEntry
    @Environment(\.modelContext) private var context

    var body: some View {
        if let kid = entry.kid {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { entry.paid.toggle() }
                } label: {
                    Image(systemName: entry.paid ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(entry.paid ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.paid ? "Paid" : "Not paid")
                .sensoryFeedback(.success, trigger: entry.paid) { _, new in new }
                .sensoryFeedback(.selection, trigger: entry.fee)

                Text(kid.flag).font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kid.hasBirthday(inMonth: entry.month) ? "\(kid.fullName) 🎂" : kid.fullName)
                        .font(.headline)
                    Menu {
                        Picker("Fee", selection: $entry.fee) {
                            ForEach(Fee.allCases) { fee in
                                Label("\(fee.title) · \(fee.amount) €", systemImage: fee.icon).tag(fee)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Label(entry.fee.title, systemImage: entry.fee.icon)
                            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(entry.fee == .standard ? AnyShapeStyle(.secondary) : AnyShapeStyle(.purple))
                    }
                    // Only one of these shows: the badge once paid this season, otherwise the button.
                    registrationBadge(kid)
                    registration(kid)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.fee.amount, format: .currency(code: "EUR").precision(.fractionLength(0)))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(entry.paid ? .accentColor : .primary)
                    if entry.registrationPaid {
                        Text("+\(Fee.registration) €")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .swipeActions(edge: .leading) {
                Button(entry.paid ? "Not Paid" : "Paid", systemImage: entry.paid ? "xmark" : "checkmark") {
                    withAnimation(.snappy) { entry.paid.toggle() }
                }
                .tint(entry.paid ? .gray : .accentColor)
            }
            .swipeActions(edge: .trailing) {
                Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                    context.delete(entry)
                }
            }
        }
    }

    /// Green seal + paid month ("✓ Sep 2026") under the fee for the whole season once registration is paid.
    /// In the month it was paid, tapping it offers Undo.
    @ViewBuilder
    private func registrationBadge(_ kid: Kid) -> some View {
        let season = Month.season(entry.month)
        if let paid = kid.registrationEntry(season: season) {
            let badge = HStack(spacing: 3) {
                Image(systemName: "checkmark.seal")
                Text(Month.shortTitle(paid.month))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Registration \(Month.seasonTitle(season)) paid in \(Month.title(paid.month))")

            if paid === entry {
                Menu {
                    Button("Undo Registration \(Month.seasonTitle(season))", systemImage: "arrow.uturn.backward", role: .destructive) {
                        entry.registrationPaid = false
                    }
                } label: {
                    badge
                }
            } else {
                badge
            }
        }
    }

    /// Registration, once per season: the button shows only while unpaid this season.
    /// "30 €" uses a no-break space so the € never wraps alone.
    @ViewBuilder
    private func registration(_ kid: Kid) -> some View {
        if kid.registrationEntry(season: Month.season(entry.month)) == nil {
            Button {
                entry.registrationPaid = true
            } label: {
                Label("Registration \(Fee.registration)\u{00A0}€", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: entry.registrationPaid)
        }
    }
}

// MARK: - Month picker

private struct MonthPickerSheet: View {
    @Binding var month: Int
    let monthsWithKids: Set<Int>
    let fullyPaid: Set<Int>
    @State private var year: Int
    @Environment(\.dismiss) private var dismiss

    init(month: Binding<Int>, monthsWithKids: Set<Int>, fullyPaid: Set<Int>) {
        _month = month
        self.monthsWithKids = monthsWithKids
        self.fullyPaid = fullyPaid
        _year = State(initialValue: month.wrappedValue / 100)
    }

    private func foreground(_ key: Int) -> AnyShapeStyle {
        if key == month { return AnyShapeStyle(.white) }
        return fullyPaid.contains(key) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)
    }

    private func background(_ key: Int) -> AnyShapeStyle {
        if key == month { return fullyPaid.contains(key) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tint) }
        return fullyPaid.contains(key) ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.fill.tertiary)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Button("Previous Year", systemImage: "chevron.left") { year -= 1 }
                    Text(String(year))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                    Button("Next Year", systemImage: "chevron.right") { year += 1 }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .animation(.snappy, value: year)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(1...12, id: \.self) { number in
                        let key = year * 100 + number
                        Button {
                            month = key
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Text(Calendar.current.shortStandaloneMonthSymbols[number - 1])
                                    .font(.body.weight(.semibold))
                                // Dot = this month already has a list.
                                Circle()
                                    .frame(width: 5, height: 5)
                                    .opacity(monthsWithKids.contains(key) ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(foreground(key))
                            .background(background(key), in: .rect(cornerRadius: 14))
                            .accessibilityValue(fullyPaid.contains(key) ? "Everyone paid" : "")
                            .overlay {
                                if key == Month.key(.now) && key != month {
                                    RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Label {
                    Text("Blue = everyone paid the monthly fee").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                }
                .font(.footnote)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Choose Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        month = Month.key(.now)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add kids to a month

private struct AddToMonthSheet: View {
    let month: Int
    let existing: Set<PersistentIdentifier>
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Kid.firstName), SortDescriptor(\Kid.lastName)]) private var kids: [Kid]
    @State private var selection: Set<PersistentIdentifier> = []

    private var available: [Kid] { kids.filter { !existing.contains($0.persistentModelID) } }

    var body: some View {
        NavigationStack {
            List(available, selection: $selection) { kid in
                HStack(spacing: 12) {
                    Text(kid.flag).font(.title2)
                    Text(kid.fullName)
                    Spacer()
                    Text("\(kid.lastFee.amount) €").foregroundStyle(.secondary)
                }
            }
            .environment(\.editMode, .constant(.active))
            .overlay {
                if available.isEmpty {
                    ContentUnavailableView(
                        kids.isEmpty ? "No Kids Yet" : "Everyone's In",
                        systemImage: "person.3",
                        description: Text(kids.isEmpty ? "Add kids in the Kids tab first." : "All your kids are already on \(Month.title(month)).")
                    )
                }
            }
            .navigationTitle(Month.title(month))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        for kid in available where selection.contains(kid.persistentModelID) {
                            let entry = PaymentEntry(month: month, fee: kid.lastFee)
                            context.insert(entry)
                            entry.kid = kid
                        }
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}

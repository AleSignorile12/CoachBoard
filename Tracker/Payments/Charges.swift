import SwiftUI
import SwiftData

/// Redraws a view when the fee plans, the registration, the season or the currency change (here or on the
/// coach's other device, see SettingsSync).
struct MoneySettings: DynamicProperty {
    @AppStorage(Money.storageKey) private var currency = "EUR"
    @AppStorage(FeePlans.storageKey) private var plans = ""
    @AppStorage(FeeAmounts.registrationKey) private var registration = FeeAmounts.original.registration
    @AppStorage(SeasonSettings.registrationOnKey) var registrationOn = true
    @AppStorage(SeasonSettings.startKey) private var seasonStart = 9
}

/// A one-off charge under a kid's fee: its name and amount, tapped when it's paid. Long-press or right-click removes it.
struct ChargeChip: View {
    @Bindable var charge: ExtraCharge
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            withAnimation(.snappy) { charge.paid.toggle() }
        } label: {
            Label {
                Text("\(charge.title) · \(Money.format(charge.amount))")
                    .lineLimit(1)
            } icon: {
                Image(systemName: charge.paid ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(charge.paid ? Color.brand : Color.orange)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: charge.paid) { _, new in new }
        .accessibilityLabel(charge.paid ? "\(charge.title), paid" : "\(charge.title), not paid")
        .contextMenu {
            Button(charge.paid ? "Mark as Not Paid" : "Mark as Paid", systemImage: charge.paid ? "circle" : "checkmark.circle") {
                charge.paid.toggle()
            }
            Button("Remove Charge", systemImage: "trash", role: .destructive) {
                context.delete(charge)
            }
        }
    }
}

/// Adds a one-off charge (kit, tournament, insurance, camp…) to some of the kids on a month's list. Each kid gets
/// it as a separate line in that month, ticked on its own when paid.
struct AddChargeSheet: View {
    let month: Int
    @Query private var entries: [PaymentEntry]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// On the Mac these open as a panel over the window (Mac/MacShell.swift), which closes differently.
    @Environment(\.macClose) private var macClose
    private func close() { if let macClose { macClose() } else { dismiss() } }
    @State private var title = ""
    @State private var amount: Int?
    @State private var selection: Set<PersistentIdentifier>
    @FocusState private var editing: Bool

    /// `preselected`: the payment rows already chosen (on the Mac, the selected rows of the table).
    init(month: Int, preselected: Set<PersistentIdentifier> = []) {
        self.month = month
        _selection = State(initialValue: preselected)
    }

    private var monthEntries: [PaymentEntry] {
        entries.filter { $0.month == month && $0.kid != nil }
            .sorted { $0.kid!.fullName.localizedStandardCompare($1.kid!.fullName) == .orderedAscending }
    }

    private var suggestions: [String] {
        [String(localized: "Kit"), String(localized: "Tournament"), String(localized: "Insurance"), String(localized: "Camp")]
    }

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0 && !selection.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Kit or Tournament", text: $title)
                        .focused($editing)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { title = suggestion }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                    .tint(title == suggestion ? Color.brand : .secondary)
                            }
                        }
                    }
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 80)
                            .focused($editing)
                        Text(verbatim: Money.symbol).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Charge")
                }

                if !monthEntries.isEmpty {
                    Section {
                        ForEach(monthEntries) { entry in
                            let chosen = selection.contains(entry.persistentModelID)
                            Button {
                                if chosen { selection.remove(entry.persistentModelID) } else { selection.insert(entry.persistentModelID) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(chosen ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.tertiary))
                                    if let kid = entry.kid {
                                        FlagBadge(code: kid.countryCode, size: 28)
                                        Text(kid.fullName).foregroundStyle(.primary)
                                    }
                                    Spacer()
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Kids on \(Month.title(month))")
                            Spacer()
                            Button(selection.count == monthEntries.count ? "Select None" : "Select All") {
                                selection = selection.count == monthEntries.count ? [] : Set(monthEntries.map(\.persistentModelID))
                            }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                        }
                    } footer: {
                        Text("Each kid gets it as a separate line in \(Month.title(month)), ticked on its own when it's paid.")
                    }
                }
            }
            .overlay {
                if monthEntries.isEmpty {
                    ContentUnavailableView("No Kids This Month", systemImage: "person.3",
                                           description: Text("Add the kids who train in \(Month.title(month)) first."))
                }
            }
            .navigationTitle("Add Charge")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(!canAdd)
                }
            }
        }
    }

    private func add() {
        let name = title.trimmingCharacters(in: .whitespaces)
        for entry in monthEntries where selection.contains(entry.persistentModelID) {
            let charge = ExtraCharge(title: name, amount: amount ?? 0)
            context.insert(charge)
            charge.entry = entry
        }
        close()
    }
}

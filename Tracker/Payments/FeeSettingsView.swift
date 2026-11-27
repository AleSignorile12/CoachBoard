import SwiftUI
import SwiftData

/// My Profile › Fees: the club's fee plans (each with a name, an amount and how often it's charged), the season
/// registration, when the season starts and the currency. New amounts count from this month on; earlier months
/// keep the ones they had.
struct FeeSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(FeePlans.storageKey) private var plansRaw = ""
    @AppStorage(FeeAmounts.registrationKey) private var registration = FeeAmounts.original.registration
    @AppStorage(SeasonSettings.registrationOnKey) private var registrationOn = true
    @AppStorage(SeasonSettings.startKey) private var seasonStart = 9
    @AppStorage(Money.storageKey) private var currency = "EUR"
    @State private var plans: [FeePlan] = FeePlans.all()
    @FocusState private var editing: Bool

    var body: some View {
        Form {
            Section {
                ForEach($plans) { $plan in
                    PlanRow(plan: $plan, editing: $editing, canDelete: plans.count > 1) { remove(plan) }
                        .deleteDisabled(plans.count <= 1)
                }
                .onDelete { offsets in
                    guard plans.count - offsets.count >= 1 else { return }
                    plans.remove(atOffsets: offsets)
                }
                .onMove { plans.move(fromOffsets: $0, toOffset: $1) }
                Button(action: add) {
                    Label {
                        Text("Add Fee Plan")
                    } icon: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.brand)
                    }
                }
            } header: {
                Text("Fee Plans")
            } footer: {
                Text("Pick a plan for each kid in Payments; the first one is used for new kids. Quarterly and yearly plans are charged in the first month of each quarter or of the season, and the months in between show nothing to pay.")
            }

            Section {
                Toggle(isOn: $registrationOn) {
                    Label("Registration Fee", systemImage: "signature")
                }
                if registrationOn {
                    AmountRow(title: String(localized: "Registration"), icon: "number", value: $registration, editing: $editing)
                }
                Picker(selection: $seasonStart) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Calendar.current.standaloneMonthSymbols[month - 1].localizedCapitalized).tag(month)
                    }
                } label: {
                    Label("Season Starts In", systemImage: "calendar")
                }
            } header: {
                Text("Season")
            } footer: {
                Text(registrationOn
                     ? "The registration is paid once per season. A season runs twelve months from the month it starts in."
                     : "No registration: the Registration column and buttons are hidden. A season runs twelve months from the month it starts in.")
            }

            Section {
                NavigationLink {
                    CurrencyPickerView(selection: $currency)
                } label: {
                    LabeledContent {
                        Text(verbatim: Money.name(currency))
                    } label: {
                        Label("Currency", systemImage: Money.icon)
                    }
                }
            } footer: {
                Text("Only the symbol changes, the amounts stay as they are. New amounts count from this month on; earlier months keep the ones they had.")
            }
        }
        .navigationTitle("Fees")
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button(role: .confirm) { editing = false }
            }
        }
        .onChange(of: plans) { _, new in
            FeePlans.save(new)
            updateFromThisMonth()
        }
        // Changed on the coach's other device.
        .onChange(of: plansRaw) {
            let saved = FeePlans.all()
            if saved != plans { plans = saved }
        }
        .onChange(of: registration) { updateFromThisMonth() }
        // The start month moves the months quarterly and yearly plans fall due in.
        .onChange(of: seasonStart) { updateFromThisMonth() }
    }

    private func add() {
        plans.append(FeePlan(id: "plan-\(UUID().uuidString)", amount: plans.first?.amount ?? 0))
    }

    private func remove(_ plan: FeePlan) {
        guard plans.count > 1 else { return }
        plans.removeAll { $0.id == plan.id }
    }

    /// This month's and later lists take the new amounts; past months stay as they were.
    private func updateFromThisMonth() {
        let now = Month.key(.now)
        let entries = (try? context.fetch(FetchDescriptor<PaymentEntry>(predicate: #Predicate { $0.month >= now }))) ?? []
        for entry in entries { entry.updateAmounts() }
    }
}

/// One plan: its name (the built-in ones show their usual name until renamed), the amount and how often.
private struct PlanRow: View {
    @Binding var plan: FeePlan
    var editing: FocusState<Bool>.Binding
    let canDelete: Bool
    let delete: () -> Void

    private var placeholder: String {
        plan.isBuiltIn ? FeePlan(id: plan.id, amount: 0).title : String(localized: "Fee Name")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: plan.icon)
                    .foregroundStyle(Color.brand)
                    .frame(width: 24)
                TextField(placeholder, text: $plan.name)
                    .focused(editing)
                TextField("Amount", value: $plan.amount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 64)
                    .focused(editing)
                Text(verbatim: Money.symbol).foregroundStyle(.secondary)
#if targetEnvironment(macCatalyst)
                // No swipe on the Mac: delete in plain sight.
                if canDelete {
                    Button("Delete", systemImage: "trash", action: delete)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Delete")
                }
#endif
            }
            Picker("How Often", selection: $plan.frequency) {
                ForEach(FeeFrequency.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .onChange(of: plan.amount) { _, new in
            if new < 0 || new > 99999 { plan.amount = min(max(new, 0), 99999) }
        }
        .contextMenu {
            if canDelete {
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        }
    }
}

private struct AmountRow: View {
    let title: String
    let icon: String
    @Binding var value: Int
    var editing: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            TextField("Amount", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .focused(editing)
            Text(verbatim: Money.symbol).foregroundStyle(.secondary)
        }
        .onChange(of: value) { _, new in
            if new < 0 || new > 99999 { value = min(max(new, 0), 99999) }
        }
    }
}

/// Every currency, the usual ones first, with search.
private struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private static let common = ["EUR", "USD", "GBP", "CHF"]
    private static let all: [String] = Locale.commonISOCurrencyCodes.sorted {
        Money.name($0).localizedStandardCompare(Money.name($1)) == .orderedAscending
    }

    private var results: [String] {
        guard !search.isEmpty else { return Self.all }
        return Self.all.filter { Money.name($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Section("Common") {
                    ForEach(Self.common, id: \.self, content: row)
                }
            }
            Section("All Currencies") {
                ForEach(results, id: \.self, content: row)
            }
        }
        .searchable(text: $search, prompt: "Search currencies")
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                Text(verbatim: Money.name(code)).foregroundStyle(.primary)
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark").foregroundStyle(Color.brand).fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

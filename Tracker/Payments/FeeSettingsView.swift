import SwiftUI
import SwiftData

/// My Profile › Fees: how much the kids pay each month, with each variation, and the season registration.
/// New amounts count from this month on; earlier months keep the ones they had.
struct FeeSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(FeeAmounts.standardKey) private var standard = FeeAmounts.original.standard
    @AppStorage(FeeAmounts.siblingKey) private var sibling = FeeAmounts.original.sibling
    @AppStorage(FeeAmounts.friendKey) private var friend = FeeAmounts.original.friend
    @AppStorage(FeeAmounts.registrationKey) private var registration = FeeAmounts.original.registration
    @FocusState private var editing: Bool

    var body: some View {
        Form {
            Section {
                AmountRow(title: Fee.standard.title, icon: Fee.standard.icon, value: $standard, editing: $editing)
                AmountRow(title: Fee.sibling.title, icon: Fee.sibling.icon, value: $sibling, editing: $editing)
                AmountRow(title: Fee.friend.title, icon: Fee.friend.icon, value: $friend, editing: $editing)
            } header: {
                Text("Monthly Fee")
            } footer: {
                Text("Pick the fee for each kid in Payments by tapping it under their name.")
            }

            Section {
                AmountRow(title: String(localized: "Registration"), icon: "signature", value: $registration, editing: $editing)
            } header: {
                Text("Once per Season")
            } footer: {
                Text("New amounts count from this month on. Earlier months keep the amounts they had.")
            }
        }
        .navigationTitle("Fees")
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button(role: .confirm) { editing = false }
            }
        }
        .onChange(of: [standard, sibling, friend, registration]) { updateFromThisMonth() }
    }

    /// This month's and later lists take the new amounts; past months stay as they were.
    private func updateFromThisMonth() {
        let now = Month.key(.now)
        let entries = (try? context.fetch(FetchDescriptor<PaymentEntry>(predicate: #Predicate { $0.month >= now }))) ?? []
        for entry in entries { entry.updateAmounts() }
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
            Text(verbatim: "€").foregroundStyle(.secondary)
        }
        .onChange(of: value) { _, new in
            if new < 0 || new > 9999 { value = min(max(new, 0), 9999) }
        }
    }
}

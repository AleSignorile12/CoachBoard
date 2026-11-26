import SwiftUI

/// Seven round toggles, one per weekday, in the order this phone's week starts.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TrainingDays.weekOrder, id: \.self) { weekday in
                let isOn = days.contains(weekday)
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.45)) {
                        if isOn { days.remove(weekday) } else { days.insert(weekday) }
                    }
                } label: {
                    Text(Calendar.current.shortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 2)
                        // Each day takes an equal share of the width; the circle is as big as fits (44 pt high).
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            Circle().fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                        }
                        .scaleEffect(isOn ? 1 : 0.92)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrainingDays.name(weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// The calendar's "Training Days" sheet.
struct TrainingDaysSheet: View {
    @AppStorage(TrainingDays.storageKey) private var raw = TrainingDays.defaultValue
    @Environment(\.dismiss) private var dismiss

    private var days: Binding<Set<Int>> {
        Binding { TrainingDays.decode(raw) } set: { raw = TrainingDays.encode($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                WeekdayPicker(days: days)
                Text(days.wrappedValue.isEmpty
                     ? "Pick at least one day. Only training days can be marked in the calendar."
                     : "Practice on \(TrainingDays.list(days.wrappedValue, type: .and)). Only these days can be marked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.default, value: raw)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Training Days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(250)])
    }
}

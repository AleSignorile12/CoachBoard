import SwiftUI
import SwiftData

/// Practice log in the style of Apple Calendar's month view. Only Tuesdays and Thursdays can be marked:
/// practice (green) or no practice (red, with a reason).
struct PracticeCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var days: [PracticeDay]
    @State private var month = Month.key(.now)
    @State private var selected: Int?

    private let calendar = Calendar.current
    /// Calendar weekday numbers (Sunday = 1): Tuesday and Thursday.
    private static let practiceWeekdays: Set<Int> = [3, 5]

    private var records: [Int: PracticeDay] {
        Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Weeks of day keys (yyyymmdd); nil = empty cell outside this month.
    private var weeks: [[Int?]] {
        let first = Month.date(month)
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + (1...count).map { month * 100 + $0 }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var monthRecords: [PracticeDay] { days.filter { $0.day / 100 == month } }

    private var today: Int { Month.key(.now) * 100 + calendar.component(.day, from: .now) }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100)) ?? .now
    }

    private func isPracticeDay(_ day: Int) -> Bool {
        Self.practiceWeekdays.contains(calendar.component(.weekday, from: date(day)))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(Month.date(month).formatted(.dateTime.month(.wide)))
                    .font(.largeTitle.bold())
                    .contentTransition(.numericText())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                weekdayRow
                Divider()
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day, topLine: index > 0)
                            } else {
                                // Fixed height: an unsized Color.clear would stretch the row.
                                Color.clear.frame(maxWidth: .infinity).frame(height: rowHeight)
                            }
                        }
                    }
                }
                Divider()
                practiceArea
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { changeMonth(1) }
                if value.translation.width > 60 { changeMonth(-1) }
            })
            .background(Color(.systemBackground))
            .sensoryFeedback(.selection, trigger: selected)
            .sensoryFeedback(.selection, trigger: month)
            .navigationTitle(String(month / 100))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Previous Month", systemImage: "chevron.left") { changeMonth(-1) }
                    Button("Next Month", systemImage: "chevron.right") { changeMonth(1) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Today") {
                        withAnimation(.snappy) { month = Month.key(.now) }
                        selected = isPracticeDay(today) ? today : nil
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
        }
    }

    // MARK: Pieces

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                let weekday = (calendar.firstWeekday - 1 + index) % 7 + 1
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.practiceWeekdays.contains(weekday) ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 6)
    }

    // Same size as the HIG Title 3 style (20 pt), scaled with the user's text size.
    @ScaledMetric(relativeTo: .title3) private var daySize: CGFloat = 20
    @ScaledMetric(relativeTo: .title3) private var circleSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title3) private var rowHeight: CGFloat = 56

    /// Like Apple Calendar: number near the top, small circle, dot underneath, and a hairline above
    /// each day (so lines stop where the month's days stop).
    private func dayCell(_ day: Int, topLine: Bool) -> some View {
        let record = records[day]
        let enabled = isPracticeDay(day)
        let isSelected = selected == day
        let isToday = day == today
        // Today is a black circle while nothing else is selected (a red number otherwise, like Apple Calendar);
        // a logged day keeps its green/red; a selected day is a black circle.
        let todayCircle = isToday && (isSelected || selected == nil)
        let fill: Color? = record.map { $0.held ? .green : .red } ?? (todayCircle || isSelected ? .primary : nil)

        return Button {
            if enabled { selected = day }
        } label: {
            VStack(spacing: 4) {
                // Proportional digits on purpose: tabular ones push "1"/"10" off the circle's center.
                Text("\(day % 100)")
                    .font(.system(size: daySize, weight: .semibold))
                    .foregroundStyle(textStyle(fill: fill, enabled: enabled, isToday: isToday))
                    .frame(width: circleSize, height: circleSize)
                    .background { if let fill { Circle().fill(fill) } }
                    .overlay {
                        // Selected day that already has a color: thin ring so the selection stays visible.
                        if isSelected && record != nil { Circle().stroke(.primary, lineWidth: 1.5).padding(-3) }
                    }
                // Gray dot = a reason is written for this day.
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(record.map { !$0.held && !$0.note.isEmpty } == true ? 1 : 0)
            }
            .padding(.top, 7)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that also fades the gray days and their hairline. Non-practice days just ignore taps.
        .allowsHitTesting(enabled)
        .accessibilityHidden(!enabled)
        .overlay(alignment: .top) { if topLine { Divider() } }
        .accessibilityLabel(date(day).formatted(date: .complete, time: .omitted))
        .accessibilityValue(record.map { $0.held ? "Practice" : "No practice" } ?? "")
    }

    private func textStyle(fill: Color?, enabled: Bool, isToday: Bool) -> AnyShapeStyle {
        // Selection circle is black in light mode, white in dark mode: invert the number.
        if fill == .primary { return AnyShapeStyle(Color(.systemBackground)) }
        if fill != nil { return AnyShapeStyle(.white) }
        if isToday { return AnyShapeStyle(.red) }
        return enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    /// Where Apple Calendar lists the day's events: the selected day's practice, or a placeholder.
    private var practiceArea: some View {
        VStack(spacing: 0) {
            if let selected {
                DayDetail(date: date(selected), record: records[selected]) { held in
                    set(selected, held: held)
                } onClear: {
                    if let record = records[selected] { context.delete(record) }
                }
                .padding(16)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("No Day Selected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Tap a Tuesday or Thursday")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
            Text("\(monthRecords.filter(\.held).count) practices · \(monthRecords.filter { !$0.held }.count) missed this month")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func changeMonth(_ delta: Int) {
        withAnimation(.snappy) { month = Month.add(delta, to: month) }
        selected = nil
    }

    private func set(_ day: Int, held: Bool) {
        if let record = records[day] {
            record.held = held
        } else {
            context.insert(PracticeDay(day: day, held: held))
        }
    }
}

private struct DayDetail: View {
    let date: Date
    let record: PracticeDay?
    let onSet: (Bool) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                Spacer()
                if record != nil {
                    Button("Clear", role: .destructive, action: onClear)
                        .font(.subheadline)
                }
            }
            HStack(spacing: 10) {
                choice("Practice", systemImage: "checkmark", color: .green, isOn: record?.held == true) { onSet(true) }
                choice("No Practice", systemImage: "xmark", color: .red, isOn: record?.held == false) { onSet(false) }
            }
            if let record, !record.held {
                ReasonField(record: record)
            }
        }
        .sensoryFeedback(.selection, trigger: record?.held)
    }

    private func choice(_ title: String, systemImage: String, color: Color, isOn: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? .white : color)
                .background(isOn ? color : color.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ReasonField: View {
    @Bindable var record: PracticeDay

    var body: some View {
        TextField("Reason (rain, holiday…)", text: $record.note, axis: .vertical)
            .lineLimit(2...6)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}

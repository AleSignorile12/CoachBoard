import SwiftUI
import SwiftData

/// Practice log in the style of Apple Calendar's month view. Only the team's training days can be marked
/// (Tuesday and Thursday unless changed): practice (green) or no practice (red), plus a note.
struct PracticeCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var days: [PracticeDay]
    @State private var month = Month.key(.now)
    @State private var selected: Int?
    @State private var showTrainingDays = false
    @AppStorage(TrainingDays.storageKey) private var trainingRaw = TrainingDays.defaultValue

    private let calendar = Calendar.current
    /// Calendar weekday numbers (Sunday = 1).
    private var practiceWeekdays: Set<Int> { TrainingDays.decode(trainingRaw) }

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

    private var monthRecords: [PracticeDay] { days.filter { $0.day / 100 == month && $0.logged } }

    /// Practices held in a row, counting back from today (a missed practice breaks it).
    private var streak: Int {
        let logged = days.filter { $0.logged && $0.day <= today }.sorted { $0.day > $1.day }
        return logged.prefix { $0.held }.count
    }

    private var today: Int { Month.key(.now) * 100 + calendar.component(.day, from: .now) }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100)) ?? .now
    }

    private func isPracticeDay(_ day: Int) -> Bool {
        practiceWeekdays.contains(calendar.component(.weekday, from: date(day)))
    }

    /// Training days, plus any day that already has something saved (so it can still be edited or cleared
    /// after its weekday stops being a training day).
    private func isEnabled(_ day: Int) -> Bool {
        isPracticeDay(day) || records[day] != nil
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
                        selected = isEnabled(today) ? today : nil
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Training Days", systemImage: "figure.run") { showTrainingDays = true }
                        .popButton()
                }
            }
            .sheet(isPresented: $showTrainingDays) { TrainingDaysSheet() }
            .onChange(of: trainingRaw) {
                if let day = selected, !isEnabled(day) { selected = nil }
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
                    .foregroundStyle(practiceWeekdays.contains(weekday) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
        let enabled = isEnabled(day)
        let status = record.flatMap { $0.logged ? $0 : nil }
        let isSelected = selected == day
        let isToday = day == today
        // Today is a black circle while nothing else is selected (a red number otherwise, like Apple Calendar);
        // a logged day keeps its green/red; a selected day is a black circle.
        let todayCircle = isToday && (isSelected || selected == nil)
        let fill: Color? = status.map { $0.held ? .accentColor : .red } ?? (todayCircle || isSelected ? .primary : nil)

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
                        if isSelected && status != nil { Circle().stroke(.primary, lineWidth: 1.5).padding(-3) }
                    }
                // Gray dot = this day has a note.
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(record?.note.isEmpty == false ? 1 : 0)
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
        .accessibilityValue([status.map { $0.held ? "Practice" : "No practice" },
                             record?.note.isEmpty == false ? "Has a note" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    private func textStyle(fill: Color?, enabled: Bool, isToday: Bool) -> AnyShapeStyle {
        // Selection circle is black in light mode, white in dark mode: invert the number.
        if fill == .primary { return AnyShapeStyle(Color(.systemBackground)) }
        if fill != nil { return AnyShapeStyle(.white) }
        if isToday { return AnyShapeStyle(.red) }
        return enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    /// Where Apple Calendar lists the day's events: the selected day's practice and note, or a placeholder.
    private var practiceArea: some View {
        VStack(spacing: 0) {
            if let selected {
                ScrollView {
                    DayDetail(date: date(selected), record: records[selected]) { held in
                        set(selected, held: held)
                    } onClear: {
                        clear(selected)
                    } onNote: { text in
                        setNote(selected, text)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            } else if practiceWeekdays.isEmpty {
                Spacer(minLength: 0)
                Text("No Training Days")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button("Choose Training Days", systemImage: "figure.run") { showTrainingDays = true }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("No Day Selected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Tap a \(TrainingDays.list(practiceWeekdays))")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
            summary
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Text("This month: \(monthRecords.filter(\.held).count) held · \(monthRecords.filter { !$0.held }.count) missed")
            if streak >= 2 {
                Text("· 🔥 \(streak) in a row")
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .animation(.snappy, value: streak)
    }

    // MARK: Actions

    private func changeMonth(_ delta: Int) {
        withAnimation(.snappy) { month = Month.add(delta, to: month) }
        selected = nil
    }

    private func set(_ day: Int, held: Bool) {
        if let record = records[day] {
            record.held = held
            record.logged = true
        } else {
            context.insert(PracticeDay(day: day, held: held))
        }
    }

    /// Clears the practice / no practice choice; a written note stays.
    private func clear(_ day: Int) {
        guard let record = records[day] else { return }
        if record.note.isEmpty { context.delete(record) } else { record.logged = false }
    }

    /// A note on a day with nothing saved yet creates a note-only record; emptying it removes that record again.
    private func setNote(_ day: Int, _ text: String) {
        if let record = records[day] {
            record.note = text
            if !record.logged && text.isEmpty { context.delete(record) }
        } else if !text.isEmpty {
            let record = PracticeDay(day: day, held: true)
            record.logged = false
            record.note = text
            context.insert(record)
        }
    }
}

private struct DayDetail: View {
    let date: Date
    let record: PracticeDay?
    let onSet: (Bool) -> Void
    let onClear: () -> Void
    let onNote: (String) -> Void

    private var status: PracticeDay? { record.flatMap { $0.logged ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                Spacer()
                if status != nil {
                    Button("Clear", role: .destructive, action: onClear)
                        .font(.subheadline)
                }
            }
            HStack(spacing: 10) {
                choice("Practice", systemImage: "checkmark", color: .accentColor, isOn: status?.held == true) { onSet(true) }
                choice("No Practice", systemImage: "xmark", color: .red, isOn: status?.held == false) { onSet(false) }
            }
            NoteField(note: record?.note ?? "", missed: status?.held == false, onChange: onNote)
        }
        .sensoryFeedback(.selection, trigger: status?.held)
    }

    private func choice(_ title: LocalizedStringKey, systemImage: String, color: Color, isOn: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? .white : color)
                .background(isOn ? color : color.opacity(0.12), in: .capsule)
                .symbolEffect(.bounce, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Note for the selected day. Works on any training day, marked or not.
private struct NoteField: View {
    let note: String
    let missed: Bool
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Note", systemImage: "note.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(missed ? "Why no practice? (rain, holiday…)" : "Drills, who came, anything to remember",
                      text: Binding { note } set: { onChange($0) }, axis: .vertical)
                .lineLimit(2...6)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
    }
}

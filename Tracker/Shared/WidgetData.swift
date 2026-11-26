import SwiftUI
import SwiftData
import WidgetKit

extension WidgetSnapshot {
    /// Builds the widget summary from the app's data.
    @MainActor
    init(kids: [Kid], entries: [PaymentEntry], trainingRaw: String, now: Date = .now) {
        let month = Month.key(now)
        let list = entries.filter { $0.month == month && $0.kid != nil }
        func shortName(_ kid: Kid) -> String { kid.firstName.isEmpty ? kid.fullName : kid.firstName }
        self.init(
            birthdays: kids.filter { !$0.birthDateUnknown }.map { Birthday(name: shortName($0), birthDate: $0.birthDate) },
            month: month,
            monthTitle: Month.title(month),
            paid: list.filter(\.paid).count,
            total: list.count,
            unpaid: list.filter { !$0.paid }.compactMap { $0.kid.map(shortName) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            trainingWeekdays: TrainingDays.decode(trainingRaw).sorted()
        )
    }

    /// Saves the summary and refreshes the widgets when something changed.
    func publish() {
        if save() { WidgetCenter.shared.reloadAllTimelines() }
    }
}

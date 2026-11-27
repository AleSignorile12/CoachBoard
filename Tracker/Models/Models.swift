import Foundation
import SwiftData

// MARK: - Kid

@Model
final class Kid {
    var firstName: String = ""
    var lastName: String = ""
    var countryCode: String = "IT"
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -10, to: .now) ?? .now
    var parent1FirstName: String = ""
    var parent1LastName: String = ""
    var parent2FirstName: String = ""
    var parent2LastName: String = ""
    // Added in v1.1. Only ever ADD fields with defaults here: renaming or removing one can lose saved data.
    var birthDateUnknown: Bool = false
    var notes: String = ""
    var createdAt: Date = Date.now
    /// Unused since registration became per season (see `PaymentEntry.registrationPaid`).
    /// Kept so older saved data still loads; `PaymentsView` moves any value over once.
    var registrationMonth: Int? = nil

    // Optional because iCloud sync (CloudKit) requires every relationship to be optional.
    @Relationship(deleteRule: .cascade, inverse: \StoredFile.kid)
    var files: [StoredFile]? = []

    @Relationship(deleteRule: .cascade, inverse: \PaymentEntry.kid)
    var payments: [PaymentEntry]? = []

    init() {}

    var fullName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "New Kid") : name
    }

    var flag: String { Country.flag(countryCode) }

    /// Goes up on the birthday itself (date only, ignoring the time of day saved with the birth date).
    var age: Int { BirthdayReminders.age(born: birthDate, on: .now) }

    var isBirthdayToday: Bool { !birthDateUnknown && BirthdayReminders.isBirthday(born: birthDate, on: .now) }

    var ageText: String {
        birthDateUnknown ? String(localized: "Age TBD") : String(localized: "\(age) years")
    }

    func file(_ kind: FileKind) -> StoredFile? {
        files?.first { $0.kind == kind }
    }

    var certificationCount: Int {
        FileKind.certifications.filter { file($0) != nil }.count
    }

    var certificationsComplete: Bool {
        certificationCount == FileKind.certifications.count
    }

    /// 0…1, how many of the tracked certificates are in (1 when none are tracked).
    var certificationProgress: Double {
        let tracked = FileKind.certifications.count
        return tracked == 0 ? 1 : Double(certificationCount) / Double(tracked)
    }

    /// True when the birthday falls in the given month (yyyymm).
    func hasBirthday(inMonth key: Int) -> Bool {
        !birthDateUnknown && Calendar.current.component(.month, from: birthDate) == key % 100
    }

    /// The month entry where this season's registration was paid, if any.
    func registrationEntry(season: Int) -> PaymentEntry? {
        payments?.first { $0.registrationPaid && Month.season($0.month) == season }
    }

    /// Fee used last time this kid was on a month list, so new months start with the right amount.
    var lastFee: Fee {
        payments?.max { $0.month < $1.month }?.fee.orFirst ?? .first
    }
}

// MARK: - Coach (the app owner)

@Model
final class Coach {
    var firstName: String = ""
    var lastName: String = ""
    var phone: String = ""
    var email: String = ""
    // Added in v1.3 (optional = safe for existing data).
    var birthDate: Date? = nil
    @Attribute(.externalStorage) var photo: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \StoredFile.coach)
    var files: [StoredFile]? = []

    init() {}
}

// MARK: - Practice log (added in v1.4: a new model is safe for existing data)

@Model
final class PracticeDay {
    /// Day as yyyymmdd, e.g. 20261104.
    var day: Int = 0
    var held: Bool = true
    /// Free note for the day: why there was no practice, what was worked on, who came…
    var note: String = ""
    /// Added in v1.5. False = the day only has a note, no practice / no practice choice yet.
    var logged: Bool = true

    init(day: Int, held: Bool) {
        self.day = day
        self.held = held
    }
}

// MARK: - Training days (added in v1.5)

/// Which weekdays the team trains, saved as calendar weekday numbers (Sunday = 1), e.g. "3,5".
nonisolated enum TrainingDays {
    static let storageKey = "trainingWeekdays"
    /// Tuesday and Thursday, the days the app was built around.
    static let defaultValue = "3,5"

    static func decode(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
    }

    static func encode(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    /// The seven weekdays in the order this phone's week starts (Monday first in Italy).
    static var weekOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func name(_ weekday: Int) -> String {
        Calendar.current.standaloneWeekdaySymbols[weekday - 1]
    }

    /// "Tuesday or Thursday" (or "… and …"), in week order and the phone's language.
    static func list(_ days: Set<Int>, type: ListFormatStyle<StringStyle, [String]>.ListType = .or) -> String {
        weekOrder.filter(days.contains).map(name).formatted(.list(type: type))
    }
}

// MARK: - Files

/// What a stored file is: one of the built-in slots, or a certificate the coach named in Settings
/// ("custom-…"). Saved as the bare string in `StoredFile.kindRaw`, exactly like the old enum, so every
/// existing file keeps its kind.
nonisolated struct FileKind: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    static let idCopy = FileKind(rawValue: "idCopy")
    static let medicalCertificate = FileKind(rawValue: "medicalCertificate")
    static let registrationForm = FileKind(rawValue: "registrationForm")
    static let coachID = FileKind(rawValue: "coachID")
    static let other = FileKind(rawValue: "other")

    /// The certificates the app can track out of the box.
    static let builtInCertifications: [FileKind] = [.medicalCertificate, .idCopy, .registrationForm]

    /// The certificates this coach tracks, in order (My Profile › Certificates).
    static var certifications: [FileKind] { CertificationTypes.active }

    var isCustom: Bool { rawValue.hasPrefix("custom-") }

    var title: String {
        switch self {
        case .idCopy: String(localized: "ID Copy")
        case .medicalCertificate: String(localized: "Medical Certificate")
        case .registrationForm: String(localized: "Registration Form")
        case .coachID: String(localized: "ID Document")
        case .other: String(localized: "File")
        default: CertificationTypes.name(of: self) ?? String(localized: "Custom Certificate")
        }
    }

    var icon: String {
        switch self {
        case .idCopy, .coachID: "person.text.rectangle"
        case .medicalCertificate: "cross.case"
        case .registrationForm: "doc.text"
        case .other: "doc"
        default: "rosette"
        }
    }
}

/// Which certificates are tracked, saved on this device (like the fees): the built-in ones can be switched off,
/// and the coach can add their own with any name (insurance, federation card…).
nonisolated enum CertificationTypes {
    static let storageKey = "certificationTypes"

    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var name: String?
        var isOn: Bool = true
    }

    /// Every built-in certificate (on unless switched off) followed by the coach's own.
    static func items(_ raw: String? = UserDefaults.standard.string(forKey: storageKey)) -> [Item] {
        let saved = raw.flatMap { try? JSONDecoder().decode([Item].self, from: Data($0.utf8)) } ?? []
        let builtIns = FileKind.builtInCertifications.map { kind in
            saved.first { $0.id == kind.rawValue } ?? Item(id: kind.rawValue)
        }
        return builtIns + saved.filter { FileKind(rawValue: $0.id).isCustom }
    }

    static func save(_ items: [Item]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: storageKey)
    }

    static var active: [FileKind] { items().filter(\.isOn).map { FileKind(rawValue: $0.id) } }

    static func name(of kind: FileKind) -> String? {
        items().first { $0.id == kind.rawValue }?.name.flatMap { $0.isEmpty ? nil : $0 }
    }
}

@Model
final class StoredFile {
    var name: String = ""
    var kindRaw: String = FileKind.other.rawValue
    @Attribute(.externalStorage) var data: Data = Data()
    var addedAt: Date = Date.now
    var kid: Kid?
    var coach: Coach?

    init(name: String, kind: FileKind, data: Data) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.data = data
    }

    var kind: FileKind { FileKind(rawValue: kindRaw) }
}

extension ModelContext {
    /// Slot kinds hold one file (a new upload replaces the old one); `.other` keeps every file.
    func storeFile(_ kind: FileKind, name: String, data: Data, kid: Kid? = nil, coach: Coach? = nil) {
        if kind != .other {
            (kid?.files ?? coach?.files ?? []).filter { $0.kind == kind }.forEach(delete)
        }
        let file = StoredFile(name: name, kind: kind, data: data)
        insert(file)
        file.kid = kid
        file.coach = coach
    }
}

// MARK: - Payments

/// How often a fee plan is charged. Quarterly and yearly plans fall due in the first month of each quarter or of
/// the season (counted from the month the season starts); the other months show nothing to pay.
enum FeeFrequency: String, Codable, CaseIterable, Identifiable {
    case monthly, quarterly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Quarterly")
        case .yearly: String(localized: "Yearly")
        }
    }

    /// True in the months this frequency asks for money.
    func isDue(inMonth key: Int) -> Bool {
        let fromStart = ((key % 100) - SeasonSettings.startMonth + 12) % 12
        switch self {
        case .monthly: return true
        case .quarterly: return fromStart % 3 == 0
        case .yearly: return fromStart == 0
        }
    }
}

/// One fee the coach charges, as set in My Profile › Fees: a name, an amount and how often.
/// The first three are the original ones (standard, sibling, friend) and keep their translated names until
/// the coach renames them.
struct FeePlan: Codable, Hashable, Identifiable {
    var id: String
    var name: String = ""
    var amount: Int
    var frequency: FeeFrequency = .monthly

    var isBuiltIn: Bool { ["standard", "sibling", "friend"].contains(id) }

    /// What the coach named it, or the built-in name.
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        switch id {
        case "standard": return String(localized: "Standard")
        case "sibling": return String(localized: "With sibling")
        case "friend": return String(localized: "With friend")
        default: return String(localized: "New Fee")
        }
    }

    var icon: String {
        switch id {
        case "standard": "person.fill"
        case "sibling": "person.2.fill"
        case "friend": "person.2.wave.2.fill"
        default: "tag.fill"
        }
    }
}

/// The coach's fee plans (synced through iCloud with the other settings, see SettingsSync).
enum FeePlans {
    static let storageKey = "feePlans"

    /// The saved plans, or the original three with the amounts set before plans existed.
    static func all(_ raw: String? = UserDefaults.standard.string(forKey: storageKey)) -> [FeePlan] {
        if let raw, let plans = try? JSONDecoder().decode([FeePlan].self, from: Data(raw.utf8)), !plans.isEmpty {
            return plans
        }
        return [
            FeePlan(id: "standard", amount: FeeAmounts.value(FeeAmounts.standardKey, FeeAmounts.original.standard)),
            FeePlan(id: "sibling", amount: FeeAmounts.value(FeeAmounts.siblingKey, FeeAmounts.original.sibling)),
            FeePlan(id: "friend", amount: FeeAmounts.value(FeeAmounts.friendKey, FeeAmounts.original.friend)),
        ]
    }

    static func save(_ plans: [FeePlan]) {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: storageKey)
    }

    static func plan(_ id: String) -> FeePlan? { all().first { $0.id == id } }
}

/// A kid's fee plan on a month list (stored by the plan's id). Was an enum of three fixed fees; the ids of those
/// three are kept, so older saved data reads the same.
struct Fee: RawRepresentable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    static let standard = Fee(rawValue: "standard")
    static let sibling = Fee(rawValue: "sibling")
    static let friend = Fee(rawValue: "friend")

    var id: String { rawValue }

    /// Every plan the coach has set up, in their order.
    static var allCases: [Fee] { FeePlans.all().map { Fee(rawValue: $0.id) } }

    /// The plans to choose from, plus `current` if its plan was deleted meanwhile (so a picker still shows it).
    static func choices(including current: Fee) -> [Fee] {
        let all = allCases
        return all.contains(current) ? all : all + [current]
    }

    /// The first plan: new kids start with it.
    static var first: Fee { allCases.first ?? .standard }

    /// This plan, or the first one if this one was deleted (for new month lists).
    var orFirst: Fee { plan == nil ? .first : self }

    var plan: FeePlan? { FeePlans.plan(rawValue) }

    var title: String { plan?.title ?? String(localized: "Deleted Fee") }
    var icon: String { plan?.icon ?? "tag" }
    var frequency: FeeFrequency { plan?.frequency ?? .monthly }

    /// The plan's amount as set in My Profile › Fees.
    var amount: Int { plan?.amount ?? 0 }

    /// What this plan costs in a given month: its amount when due, 0 in the months a quarterly or yearly plan skips.
    func amount(inMonth key: Int) -> Int { frequency.isDue(inMonth: key) ? amount : 0 }

    /// Registration fee, paid once per kid per season (as set in My Profile › Fees).
    static var registration: Int { FeeAmounts.registration }
}

/// The original fee amounts (before fee plans) and the registration amount, in whole units of the currency.
enum FeeAmounts {
    static let standardKey = "feeStandard", siblingKey = "feeSibling", friendKey = "feeFriend", registrationKey = "feeRegistration"

    /// The amounts before they could be changed. Payments saved back then have no amount of their own and use these.
    static let original = (standard: 30, sibling: 25, friend: 25, registration: 30)

    static var registration: Int { value(registrationKey, original.registration) }

    static func value(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
}

/// The season: the month it starts in and whether the club asks for a registration fee each season.
enum SeasonSettings {
    static let startKey = "seasonStartMonth", registrationOnKey = "feeRegistrationOn"

    /// 1…12, September unless the coach picked another month.
    static var startMonth: Int {
        let value = UserDefaults.standard.object(forKey: startKey) as? Int ?? 9
        return (1...12).contains(value) ? value : 9
    }

    static var registrationOn: Bool { UserDefaults.standard.object(forKey: registrationOnKey) as? Bool ?? true }

    /// "September – August".
    static var monthsTitle: String {
        let names = Calendar.current.standaloneMonthSymbols
        return "\(names[startMonth - 1].localizedCapitalized) – \(names[(startMonth + 10) % 12].localizedCapitalized)"
    }
}

/// The currency amounts are shown in. Amounts are whole numbers, so changing it only changes the symbol.
enum Money {
    static let storageKey = "currency"

    static var code: String { UserDefaults.standard.string(forKey: storageKey) ?? "EUR" }

    /// "30 €", "$30", "CHF 30"…
    static func format(_ amount: Int) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// "€", "$"…
    static var symbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    /// "Euro (€)".
    static func name(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let symbol = formatter.currencySymbol ?? code
        return symbol == code ? "\(name.localizedCapitalized) (\(code))" : "\(name.localizedCapitalized) (\(symbol))"
    }

    /// The SF Symbol for the currency in a circle, with a banknote for currencies without one.
    static var icon: String {
        let base: String? = switch code {
        case "EUR": "eurosign"
        case "USD", "CAD", "AUD", "NZD", "MXN", "ARS", "CLP", "COP", "SGD", "HKD": "dollarsign"
        case "GBP": "sterlingsign"
        case "CHF": "francsign"
        case "JPY", "CNY": "yensign"
        case "INR": "indianrupeesign"
        case "TRY": "turkishlirasign"
        case "BRL": "brazilianrealsign"
        case "RUB": "rublesign"
        case "KRW": "wonsign"
        case "UAH": "hryvniasign"
        case "PHP": "pesosign"
        case "ILS": "shekelsign"
        case "PLN": "polishzlotysign"
        case "BDT": "bangladeshitakasign"
        default: nil
        }
        return base.map { "\($0).circle" } ?? "banknote"
    }
}

/// A one-off charge on top of the monthly fee (kit, tournament, insurance, camp…), with its own paid tick.
/// Added in v1.6: a new model is safe for existing data.
@Model
final class ExtraCharge {
    var title: String = ""
    var amount: Int = 0
    var paid: Bool = false
    var createdAt: Date = Date.now
    var entry: PaymentEntry?

    init(title: String, amount: Int) {
        self.title = title
        self.amount = amount
    }
}

@Model
final class PaymentEntry {
    /// Month as yyyymm, e.g. 202611.
    var month: Int = 0
    var paid: Bool = false
    /// The fee plan and the amounts it had when set, as "standard|30|30|Standard" (plan id, amount this month,
    /// registration, plan name), so later changes in Fees don't rewrite past months. Older entries are
    /// "standard|30|30" or just "standard".
    var feeRaw: String = Fee.standard.rawValue
    /// Season registration paid in this month (at most one entry per kid per season).
    var registrationPaid: Bool = false
    var kid: Kid?

    // Added in v1.6. Optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \ExtraCharge.entry)
    var charges: [ExtraCharge]? = []

    init(month: Int, fee: Fee) {
        self.month = month
        self.fee = fee
    }

    private var parts: [Substring] { feeRaw.split(separator: "|", omittingEmptySubsequences: false) }

    var fee: Fee {
        get { parts.first.map { Fee(rawValue: String($0)) } ?? .standard }
        set {
            let old = parts.count > 1 ? amount : nil
            // A deleted plan keeps the amount and name it had.
            let new = newValue.plan == nil ? (newValue == fee ? amount : 0) : newValue.amount(inMonth: month)
            let name = (newValue.plan?.title ?? feeName).replacingOccurrences(of: "|", with: "/")
            feeRaw = "\(newValue.rawValue)|\(new)|\(Fee.registration)|\(name)"
            // Nothing to pay this month (a quarterly plan's off month, a free plan): counts as paid.
            if new == 0 { paid = true } else if old == 0 { paid = false }
        }
    }

    /// The plan's name, also after the plan was deleted.
    var feeName: String {
        if let plan = fee.plan { return plan.title }
        if parts.count > 3, !parts[3].isEmpty { return String(parts[3]) }
        return fee.title
    }

    /// The fee for this kid this month.
    var amount: Int {
        if parts.count > 1, let value = Int(parts[1]) { return value }
        return fee == .standard ? FeeAmounts.original.standard : FeeAmounts.original.sibling
    }

    /// What the season registration costs if it's paid in this month.
    var registrationAmount: Int {
        if parts.count > 2, let value = Int(parts[2]) { return value }
        return FeeAmounts.original.registration
    }

    /// The registration counted in this month's totals: its amount if paid this month, otherwise 0.
    var registrationTotal: Int { registrationPaid ? registrationAmount : 0 }

    /// One-off charges, oldest first.
    var sortedCharges: [ExtraCharge] { (charges ?? []).sorted { $0.createdAt < $1.createdAt } }

    var chargesTotal: Int { (charges ?? []).reduce(0) { $0 + $1.amount } }
    var chargesPaid: Int { (charges ?? []).filter(\.paid).reduce(0) { $0 + $1.amount } }

    /// Everything asked of this kid this month: fee, registration paid this month and one-off charges.
    var lineTotal: Int { amount + registrationTotal + chargesTotal }

    /// What has come in so far.
    var collected: Int { (paid ? amount : 0) + registrationTotal + chargesPaid }

    /// Fee and every charge paid.
    var settled: Bool { paid && (charges ?? []).allSatisfy(\.paid) }

    /// Takes the amounts currently set in Fees, keeping the fee plan.
    func updateAmounts() { fee = fee }
}

enum KidSort: String, CaseIterable, Identifiable {
    case name, age, nationality, newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .age: String(localized: "Age")
        case .nationality: String(localized: "Nationality")
        case .newest: String(localized: "Newest Added")
        }
    }

    var icon: String {
        switch self {
        case .name: "textformat"
        case .age: "birthday.cake"
        case .nationality: "flag"
        case .newest: "clock"
        }
    }

    func sorted(_ kids: [Kid]) -> [Kid] {
        kids.sorted { a, b in
            switch self {
            case .name:
                return a.fullName.localizedStandardCompare(b.fullName) == .orderedAscending
            case .age:
                // Youngest first, TBD at the end.
                if a.birthDateUnknown != b.birthDateUnknown { return b.birthDateUnknown }
                return a.birthDate > b.birthDate
            case .nationality:
                let (ca, cb) = (Country.name(a.countryCode), Country.name(b.countryCode))
                return ca == cb ? a.fullName < b.fullName : ca < cb
            case .newest:
                return a.createdAt > b.createdAt
            }
        }
    }
}

enum Month {
    static func key(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return c.year! * 100 + c.month!
    }

    static func add(_ months: Int, to key: Int) -> Int {
        let total = (key / 100) * 12 + (key % 100 - 1) + months
        return (total / 12) * 100 + total % 12 + 1
    }

    static func date(_ key: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: key / 100, month: key % 100)) ?? .now
    }

    static func title(_ key: Int) -> String {
        date(key).formatted(.dateTime.month(.wide).year())
    }

    /// "Sep 2026", for tight spaces.
    static func shortTitle(_ key: Int) -> String {
        date(key).formatted(.dateTime.month(.abbreviated).year())
    }

    /// Season = from the start month (September unless changed in Fees) for twelve months, named by its
    /// starting year (Sep 2026 – Aug 2027 → 2026).
    static func season(_ key: Int, start: Int = SeasonSettings.startMonth) -> Int {
        key % 100 >= start ? key / 100 : key / 100 - 1
    }

    /// The first month of a season (yyyymm).
    static func seasonStart(_ season: Int) -> Int { season * 100 + SeasonSettings.startMonth }

    static func seasonTitle(_ season: Int) -> String {
        "\(season)/\(String(format: "%02d", (season + 1) % 100))"
    }
}

// MARK: - Self-check (debug builds only)

enum SelfCheck {
    static func run() {
        assert(Month.add(-1, to: 202601) == 202512)
        assert(Month.add(1, to: 202612) == 202701)
        assert(Month.add(-13, to: 202611) == 202510)
        assert(Month.key(Month.date(202603)) == 202603)
        let old = PaymentEntry(month: 202610, fee: .standard)
        old.feeRaw = "sibling"
        assert(old.fee == .sibling && old.amount == 25 && old.registrationAmount == 30)
        old.feeRaw = "friend|28|35"
        assert(old.fee == .friend && old.amount == 28 && old.registrationAmount == 35)
        assert(Month.season(202609, start: 9) == 2026 && Month.season(202706, start: 9) == 2026 && Month.season(202608, start: 9) == 2025)
        assert(Month.season(202601, start: 1) == 2026 && Month.season(202612, start: 1) == 2026)
        assert(Month.seasonTitle(2026) == "2026/27" && Month.seasonTitle(2099) == "2099/00")
        assert(Country.flag("it") == "🇮🇹")
        assert(TrainingDays.decode("3,5") == [3, 5] && TrainingDays.decode("") == [] && TrainingDays.decode("9,x,2") == [2])
        assert(TrainingDays.encode([5, 3]) == "3,5")
        assert(AppLanguage.allCases.count == 59 && AppLanguage.italian.flag == "🇮🇹")
    }
}

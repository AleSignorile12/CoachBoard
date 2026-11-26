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
        payments?.max { $0.month < $1.month }?.fee ?? .standard
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

enum FileKind: String, CaseIterable {
    case idCopy, medicalCertificate, registrationForm, coachID, other

    static let certifications: [FileKind] = [.medicalCertificate, .idCopy, .registrationForm]

    var title: String {
        switch self {
        case .idCopy: String(localized: "ID Copy")
        case .medicalCertificate: String(localized: "Medical Certificate")
        case .registrationForm: String(localized: "Registration Form")
        case .coachID: String(localized: "ID Document")
        case .other: String(localized: "File")
        }
    }

    var icon: String {
        switch self {
        case .idCopy, .coachID: "person.text.rectangle"
        case .medicalCertificate: "cross.case"
        case .registrationForm: "doc.text"
        case .other: "doc"
        }
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

    var kind: FileKind { FileKind(rawValue: kindRaw) ?? .other }
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

enum Fee: String, CaseIterable, Identifiable {
    case standard, sibling, friend

    var id: String { rawValue }

    var amount: Int { self == .standard ? 30 : 25 }

    /// Registration fee, paid once per kid per season.
    static let registration = 30

    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .sibling: String(localized: "With sibling")
        case .friend: String(localized: "With friend")
        }
    }

    var icon: String {
        switch self {
        case .standard: "person.fill"
        case .sibling: "person.2.fill"
        case .friend: "person.2.wave.2.fill"
        }
    }
}

@Model
final class PaymentEntry {
    /// Month as yyyymm, e.g. 202611.
    var month: Int = 0
    var paid: Bool = false
    var feeRaw: String = Fee.standard.rawValue
    /// Season registration paid in this month (at most one entry per kid per season).
    var registrationPaid: Bool = false
    var kid: Kid?

    init(month: Int, fee: Fee) {
        self.month = month
        self.feeRaw = fee.rawValue
    }

    var fee: Fee {
        get { Fee(rawValue: feeRaw) ?? .standard }
        set { feeRaw = newValue.rawValue }
    }
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

    /// Season = September to August, named by its starting year (Sep 2026 – Aug 2027 → 2026).
    static func season(_ key: Int) -> Int {
        key % 100 >= 9 ? key / 100 : key / 100 - 1
    }

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
        assert(Fee.standard.amount == 30 && Fee.sibling.amount == 25 && Fee.friend.amount == 25)
        assert(Month.season(202609) == 2026 && Month.season(202706) == 2026 && Month.season(202608) == 2025)
        assert(Month.seasonTitle(2026) == "2026/27" && Month.seasonTitle(2099) == "2099/00")
        assert(Country.flag("it") == "🇮🇹")
        assert(TrainingDays.decode("3,5") == [3, 5] && TrainingDays.decode("") == [] && TrainingDays.decode("9,x,2") == [2])
        assert(TrainingDays.encode([5, 3]) == "3,5")
        assert(AppLanguage.allCases.count == 59 && AppLanguage.italian.flag == "🇮🇹")
    }
}

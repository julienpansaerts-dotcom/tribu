import Foundation

/// Jours fériés belges et congés scolaires de la Fédération Wallonie-Bruxelles.
enum BelgianCalendar {
    struct Period: Identifiable, Hashable {
        var id: String { name + String(start.timeIntervalSince1970) }
        let name: String
        let start: Date
        let end: Date

        func contains(_ date: Date) -> Bool {
            let day = Calendar.current.startOfDay(for: date)
            return day >= start && day <= end
        }
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d)) ?? .distantPast
    }

    /// Dimanche de Pâques (algorithme grégorien anonyme).
    static func easter(_ year: Int) -> Date {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return date(year, month, day)
    }

    static func holidays(_ year: Int) -> [Period] {
        let e = easter(year)
        func plus(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: e) ?? e }
        let list: [(String, Date)] = [
            ("Nouvel An", date(year, 1, 1)),
            ("Lundi de Pâques", plus(1)),
            ("Fête du Travail", date(year, 5, 1)),
            ("Ascension", plus(39)),
            ("Lundi de Pentecôte", plus(50)),
            ("Fête nationale", date(year, 7, 21)),
            ("Assomption", date(year, 8, 15)),
            ("Toussaint", date(year, 11, 1)),
            ("Armistice", date(year, 11, 11)),
            ("Noël", date(year, 12, 25)),
        ]
        return list.map { Period(name: $0.0, start: $0.1, end: $0.1) }
    }

    /// Congés scolaires FWB (enseignement fondamental et secondaire), selon les décrets publiés.
    /// Les années suivantes seront ajoutées quand la Fédération les publiera.
    static let schoolHolidays: [Period] = [
        Period(name: "Congé d'automne", start: date(2025, 10, 20), end: date(2025, 10, 31)),
        Period(name: "Vacances d'hiver", start: date(2025, 12, 22), end: date(2026, 1, 2)),
        Period(name: "Congé de détente", start: date(2026, 2, 16), end: date(2026, 2, 27)),
        Period(name: "Vacances de printemps", start: date(2026, 4, 27), end: date(2026, 5, 8)),
        Period(name: "Vacances d'été", start: date(2026, 7, 4), end: date(2026, 8, 23)),
        Period(name: "Congé d'automne", start: date(2026, 10, 19), end: date(2026, 10, 30)),
        Period(name: "Vacances d'hiver", start: date(2026, 12, 21), end: date(2027, 1, 1)),
        Period(name: "Congé de détente", start: date(2027, 2, 22), end: date(2027, 3, 5)),
        Period(name: "Vacances de printemps", start: date(2027, 4, 26), end: date(2027, 5, 7)),
        Period(name: "Vacances d'été", start: date(2027, 7, 3), end: date(2027, 8, 22)),
    ]

    static func labels(for day: Date) -> [String] {
        let year = Calendar.current.component(.year, from: day)
        var result = holidays(year).filter { $0.contains(day) }.map { "Férié · \($0.name)" }
        result += schoolHolidays.filter { $0.contains(day) }.map(\.name)
        return result
    }
}

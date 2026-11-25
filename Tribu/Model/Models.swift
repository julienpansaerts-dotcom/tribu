import Foundation

/// Une personne de la famille. Elle peut avoir un compte dans l'app (adulte) ou non (jeune enfant).
struct Person: Identifiable, Hashable {
    let id: String
    var firstName: String
    var colorHex: UInt32
    var birthDate: Date?
    var bloodType: String?
    var allergies: [String]
    var notes: [String]
    var sizes: [SizeEntry]
    var growth: [GrowthPoint]

    var initial: String { String(firstName.prefix(1)).uppercased() }

    var isChild: Bool {
        guard let birthDate else { return false }
        return (Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 99) < 16
    }

    var ageText: String? {
        guard let birthDate else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month], from: birthDate, to: .now)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        if years < 2 { return "\(years * 12 + months) mois" }
        return months > 0 ? "\(years) ans \(months) mois" : "\(years) ans"
    }
}

/// Une taille ou une mesure : pointure, pantalon, pull…
struct SizeEntry: Identifiable, Hashable {
    let id: String
    var label: String
    var value: String
    var detail: String?
    var previousValue: String?
    var updatedAt: Date
    var updatedBy: String
}

/// Un point de la courbe de croissance.
struct GrowthPoint: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var heightCm: Double?
    var weightKg: Double?
}

/// Ce qui se passe aujourd'hui : rappel, rendez-vous ou repas.
struct AgendaItem: Identifiable, Hashable {
    enum Kind: Hashable { case reminder, event, meal }

    let id: String
    var time: String
    var title: String
    var detail: String
    var kind: Kind
    var personId: String?
    var isDone: Bool = false
}

/// Un article de la liste de courses.
struct ShoppingItem: Identifiable, Hashable {
    let id: String
    var name: String
    var quantity: String?
    var origin: String?
    var isChecked: Bool = false
}

/// Le repas prévu pour un soir.
struct Meal: Hashable {
    var title: String
    var minutes: Int
    var servings: Int
    var note: String
}

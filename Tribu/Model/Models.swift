import Foundation

/// Une personne de la famille. Elle peut avoir un compte dans l'app (adulte) ou non (jeune enfant).
struct Person: Identifiable, Hashable {
    let id: String
    var linkedUid: String? = nil
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

/// Un modèle de taille proposé à l'ajout, avec un exemple de valeur.
struct SizeTemplate: Identifiable, Hashable {
    let label: String
    let hint: String
    var id: String { label }

    init(_ label: String, _ hint: String) {
        self.label = label
        self.hint = hint
    }
}

enum SizeTemplates {
    static let adult: [SizeTemplate] = [
        SizeTemplate("Pull", "M ou 38"), SizeTemplate("T-shirt", "S"), SizeTemplate("Chemise", "41 (col)"), SizeTemplate("Pantalon", "38 ou W29 L32"),
        SizeTemplate("Jean", "W30 L32"), SizeTemplate("Short", "38"), SizeTemplate("Robe", "38"), SizeTemplate("Jupe", "38"), SizeTemplate("Veste", "M"),
        SizeTemplate("Manteau", "M"), SizeTemplate("Chaussures", "39"), SizeTemplate("Chaussettes", "39-42"), SizeTemplate("Sous-vêtements", "M"),
        SizeTemplate("Soutien-gorge", "85B"), SizeTemplate("Pyjama", "M"), SizeTemplate("Maillot de bain", "38"), SizeTemplate("Gants", "7"),
        SizeTemplate("Bague", "52"), SizeTemplate("Chapeau", "57 cm"), SizeTemplate("Ceinture", "90"),
    ]

    static let child: [SizeTemplate] = [
        SizeTemplate("Haut", "104 ou 4 ans"), SizeTemplate("Pantalon", "104"), SizeTemplate("Body", "86"), SizeTemplate("Pyjama", "4 ans"),
        SizeTemplate("Chaussures", "27"), SizeTemplate("Chaussons", "26"), SizeTemplate("Bottes", "27"), SizeTemplate("Manteau", "104"),
        SizeTemplate("Combinaison de ski", "110"), SizeTemplate("Bonnet", "52 cm"), SizeTemplate("Gants", "3-4 ans"),
        SizeTemplate("Maillot de bain", "4 ans"), SizeTemplate("Couches", "T4"), SizeTemplate("Chaussettes", "27-30"),
    ]
}

/// Un point de la courbe de croissance.
struct GrowthPoint: Identifiable, Hashable {
    var id: String = UUID().uuidString
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

import Foundation
import Observation

/// Données de la maisonnée.
///
/// Pour ce premier jalon, les données sont des exemples locaux : elles seront remplacées par la
/// synchronisation Firebase (partage en temps réel entre les membres) au jalon suivant.
@Observable
final class FamilyStore {
    var householdName: String
    var currentUserId: String
    var people: [Person]
    var today: [AgendaItem]
    var shopping: [ShoppingItem]
    var tonight: Meal?
    var unpaidBillsTotal: Decimal
    var unpaidBillsCount: Int
    var shopperName: String?

    init(
        householdName: String,
        currentUserId: String,
        people: [Person],
        today: [AgendaItem],
        shopping: [ShoppingItem],
        tonight: Meal?,
        unpaidBillsTotal: Decimal,
        unpaidBillsCount: Int,
        shopperName: String?
    ) {
        self.householdName = householdName
        self.currentUserId = currentUserId
        self.people = people
        self.today = today
        self.shopping = shopping
        self.tonight = tonight
        self.unpaidBillsTotal = unpaidBillsTotal
        self.unpaidBillsCount = unpaidBillsCount
        self.shopperName = shopperName
    }

    var currentUser: Person? { person(currentUserId) }

    func person(_ id: String?) -> Person? {
        guard let id else { return nil }
        return people.first { $0.id == id }
    }

    var remainingShopping: [ShoppingItem] { shopping.filter { !$0.isChecked } }

    func toggleDone(_ item: AgendaItem) {
        guard let index = today.firstIndex(where: { $0.id == item.id }) else { return }
        today[index].isDone.toggle()
    }

    /// Le changement de taille le plus récent, mis en avant sur l'écran d'accueil.
    var latestSizeChange: (person: Person, size: SizeEntry)? {
        var best: (person: Person, size: SizeEntry)?
        for person in people {
            for size in person.sizes where size.previousValue != nil {
                if let current = best, current.size.updatedAt >= size.updatedAt { continue }
                best = (person: person, size: size)
            }
        }
        return best
    }
}

extension FamilyStore {
    static func sample() -> FamilyStore {
        let cal = Calendar.current
        func yearsAgo(_ y: Int, months: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(year: -y, month: -months), to: .now) ?? .now
        }
        func monthsAgo(_ m: Int) -> Date { cal.date(byAdding: .month, value: -m, to: .now) ?? .now }
        let hourAgo = Date.now.addingTimeInterval(-3600)

        let camille = Person(
            id: "camille", firstName: "Camille", colorHex: 0xE8553B, birthDate: yearsAgo(34),
            bloodType: "O+", allergies: [], notes: ["Préfère les pulls en laine mérinos"],
            sizes: [
                SizeEntry(id: "c1", label: "Pull", value: "M", detail: "38", updatedAt: monthsAgo(4), updatedBy: "Camille"),
                SizeEntry(id: "c2", label: "Pantalon", value: "38", detail: "W29 L32", updatedAt: monthsAgo(4), updatedBy: "Camille"),
                SizeEntry(id: "c3", label: "Chaussures", value: "39", detail: nil, updatedAt: monthsAgo(8), updatedBy: "Camille"),
                SizeEntry(id: "c4", label: "T-shirt", value: "S", detail: nil, updatedAt: monthsAgo(8), updatedBy: "Camille"),
                SizeEntry(id: "c5", label: "Bague", value: "52", detail: nil, updatedAt: monthsAgo(12), updatedBy: "Alex"),
            ],
            growth: []
        )
        let alex = Person(
            id: "alex", firstName: "Alex", colorHex: 0x4F86C6, birthDate: yearsAgo(36),
            bloodType: "A+", allergies: ["Pénicilline"], notes: [],
            sizes: [
                SizeEntry(id: "a1", label: "Pull", value: "L", detail: nil, updatedAt: monthsAgo(3), updatedBy: "Alex"),
                SizeEntry(id: "a2", label: "Pantalon", value: "44", detail: "W32 L34", updatedAt: monthsAgo(3), updatedBy: "Alex"),
                SizeEntry(id: "a3", label: "Chaussures", value: "43", detail: nil, updatedAt: monthsAgo(6), updatedBy: "Alex"),
                SizeEntry(id: "a4", label: "Chemise", value: "41", detail: "col", updatedAt: monthsAgo(6), updatedBy: "Camille"),
            ],
            growth: []
        )
        let leo = Person(
            id: "leo", firstName: "Léo", colorHex: 0xF2B84B, birthDate: yearsAgo(4, months: 3),
            bloodType: "A+", allergies: ["Arachides"], notes: ["Trousse EpiPen dans le sac bleu", "Veilleuse obligatoire"],
            sizes: [
                SizeEntry(id: "l1", label: "Haut", value: "110", detail: "5 ans", updatedAt: monthsAgo(1), updatedBy: "Camille"),
                SizeEntry(id: "l2", label: "Pantalon", value: "104", detail: "4 ans, coupe slim", updatedAt: monthsAgo(2), updatedBy: "Camille"),
                SizeEntry(id: "l3", label: "Pointure", value: "28", detail: nil, previousValue: "27", updatedAt: hourAgo, updatedBy: "Alex"),
                SizeEntry(id: "l4", label: "Pyjama", value: "4A", detail: "prendre 5A", updatedAt: monthsAgo(2), updatedBy: "Camille"),
                SizeEntry(id: "l5", label: "Bonnet", value: "52", detail: "tour de tête", updatedAt: monthsAgo(9), updatedBy: "Alex"),
            ],
            growth: [
                GrowthPoint(date: monthsAgo(27), heightCm: 87, weightKg: 12.1),
                GrowthPoint(date: monthsAgo(21), heightCm: 92, weightKg: 13.4),
                GrowthPoint(date: monthsAgo(15), heightCm: 96, weightKg: 14.2),
                GrowthPoint(date: monthsAgo(9), heightCm: 100, weightKg: 15.3),
                GrowthPoint(date: monthsAgo(3), heightCm: 103.5, weightKg: 16.1),
                GrowthPoint(date: .now, heightCm: 106, weightKg: 16.8),
            ]
        )
        let nina = Person(
            id: "nina", firstName: "Nina", colorHex: 0x7FAF8B, birthDate: yearsAgo(1, months: 6),
            bloodType: nil, allergies: [], notes: ["Doudou lapin gris"],
            sizes: [
                SizeEntry(id: "n1", label: "Body", value: "86", detail: "18 mois", updatedAt: monthsAgo(1), updatedBy: "Camille"),
                SizeEntry(id: "n2", label: "Pointure", value: "21", detail: nil, updatedAt: monthsAgo(2), updatedBy: "Camille"),
                SizeEntry(id: "n3", label: "Couches", value: "T4", detail: "9–14 kg", updatedAt: monthsAgo(2), updatedBy: "Alex"),
            ],
            growth: []
        )

        return FamilyStore(
            householdName: "La tribu",
            currentUserId: "alex",
            people: [camille, alex, leo, nina],
            today: [
                AgendaItem(id: "t1", time: "09:00", title: "Acheter du pain", detail: "Rappel de Camille pour toi", kind: .reminder, personId: "camille"),
                AgendaItem(id: "t2", time: "10:30", title: "Vaccin de Nina", detail: "Dr Lambert · Alex y va", kind: .event, personId: "alex"),
                AgendaItem(id: "t3", time: "16:15", title: "Récupérer Léo à l'école", detail: "Camille", kind: .event, personId: "camille"),
                AgendaItem(id: "t4", time: "19:00", title: "Risotto aux champignons", detail: "À table", kind: .meal, personId: nil),
            ],
            shopping: [
                ShoppingItem(id: "s1", name: "Champignons de Paris", quantity: "400 g", origin: "Risotto"),
                ShoppingItem(id: "s2", name: "Oignons", quantity: "×3", origin: "Risotto + Chili"),
                ShoppingItem(id: "s3", name: "Parmesan", quantity: "80 g", origin: "Risotto"),
                ShoppingItem(id: "s4", name: "Lait demi-écrémé", quantity: "×2", origin: nil),
                ShoppingItem(id: "s5", name: "Bananes", quantity: nil, origin: nil),
                ShoppingItem(id: "s6", name: "Yaourts nature", quantity: "×8", origin: nil),
                ShoppingItem(id: "s7", name: "Œufs", quantity: "×12", origin: nil),
                ShoppingItem(id: "s8", name: "Bouillon de légumes", quantity: "1 l", origin: "Risotto"),
                ShoppingItem(id: "s9", name: "Pommes", quantity: "1 kg", origin: nil),
                ShoppingItem(id: "s10", name: "Pain gris", quantity: nil, origin: nil, isChecked: true),
                ShoppingItem(id: "s11", name: "Riz arborio", quantity: "300 g", origin: "Risotto", isChecked: true),
            ],
            tonight: Meal(title: "Risotto aux champignons", minutes: 35, servings: 4, note: "Tout est dans la liste"),
            unpaidBillsTotal: 214.60,
            unpaidBillsCount: 2,
            shopperName: "Camille"
        )
    }
}

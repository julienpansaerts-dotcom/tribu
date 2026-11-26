import Foundation
import Observation

/// Écritures vers le serveur. En mode démo, il n'y en a pas et le magasin modifie ses données localement.
protocol FamilyRemote: AnyObject {
    func savePerson(_ person: Person)
    func deletePerson(_ personId: String)
    func saveSize(_ size: SizeEntry, personId: String)
    func deleteSize(_ sizeId: String, personId: String)
    func saveGrowth(_ point: GrowthPoint, personId: String)
    func saveDocument(_ entry: IdentityDocument, personId: String)
    func deleteDocument(_ documentId: String, personId: String)
    func addShopping(name: String, quantity: String?, origin: String?)
    func setShopping(_ item: ShoppingItem, checked: Bool)
    func updateShoppingQuantity(_ item: ShoppingItem, quantity: String)
    func deleteShopping(_ itemIds: [String])
    func save(collection: String, id: String, data: [String: Any])
    func update(collection: String, id: String, fields: [String: Any])
    func delete(collection: String, id: String)
    func saveBudgets(_ budgets: [String: Double])
    func uploadImage(_ data: Data, name: String) async throws -> String
    func imageURL(path: String) async -> URL?
}

/// Données de la tribu, partagées en temps réel via Firebase (ou exemples locaux en mode démo).
@Observable
final class FamilyStore {
    /// Branché par la synchronisation Firebase ; nil en mode démo.
    @ObservationIgnored weak var remote: FamilyRemote?

    var householdName: String
    var currentUserId: String
    /// Identifiant de connexion de l'utilisateur (vide en mode démo).
    var currentUid: String = ""
    var people: [Person]
    var shopping: [ShoppingItem]
    var shopperName: String?
    var reminders: [Reminder] = []
    var events: [FamilyEvent] = []
    var recipes: [Recipe] = []
    var meals: [Meal] = []
    var tasks: [TaskItem] = []
    var expenses: [Expense] = []
    var activities: [Activity] = []
    var feed: [FeedEntry] = []
    var budgets: [String: Double] = [:]

    init(householdName: String, currentUserId: String, people: [Person], shopping: [ShoppingItem], shopperName: String?) {
        self.householdName = householdName
        self.currentUserId = currentUserId
        self.people = people
        self.shopping = shopping
        self.shopperName = shopperName
    }

    var currentUser: Person? { person(currentUserId) }
    var authorName: String { currentUser?.firstName ?? "" }

    func person(_ id: String?) -> Person? {
        guard let id else { return nil }
        return people.first { $0.id == id }
    }

    func names(_ ids: [String]) -> String {
        let list = ids.compactMap { person($0)?.firstName }
        if list.count == people.count, list.count > 1 { return "Tous" }
        return ListFormatter.localizedString(byJoining: list)
    }

    var remainingShopping: [ShoppingItem] { shopping.filter { !$0.isChecked } }

    // MARK: - Aujourd'hui

    var tonight: Meal? { meals.first { $0.id == Meal.key(for: .now) } }

    var unpaidExpenses: [Expense] { expenses.filter { !$0.isPaid } }
    var unpaidBillsCount: Int { unpaidExpenses.count }
    var unpaidBillsTotal: Decimal { Decimal(unpaidExpenses.reduce(0) { $0 + $1.amount }) }

    /// Ce qui se passe aujourd'hui : rappels, rendez-vous et repas, dans l'ordre.
    var today: [AgendaItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: .now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? .now
        let day = DateInterval(start: dayStart, end: dayEnd)
        var items: [AgendaItem] = []

        for reminder in reminders {
            let isToday = day.contains(reminder.dueAt)
            let overdue = reminder.dueAt < dayStart && !reminder.isDone
            let doneToday = reminder.doneAt.map { day.contains($0) } ?? false
            guard isToday || overdue || doneToday else { continue }
            let forNames = names(reminder.assigneeIds)
            let mine = reminder.assigneeIds.contains(currentUserId)
            items.append(AgendaItem(
                id: "r_" + reminder.id,
                time: overdue ? "En retard" : reminder.dueAt.formatted(date: .omitted, time: .shortened),
                title: reminder.title,
                detail: mine ? "Rappel de \(reminder.createdByName) pour toi" : "Rappel pour \(forNames)",
                kind: .reminder,
                personId: reminder.assigneeIds.first,
                isDone: reminder.isDone,
                sourceId: reminder.id,
                sortDate: reminder.dueAt
            ))
        }

        for event in events {
            for occurrence in event.occurrences(in: day) {
                items.append(AgendaItem(
                    id: "e_" + event.id + "_" + String(Int(occurrence.start.timeIntervalSince1970)),
                    time: occurrence.allDay ? "Journée" : occurrence.start.formatted(date: .omitted, time: .shortened),
                    title: occurrence.title,
                    detail: [names(occurrence.personIds), occurrence.location].filter { !$0.isEmpty }.joined(separator: " · "),
                    kind: .event,
                    personId: occurrence.personIds.first,
                    sourceId: event.id,
                    sortDate: occurrence.allDay ? dayStart : occurrence.start
                ))
            }
        }

        if let meal = tonight {
            let evening = cal.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
            items.append(AgendaItem(
                id: "m_" + meal.id,
                time: "19:00",
                title: meal.title,
                detail: meal.minutes > 0 ? "\(meal.minutes) min · \(meal.servings) pers." : "Au menu ce soir",
                kind: .meal,
                sourceId: meal.id,
                sortDate: evening
            ))
        }
        return items.sorted { $0.sortDate < $1.sortDate }
    }

    func toggleDone(_ item: AgendaItem) {
        guard item.kind == .reminder, let reminder = reminders.first(where: { $0.id == item.sourceId }) else { return }
        setReminder(reminder, done: !reminder.isDone)
    }

    /// Le changement de taille le plus récent, mis en avant sur l'écran d'accueil.
    var latestSizeChange: (person: Person, size: SizeEntry)? {
        var best: (person: Person, size: SizeEntry)?
        let limit = Date.now.addingTimeInterval(-30 * 24 * 3600)
        for person in people {
            for size in person.sizes where size.previousValue != nil && size.updatedAt > limit {
                if let current = best, current.size.updatedAt >= size.updatedAt { continue }
                best = (person: person, size: size)
            }
        }
        return best
    }

    // MARK: - Documents génériques

    func save<T: FamilyDocument>(_ item: T) {
        if let remote {
            remote.save(collection: T.collection, id: item.id, data: item.firestoreData)
            return
        }
        var list = self[keyPath: T.storePath]
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
        self[keyPath: T.storePath] = list
    }

    func delete<T: FamilyDocument>(_ item: T) {
        if let remote {
            remote.delete(collection: T.collection, id: item.id)
            return
        }
        self[keyPath: T.storePath].removeAll { $0.id == item.id }
    }

    /// Ajoute une ligne au fil d'activité de la tribu.
    func post(_ text: String, icon: String) {
        save(FeedEntry(text: text, actorName: authorName, icon: icon))
    }

    // MARK: - Rappels

    func setReminder(_ reminder: Reminder, done: Bool) {
        var updated = reminder
        updated.doneAt = done ? .now : nil
        updated.doneByName = done ? authorName : nil
        save(updated)
        if done { post("a validé « \(reminder.title) »", icon: "checkmark.circle") }
    }

    func markSeen(_ reminder: Reminder) {
        guard !currentUserId.isEmpty, reminder.assigneeIds.contains(currentUserId), !reminder.seenByIds.contains(currentUserId) else { return }
        var updated = reminder
        updated.seenByIds.append(currentUserId)
        save(updated)
    }

    // MARK: - Personnes et tailles

    func savePerson(_ person: Person) {
        if let remote { remote.savePerson(person); return }
        if let index = people.firstIndex(where: { $0.id == person.id }) {
            var updated = person
            updated.sizes = people[index].sizes
            updated.growth = people[index].growth
            updated.documents = people[index].documents
            people[index] = updated
        } else {
            people.append(person)
        }
    }

    func deletePerson(_ personId: String) {
        if let remote { remote.deletePerson(personId); return }
        people.removeAll { $0.id == personId }
    }

    func saveSize(_ size: SizeEntry, personId: String) {
        if size.previousValue != nil, size.updatedAt > Date.now.addingTimeInterval(-60), let p = person(personId) {
            post("a changé \(size.label.lowercased()) de \(p.firstName) : \(size.previousValue ?? "") → \(size.value)", icon: "ruler")
        }
        if let remote { remote.saveSize(size, personId: personId); return }
        guard let p = people.firstIndex(where: { $0.id == personId }) else { return }
        if let s = people[p].sizes.firstIndex(where: { $0.id == size.id }) {
            people[p].sizes[s] = size
        } else {
            people[p].sizes.append(size)
        }
    }

    func deleteSize(_ sizeId: String, personId: String) {
        if let remote { remote.deleteSize(sizeId, personId: personId); return }
        guard let p = people.firstIndex(where: { $0.id == personId }) else { return }
        people[p].sizes.removeAll { $0.id == sizeId }
    }

    func saveGrowth(_ point: GrowthPoint, personId: String) {
        if let remote { remote.saveGrowth(point, personId: personId); return }
        guard let p = people.firstIndex(where: { $0.id == personId }) else { return }
        people[p].growth.append(point)
        people[p].growth.sort { $0.date < $1.date }
    }

    func saveDocument(_ entry: IdentityDocument, personId: String) {
        if let remote { remote.saveDocument(entry, personId: personId); return }
        guard let p = people.firstIndex(where: { $0.id == personId }) else { return }
        if let d = people[p].documents.firstIndex(where: { $0.id == entry.id }) {
            people[p].documents[d] = entry
        } else {
            people[p].documents.append(entry)
        }
    }

    func deleteDocument(_ documentId: String, personId: String) {
        if let remote { remote.deleteDocument(documentId, personId: personId); return }
        guard let p = people.firstIndex(where: { $0.id == personId }) else { return }
        people[p].documents.removeAll { $0.id == documentId }
    }

    // MARK: - Courses

    func addShopping(name: String, quantity: String?, origin: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let remote { remote.addShopping(name: trimmed, quantity: quantity, origin: origin); return }
        shopping.insert(ShoppingItem(id: UUID().uuidString, name: trimmed, quantity: quantity, origin: origin), at: 0)
    }

    /// Ajoute des ingrédients en fusionnant avec les articles déjà sur la liste.
    func addIngredients(_ ingredients: [ParsedIngredient], origin: String) {
        for ingredient in ingredients {
            if let existing = remainingShopping.first(where: { IngredientParser.normalize($0.name) == IngredientParser.normalize(ingredient.name) }) {
                let merged = IngredientParser.merge(existing.quantity, ingredient.quantityText)
                if let remote {
                    remote.updateShoppingQuantity(existing, quantity: merged ?? existing.quantity ?? "")
                } else if let index = shopping.firstIndex(where: { $0.id == existing.id }) {
                    shopping[index].quantity = merged
                    shopping[index].origin = [existing.origin, origin].compactMap { $0 }.joined(separator: " + ")
                }
            } else {
                addShopping(name: ingredient.name, quantity: ingredient.quantityText, origin: origin)
            }
        }
        post("a ajouté \(ingredients.count) ingrédients de « \(origin) » aux courses", icon: "basket")
    }

    func toggleShopping(_ item: ShoppingItem) {
        if let remote { remote.setShopping(item, checked: !item.isChecked); return }
        guard let index = shopping.firstIndex(where: { $0.id == item.id }) else { return }
        shopping[index].isChecked.toggle()
    }

    func deleteShopping(_ items: [ShoppingItem]) {
        let ids = items.map(\.id)
        if let remote { remote.deleteShopping(ids); return }
        shopping.removeAll { ids.contains($0.id) }
    }

    // MARK: - Budget

    func saveBudgets(_ newBudgets: [String: Double]) {
        if let remote { remote.saveBudgets(newBudgets); return }
        budgets = newBudgets
    }
}

extension FamilyStore {
    /// Magasin vide, rempli par la synchronisation Firebase.
    static func empty() -> FamilyStore {
        FamilyStore(householdName: "", currentUserId: "", people: [], shopping: [], shopperName: nil)
    }

    /// Remet le magasin à zéro (déconnexion).
    func reset() {
        householdName = ""
        currentUserId = ""
        currentUid = ""
        people = []
        shopping = []
        shopperName = nil
        reminders = []
        events = []
        recipes = []
        meals = []
        tasks = []
        expenses = []
        activities = []
        feed = []
        budgets = [:]
    }

    static func sample() -> FamilyStore {
        let cal = Calendar.current
        func yearsAgo(_ y: Int, months: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(year: -y, month: -months), to: .now) ?? .now
        }
        func monthsAgo(_ m: Int) -> Date { cal.date(byAdding: .month, value: -m, to: .now) ?? .now }
        func today(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }
        func inDays(_ d: Int, _ hour: Int = 10) -> Date {
            cal.date(byAdding: .day, value: d, to: today(hour)) ?? .now
        }
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

        let store = FamilyStore(
            householdName: "La tribu",
            currentUserId: "alex",
            people: [camille, alex, leo, nina],
            shopping: [
                ShoppingItem(id: "s1", name: "Champignons de Paris", quantity: "400 g", origin: "Risotto"),
                ShoppingItem(id: "s2", name: "Oignons", quantity: "3", origin: "Risotto + Chili"),
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
            shopperName: "Camille"
        )
        store.reminders = [
            Reminder(id: "r1", title: "Acheter du pain", dueAt: today(9), offsets: [30, 0], assigneeIds: ["alex"],
                     createdById: "camille", createdByName: "Camille"),
            Reminder(id: "r2", title: "Appeler la crèche pour vendredi", dueAt: inDays(1, 8), offsets: [0], assigneeIds: ["camille"],
                     createdById: "alex", createdByName: "Alex"),
        ]
        store.events = [
            FamilyEvent(id: "e1", title: "Vaccin de Nina", start: today(10, 30), end: today(11), personIds: ["alex", "nina"], location: "Dr Lambert"),
            FamilyEvent(id: "e2", title: "Récupérer Léo à l'école", start: today(16, 15), end: today(16, 45), personIds: ["camille"], recurrence: .weekly),
            FamilyEvent(id: "e3", title: "Anniversaire de Mamie", start: inDays(3, 12), end: inDays(3, 16), personIds: [], location: "Namur"),
            FamilyEvent(id: "e4", title: "Piscine", start: inDays(2, 14), end: inDays(2, 15), personIds: ["leo", "alex"]),
        ]
        store.recipes = [
            Recipe(id: "rc1", url: "https://www.example.be/risotto", title: "Risotto aux champignons", servings: 4, totalMinutes: 35,
                   ingredients: ["300 g de riz arborio", "400 g de champignons de Paris", "1 oignon", "1 l de bouillon de légumes", "80 g de parmesan", "2 c. à soupe d'huile d'olive"],
                   steps: ["Émincer l'oignon et le faire revenir dans l'huile.", "Ajouter le riz et le nacrer 2 minutes.", "Verser le bouillon louche par louche en remuant.", "Ajouter les champignons poêlés et le parmesan."],
                   favorite: true, createdByName: "Camille"),
            Recipe(id: "rc2", title: "Curry de lentilles corail", servings: 4, totalMinutes: 30,
                   ingredients: ["250 g de lentilles corail", "400 ml de lait de coco", "1 oignon", "2 c. à café de curry"],
                   steps: ["Faire revenir l'oignon.", "Ajouter lentilles, coco et curry, cuire 20 minutes."], createdByName: "Alex"),
            Recipe(id: "rc3", title: "Tarte fine poireaux et chèvre", servings: 4, totalMinutes: 45,
                   ingredients: ["1 pâte feuilletée", "3 poireaux", "1 bûche de chèvre"], steps: ["Fondre les poireaux.", "Garnir la pâte et cuire 25 minutes."], createdByName: "Camille"),
        ]
        store.meals = [
            Meal(id: Meal.key(for: .now), recipeId: "rc1", title: "Risotto aux champignons", minutes: 35, servings: 4, note: "Tout est dans la liste"),
            Meal(id: Meal.key(for: inDays(1)), recipeId: "rc2", title: "Curry de lentilles corail", minutes: 30, servings: 4),
            Meal(id: Meal.key(for: inDays(2)), recipeId: "rc3", title: "Tarte fine poireaux et chèvre", minutes: 45, servings: 4),
        ]
        store.tasks = [
            TaskItem(id: "t1", title: "Repeindre la chambre de Léo", notes: "Couleur vert sauge, 2 couches.", status: .doing,
                     assigneeIds: ["alex"], dueDate: inDays(10), estimatedCost: 120,
                     checklist: [ChecklistEntry(text: "Acheter la peinture", done: true), ChecklistEntry(text: "Protéger le sol"), ChecklistEntry(text: "Première couche")],
                     comments: [TaskComment(text: "J'ai trouvé la teinte chez Brico !", authorName: "Camille", at: hourAgo)],
                     createdByName: "Camille", lastEditedByName: "Camille", lastChange: "a ajouté un commentaire"),
            TaskItem(id: "t2", title: "Réserver le stage de Pâques", assigneeIds: ["camille"], dueDate: inDays(4), createdByName: "Alex"),
            TaskItem(id: "t3", title: "Week-end à la mer en mai", notes: "Le Coq ou De Haan ?", kind: .idea,
                     estimatedCost: 450, links: ["https://www.example.be/location"], voterIds: ["alex", "camille"], createdByName: "Alex"),
        ]
        store.expenses = [
            Expense(id: "x1", vendor: "Engie", amount: 148.30, category: .energie, issueDate: inDays(-5), dueDate: inDays(6),
                    iban: "BE68 5390 0754 7034", communication: "+++090/9337/55493+++", recurrence: .monthly, createdByName: "Alex"),
            Expense(id: "x2", vendor: "Crèche Les Lutins", amount: 66.30, category: .enfants, issueDate: inDays(-2), dueDate: inDays(12), createdByName: "Camille"),
            Expense(id: "x3", vendor: "Delhaize", amount: 87.45, category: .courses, issueDate: inDays(-1), paidAt: inDays(-1), paidByName: "Camille"),
            Expense(id: "x4", vendor: "Proximus", amount: 59.99, category: .abonnements, issueDate: inDays(-8), paidAt: inDays(-3), paidByName: "Alex", recurrence: .monthly),
        ]
        store.budgets = ["courses": 600, "energie": 200, "enfants": 250, "loisirs": 150]
        store.activities = [
            Activity(id: "a1", title: "Pairi Daiza", details: "Prendre les billets en ligne, c'est moins cher.", tags: ["Journée", "Extérieur"], voterIds: ["alex", "camille"], createdByName: "Camille"),
            Activity(id: "a2", title: "Atelier poterie parent-enfant", tags: ["Pluie", "Grands"], voterIds: ["camille"], createdByName: "Camille"),
            Activity(id: "a3", title: "Balade au bois de la Cambre", tags: ["Gratuit", "Extérieur", "Petits"], createdByName: "Alex"),
        ]
        store.feed = [
            FeedEntry(text: "a ajouté 6 ingrédients du risotto aux courses", actorName: "Camille", icon: "basket", createdAt: Date.now.addingTimeInterval(-120)),
            FeedEntry(text: "a changé pointure de Léo : 27 → 28", actorName: "Alex", icon: "ruler", createdAt: hourAgo),
        ]
        return store
    }
}

import FirebaseFirestore
import Foundation

/// Un document Firestore de la tribu : lu depuis un dictionnaire, écrit vers un dictionnaire.
protocol FamilyDocument: Identifiable, Hashable {
    static var collection: String { get }
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Self]> { get }
    var id: String { get }
    init?(id: String, data: [String: Any])
    var firestoreData: [String: Any] { get }
}

// MARK: - Conversions

enum FS {
    static func date(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        return value as? Date
    }

    static func value(_ date: Date?) -> Any {
        date.map { Timestamp(date: $0) } ?? NSNull()
    }

    static func value(_ string: String?) -> Any {
        guard let string, !string.isEmpty else { return NSNull() }
        return string
    }

    static func value(_ number: Double?) -> Any {
        number.map { NSNumber(value: $0) } ?? NSNull()
    }

    static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    static func strings(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }
}

/// Répétition d'un rappel ou d'un événement.
enum Recurrence: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Jamais"
        case .daily: return "Tous les jours"
        case .weekly: return "Toutes les semaines"
        case .monthly: return "Tous les mois"
        case .yearly: return "Tous les ans"
        }
    }

    var component: Calendar.Component? {
        switch self {
        case .none: return nil
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }

    /// Prochaine occurrence strictement après `date`.
    func next(after start: Date, from date: Date = .now) -> Date? {
        guard let component else { return nil }
        var candidate = start
        var guardCount = 0
        while candidate <= date && guardCount < 5000 {
            guard let n = Calendar.current.date(byAdding: component, value: 1, to: candidate) else { return nil }
            candidate = n
            guardCount += 1
        }
        return candidate
    }
}

// MARK: - Rappels

struct Reminder: FamilyDocument {
    static let collection = "reminders"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Reminder]> { \.reminders }

    var id: String = UUID().uuidString
    var title: String
    var note: String = ""
    var dueAt: Date
    /// Minutes avant l'heure (0 = à l'heure).
    var offsets: [Int] = [0]
    var recurrence: Recurrence = .none
    var assigneeIds: [String]
    var createdById: String
    var createdByName: String
    var doneAt: Date?
    var doneByName: String?
    var seenByIds: [String] = []
    var createdAt: Date = .now

    var isDone: Bool { doneAt != nil }

    init(id: String = UUID().uuidString, title: String, note: String = "", dueAt: Date, offsets: [Int] = [0],
         recurrence: Recurrence = .none, assigneeIds: [String], createdById: String, createdByName: String,
         doneAt: Date? = nil, doneByName: String? = nil, seenByIds: [String] = [], createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.note = note
        self.dueAt = dueAt
        self.offsets = offsets
        self.recurrence = recurrence
        self.assigneeIds = assigneeIds
        self.createdById = createdById
        self.createdByName = createdByName
        self.doneAt = doneAt
        self.doneByName = doneByName
        self.seenByIds = seenByIds
        self.createdAt = createdAt
    }

    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String, let due = FS.date(data["dueAt"]) else { return nil }
        self.id = id
        self.title = title
        note = data["note"] as? String ?? ""
        dueAt = due
        offsets = (data["offsets"] as? [NSNumber])?.map(\.intValue) ?? [0]
        recurrence = Recurrence(rawValue: data["recurrence"] as? String ?? "") ?? .none
        assigneeIds = FS.strings(data["assigneeIds"])
        createdById = data["createdById"] as? String ?? ""
        createdByName = data["createdByName"] as? String ?? ""
        doneAt = FS.date(data["doneAt"])
        doneByName = data["doneByName"] as? String
        seenByIds = FS.strings(data["seenByIds"])
        createdAt = FS.date(data["createdAt"]) ?? .now
    }

    var firestoreData: [String: Any] {
        [
            "title": title,
            "note": note,
            "dueAt": Timestamp(date: dueAt),
            "offsets": offsets,
            "recurrence": recurrence.rawValue,
            "assigneeIds": assigneeIds,
            "createdById": createdById,
            "createdByName": createdByName,
            "doneAt": FS.value(doneAt),
            "doneByName": FS.value(doneByName),
            "seenByIds": seenByIds,
            "createdAt": Timestamp(date: createdAt),
        ]
    }

    static func offsetLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "À l'heure"
        case 1440: return "1 jour avant"
        case let m where m % 1440 == 0: return "\(m / 1440) jours avant"
        case let m where m % 60 == 0: return "\(m / 60) h avant"
        default: return "\(minutes) min avant"
        }
    }
}

// MARK: - Agenda

struct FamilyEvent: FamilyDocument {
    static let collection = "events"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [FamilyEvent]> { \.events }

    var id: String = UUID().uuidString
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool = false
    var personIds: [String] = []
    var location: String = ""
    var notes: String = ""
    var recurrence: Recurrence = .none
    /// Minutes avant l'événement pour la notification, nil = pas d'alerte.
    var alertMinutes: Int?
    var createdByName: String = ""

    init(id: String = UUID().uuidString, title: String, start: Date, end: Date, allDay: Bool = false,
         personIds: [String] = [], location: String = "", notes: String = "", recurrence: Recurrence = .none,
         alertMinutes: Int? = nil, createdByName: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.personIds = personIds
        self.location = location
        self.notes = notes
        self.recurrence = recurrence
        self.alertMinutes = alertMinutes
        self.createdByName = createdByName
    }

    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String, let start = FS.date(data["start"]) else { return nil }
        self.id = id
        self.title = title
        self.start = start
        end = FS.date(data["end"]) ?? start.addingTimeInterval(3600)
        allDay = data["allDay"] as? Bool ?? false
        personIds = FS.strings(data["personIds"])
        location = data["location"] as? String ?? ""
        notes = data["notes"] as? String ?? ""
        recurrence = Recurrence(rawValue: data["recurrence"] as? String ?? "") ?? .none
        alertMinutes = FS.int(data["alertMinutes"])
        createdByName = data["createdByName"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "title": title,
            "start": Timestamp(date: start),
            "end": Timestamp(date: end),
            "allDay": allDay,
            "personIds": personIds,
            "location": location,
            "notes": notes,
            "recurrence": recurrence.rawValue,
            "alertMinutes": alertMinutes.map { NSNumber(value: $0) } ?? NSNull(),
            "createdByName": createdByName,
        ]
    }

    /// Occurrences de l'événement qui touchent l'intervalle donné.
    func occurrences(in interval: DateInterval) -> [FamilyEvent] {
        let duration = end.timeIntervalSince(start)
        guard let component = recurrence.component else {
            return DateInterval(start: start, end: max(end, start)).intersects(interval) ? [self] : []
        }
        var result: [FamilyEvent] = []
        var occurrence = start
        var count = 0
        while occurrence < interval.end && count < 2000 {
            if occurrence.addingTimeInterval(max(duration, 1)) > interval.start {
                var copy = self
                copy.start = occurrence
                copy.end = occurrence.addingTimeInterval(duration)
                result.append(copy)
            }
            guard let next = Calendar.current.date(byAdding: component, value: 1, to: occurrence) else { break }
            occurrence = next
            count += 1
        }
        return result
    }
}

// MARK: - Recettes et menu

struct Recipe: FamilyDocument {
    static let collection = "recipes"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Recipe]> { \.recipes }

    var id: String = UUID().uuidString
    var url: String = ""
    var title: String
    var imageURL: String = ""
    var servings: Int = 4
    var totalMinutes: Int?
    var ingredients: [String] = []
    var steps: [String] = []
    var favorite: Bool = false
    var tags: [String] = []
    var createdByName: String = ""
    var createdAt: Date = .now

    init(id: String = UUID().uuidString, url: String = "", title: String, imageURL: String = "", servings: Int = 4,
         totalMinutes: Int? = nil, ingredients: [String] = [], steps: [String] = [], favorite: Bool = false,
         tags: [String] = [], createdByName: String = "", createdAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.imageURL = imageURL
        self.servings = servings
        self.totalMinutes = totalMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.favorite = favorite
        self.tags = tags
        self.createdByName = createdByName
        self.createdAt = createdAt
    }

    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String else { return nil }
        self.id = id
        self.title = title
        url = data["url"] as? String ?? ""
        imageURL = data["imageURL"] as? String ?? ""
        servings = FS.int(data["servings"]) ?? 4
        totalMinutes = FS.int(data["totalMinutes"])
        ingredients = FS.strings(data["ingredients"])
        steps = FS.strings(data["steps"])
        favorite = data["favorite"] as? Bool ?? false
        tags = FS.strings(data["tags"])
        createdByName = data["createdByName"] as? String ?? ""
        createdAt = FS.date(data["createdAt"]) ?? .now
    }

    var firestoreData: [String: Any] {
        [
            "url": url,
            "title": title,
            "imageURL": imageURL,
            "servings": servings,
            "totalMinutes": totalMinutes.map { NSNumber(value: $0) } ?? NSNull(),
            "ingredients": ingredients,
            "steps": steps,
            "favorite": favorite,
            "tags": tags,
            "createdByName": createdByName,
            "createdAt": Timestamp(date: createdAt),
        ]
    }

    var host: String {
        URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
    }
}

/// Repas prévu un jour donné. L'identifiant est la date au format « 2026-11-26 ».
struct Meal: FamilyDocument {
    static let collection = "meals"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Meal]> { \.meals }

    var id: String
    var recipeId: String?
    var title: String
    var imageURL: String = ""
    var minutes: Int = 0
    var servings: Int = 4
    var note: String = ""

    init(id: String, recipeId: String? = nil, title: String, imageURL: String = "", minutes: Int = 0,
         servings: Int = 4, note: String = "") {
        self.id = id
        self.recipeId = recipeId
        self.title = title
        self.imageURL = imageURL
        self.minutes = minutes
        self.servings = servings
        self.note = note
    }

    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String else { return nil }
        self.id = id
        self.title = title
        recipeId = data["recipeId"] as? String
        imageURL = data["imageURL"] as? String ?? ""
        minutes = FS.int(data["minutes"]) ?? 0
        servings = FS.int(data["servings"]) ?? 4
        note = data["note"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "recipeId": FS.value(recipeId),
            "title": title,
            "imageURL": imageURL,
            "minutes": minutes,
            "servings": servings,
            "note": note,
        ]
    }

    static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var date: Date? {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - Tâches et idées

struct ChecklistEntry: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var done: Bool = false
}

struct TaskComment: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var authorName: String
    var at: Date = .now

    var data: [String: Any] {
        ["id": id, "text": text, "authorName": authorName, "at": Timestamp(date: at)]
    }
}

struct TaskItem: FamilyDocument {
    enum Kind: String, CaseIterable { case task, idea }
    enum Status: String, CaseIterable, Identifiable {
        case todo, doing, done
        var id: String { rawValue }
        var label: String {
            switch self {
            case .todo: return "À faire"
            case .doing: return "En cours"
            case .done: return "Fait"
            }
        }
    }

    static let collection = "tasks"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [TaskItem]> { \.tasks }

    var id: String = UUID().uuidString
    var title: String
    var notes: String = ""
    var kind: Kind = .task
    var status: Status = .todo
    var assigneeIds: [String] = []
    var dueDate: Date?
    var estimatedCost: Double?
    var actualCost: Double?
    var links: [String] = []
    var checklist: [ChecklistEntry] = []
    var comments: [TaskComment] = []
    var voterIds: [String] = []
    /// Identifiants de connexion (uid) des personnes qui suivent la tâche.
    var followerUids: [String] = []
    var createdByName: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var lastEditedByUid: String = ""
    var lastEditedByName: String = ""
    var lastChange: String = ""

    init(id: String = UUID().uuidString, title: String, notes: String = "", kind: Kind = .task, status: Status = .todo,
         assigneeIds: [String] = [], dueDate: Date? = nil, estimatedCost: Double? = nil, actualCost: Double? = nil,
         links: [String] = [], checklist: [ChecklistEntry] = [], comments: [TaskComment] = [], voterIds: [String] = [],
         followerUids: [String] = [], createdByName: String = "", createdAt: Date = .now, updatedAt: Date = .now,
         lastEditedByUid: String = "", lastEditedByName: String = "", lastChange: String = "") {
        self.id = id
        self.title = title
        self.notes = notes
        self.kind = kind
        self.status = status
        self.assigneeIds = assigneeIds
        self.dueDate = dueDate
        self.estimatedCost = estimatedCost
        self.actualCost = actualCost
        self.links = links
        self.checklist = checklist
        self.comments = comments
        self.voterIds = voterIds
        self.followerUids = followerUids
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEditedByUid = lastEditedByUid
        self.lastEditedByName = lastEditedByName
        self.lastChange = lastChange
    }

    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String else { return nil }
        self.id = id
        self.title = title
        notes = data["notes"] as? String ?? ""
        kind = Kind(rawValue: data["kind"] as? String ?? "") ?? .task
        status = Status(rawValue: data["status"] as? String ?? "") ?? .todo
        assigneeIds = FS.strings(data["assigneeIds"])
        dueDate = FS.date(data["dueDate"])
        estimatedCost = FS.double(data["estimatedCost"])
        actualCost = FS.double(data["actualCost"])
        links = FS.strings(data["links"])
        checklist = (data["checklist"] as? [[String: Any]] ?? []).map {
            ChecklistEntry(id: $0["id"] as? String ?? UUID().uuidString, text: $0["text"] as? String ?? "", done: $0["done"] as? Bool ?? false)
        }
        comments = (data["comments"] as? [[String: Any]] ?? []).map {
            TaskComment(id: $0["id"] as? String ?? UUID().uuidString, text: $0["text"] as? String ?? "",
                        authorName: $0["authorName"] as? String ?? "", at: FS.date($0["at"]) ?? .now)
        }
        .sorted { $0.at < $1.at }
        voterIds = FS.strings(data["voterIds"])
        followerUids = FS.strings(data["followerUids"])
        createdByName = data["createdByName"] as? String ?? ""
        createdAt = FS.date(data["createdAt"]) ?? .now
        updatedAt = FS.date(data["updatedAt"]) ?? .now
        lastEditedByUid = data["lastEditedByUid"] as? String ?? ""
        lastEditedByName = data["lastEditedByName"] as? String ?? ""
        lastChange = data["lastChange"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "title": title,
            "notes": notes,
            "kind": kind.rawValue,
            "status": status.rawValue,
            "assigneeIds": assigneeIds,
            "dueDate": FS.value(dueDate),
            "estimatedCost": FS.value(estimatedCost),
            "actualCost": FS.value(actualCost),
            "links": links,
            "checklist": checklist.map { ["id": $0.id, "text": $0.text, "done": $0.done] },
            "comments": comments.map(\.data),
            "voterIds": voterIds,
            "followerUids": followerUids,
            "createdByName": createdByName,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "lastEditedByUid": lastEditedByUid,
            "lastEditedByName": lastEditedByName,
            "lastChange": lastChange,
        ]
    }
}

// MARK: - Dépenses

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case courses, logement, energie, assurances, sante, enfants, transport, loisirs, abonnements, maison, autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .courses: return "Courses"
        case .logement: return "Logement"
        case .energie: return "Énergie"
        case .assurances: return "Assurances"
        case .sante: return "Santé"
        case .enfants: return "Enfants"
        case .transport: return "Transport"
        case .loisirs: return "Loisirs"
        case .abonnements: return "Abonnements"
        case .maison: return "Maison"
        case .autre: return "Autre"
        }
    }

    var icon: String {
        switch self {
        case .courses: return "basket"
        case .logement: return "house"
        case .energie: return "bolt"
        case .assurances: return "shield"
        case .sante: return "cross.case"
        case .enfants: return "figure.and.child.holdinghands"
        case .transport: return "car"
        case .loisirs: return "ticket"
        case .abonnements: return "repeat"
        case .maison: return "hammer"
        case .autre: return "ellipsis"
        }
    }
}

struct Expense: FamilyDocument {
    static let collection = "expenses"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Expense]> { \.expenses }

    var id: String = UUID().uuidString
    var vendor: String
    var amount: Double
    var category: ExpenseCategory = .autre
    var issueDate: Date = .now
    var dueDate: Date?
    var paidAt: Date?
    var paidByName: String?
    var note: String = ""
    var iban: String = ""
    var communication: String = ""
    var imagePath: String = ""
    var recurrence: Recurrence = .none
    var warrantyUntil: Date?
    var createdByName: String = ""

    var isPaid: Bool { paidAt != nil }

    init(id: String = UUID().uuidString, vendor: String, amount: Double, category: ExpenseCategory = .autre,
         issueDate: Date = .now, dueDate: Date? = nil, paidAt: Date? = nil, paidByName: String? = nil,
         note: String = "", iban: String = "", communication: String = "", imagePath: String = "",
         recurrence: Recurrence = .none, warrantyUntil: Date? = nil, createdByName: String = "") {
        self.id = id
        self.vendor = vendor
        self.amount = amount
        self.category = category
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.paidAt = paidAt
        self.paidByName = paidByName
        self.note = note
        self.iban = iban
        self.communication = communication
        self.imagePath = imagePath
        self.recurrence = recurrence
        self.warrantyUntil = warrantyUntil
        self.createdByName = createdByName
    }

    init?(id: String, data: [String: Any]) {
        guard let vendor = data["vendor"] as? String, let amount = FS.double(data["amount"]) else { return nil }
        self.id = id
        self.vendor = vendor
        self.amount = amount
        category = ExpenseCategory(rawValue: data["category"] as? String ?? "") ?? .autre
        issueDate = FS.date(data["issueDate"]) ?? .now
        dueDate = FS.date(data["dueDate"])
        paidAt = FS.date(data["paidAt"])
        paidByName = data["paidByName"] as? String
        note = data["note"] as? String ?? ""
        iban = data["iban"] as? String ?? ""
        communication = data["communication"] as? String ?? ""
        imagePath = data["imagePath"] as? String ?? ""
        recurrence = Recurrence(rawValue: data["recurrence"] as? String ?? "") ?? .none
        warrantyUntil = FS.date(data["warrantyUntil"])
        createdByName = data["createdByName"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "vendor": vendor,
            "amount": amount,
            "category": category.rawValue,
            "issueDate": Timestamp(date: issueDate),
            "dueDate": FS.value(dueDate),
            "paidAt": FS.value(paidAt),
            "paidByName": FS.value(paidByName),
            "note": note,
            "iban": iban,
            "communication": communication,
            "imagePath": imagePath,
            "recurrence": recurrence.rawValue,
            "warrantyUntil": FS.value(warrantyUntil),
            "createdByName": createdByName,
        ]
    }
}

// MARK: - Activités

struct Activity: FamilyDocument {
    static let collection = "activities"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Activity]> { \.activities }

    static let suggestedTags = ["Gratuit", "Pluie", "Extérieur", "Petits", "Grands", "1 h", "Journée", "Près de chez nous", "Voyage"]

    var id: String = UUID().uuidString
    var title: String
    var details: String = ""
    var link: String = ""
    var tags: [String] = []
    var voterIds: [String] = []
    var plannedDate: Date?
    var createdByName: String = ""
    var createdAt: Date = .now

    init(id: String = UUID().uuidString, title: String, details: String = "", link: String = "", tags: [String] = [],
         voterIds: [String] = [], plannedDate: Date? = nil, createdByName: String = "", createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.details = details
        self.link = link
        self.tags = tags
        self.voterIds = voterIds
        self.plannedDate = plannedDate
        self.createdByName = createdByName
        self.createdAt = createdAt
    }

    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String else { return nil }
        self.id = id
        self.title = title
        details = data["details"] as? String ?? ""
        link = data["link"] as? String ?? ""
        tags = FS.strings(data["tags"])
        voterIds = FS.strings(data["voterIds"])
        plannedDate = FS.date(data["plannedDate"])
        createdByName = data["createdByName"] as? String ?? ""
        createdAt = FS.date(data["createdAt"]) ?? .now
    }

    var firestoreData: [String: Any] {
        [
            "title": title,
            "details": details,
            "link": link,
            "tags": tags,
            "voterIds": voterIds,
            "plannedDate": FS.value(plannedDate),
            "createdByName": createdByName,
            "createdAt": Timestamp(date: createdAt),
        ]
    }
}

// MARK: - Fil d'activité

struct FeedEntry: FamilyDocument {
    static let collection = "feed"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [FeedEntry]> { \.feed }

    var id: String = UUID().uuidString
    var text: String
    var actorName: String
    var icon: String = "circle"
    var createdAt: Date = .now

    init(id: String = UUID().uuidString, text: String, actorName: String, icon: String = "circle", createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.actorName = actorName
        self.icon = icon
        self.createdAt = createdAt
    }

    init?(id: String, data: [String: Any]) {
        guard let text = data["text"] as? String else { return nil }
        self.id = id
        self.text = text
        actorName = data["actorName"] as? String ?? ""
        icon = data["icon"] as? String ?? "circle"
        createdAt = FS.date(data["createdAt"]) ?? .now
    }

    var firestoreData: [String: Any] {
        ["text": text, "actorName": actorName, "icon": icon, "createdAt": Timestamp(date: createdAt)]
    }
}

// MARK: - Carnet de santé

/// Un médecin ou un professionnel de santé de la famille.
struct Doctor: FamilyDocument {
    static let collection = "doctors"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [Doctor]> { \.doctors }

    static let specialties = [
        "Pédiatre", "Médecin généraliste", "Gastro-entérologue", "ORL", "Dermatologue", "Allergologue",
        "Pneumologue", "Ophtalmologue", "Dentiste", "Orthodontiste", "Kinésithérapeute", "Logopède",
        "Psychomotricien·ne", "Psychologue", "Cardiologue", "Neurologue", "Gynécologue", "Sage-femme",
        "ONE (consultation)", "Urgences", "Autre",
    ]

    var id: String = UUID().uuidString
    var name: String
    var specialty: String = "Pédiatre"
    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var notes: String = ""
    var personIds: [String] = []

    init(id: String = UUID().uuidString, name: String, specialty: String = "Pédiatre", phone: String = "", email: String = "",
         address: String = "", notes: String = "", personIds: [String] = []) {
        self.id = id
        self.name = name
        self.specialty = specialty
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
        self.personIds = personIds
    }

    init?(id: String, data: [String: Any]) {
        guard let name = data["name"] as? String else { return nil }
        self.id = id
        self.name = name
        specialty = data["specialty"] as? String ?? "Autre"
        phone = data["phone"] as? String ?? ""
        email = data["email"] as? String ?? ""
        address = data["address"] as? String ?? ""
        notes = data["notes"] as? String ?? ""
        personIds = FS.strings(data["personIds"])
    }

    var firestoreData: [String: Any] {
        ["name": name, "specialty": specialty, "phone": phone, "email": email, "address": address,
         "notes": notes, "personIds": personIds]
    }
}

/// Une visite chez un médecin : ce qui a été vu et dit.
struct MedicalVisit: FamilyDocument {
    static let collection = "visits"
    static var storePath: ReferenceWritableKeyPath<FamilyStore, [MedicalVisit]> { \.visits }

    var id: String = UUID().uuidString
    var personId: String
    var doctorId: String?
    var date: Date = .now
    var reason: String = ""
    var summary: String = ""
    var heightCm: Double?
    var weightKg: Double?
    var headCm: Double?
    var vaccines: [String] = []
    var treatment: String = ""
    var nextAppointment: Date?
    var createdByName: String = ""

    init(id: String = UUID().uuidString, personId: String, doctorId: String? = nil, date: Date = .now, reason: String = "",
         summary: String = "", heightCm: Double? = nil, weightKg: Double? = nil, headCm: Double? = nil,
         vaccines: [String] = [], treatment: String = "", nextAppointment: Date? = nil, createdByName: String = "") {
        self.id = id
        self.personId = personId
        self.doctorId = doctorId
        self.date = date
        self.reason = reason
        self.summary = summary
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.headCm = headCm
        self.vaccines = vaccines
        self.treatment = treatment
        self.nextAppointment = nextAppointment
        self.createdByName = createdByName
    }

    init?(id: String, data: [String: Any]) {
        guard let personId = data["personId"] as? String else { return nil }
        self.id = id
        self.personId = personId
        doctorId = data["doctorId"] as? String
        date = FS.date(data["date"]) ?? .now
        reason = data["reason"] as? String ?? ""
        summary = data["summary"] as? String ?? ""
        heightCm = FS.double(data["heightCm"])
        weightKg = FS.double(data["weightKg"])
        headCm = FS.double(data["headCm"])
        vaccines = FS.strings(data["vaccines"])
        treatment = data["treatment"] as? String ?? ""
        nextAppointment = FS.date(data["nextAppointment"])
        createdByName = data["createdByName"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "personId": personId,
            "doctorId": FS.value(doctorId),
            "date": Timestamp(date: date),
            "reason": reason,
            "summary": summary,
            "heightCm": FS.value(heightCm),
            "weightKg": FS.value(weightKg),
            "headCm": FS.value(headCm),
            "vaccines": vaccines,
            "treatment": treatment,
            "nextAppointment": FS.value(nextAppointment),
            "createdByName": createdByName,
        ]
    }
}

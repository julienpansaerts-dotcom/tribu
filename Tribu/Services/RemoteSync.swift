import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Synchronisation en temps réel d'une tribu avec Firestore.
///
/// Les écoutes Firestore remplissent le `FamilyStore` ; les modifications passent par les méthodes
/// de `FamilyRemote`. Le cache hors ligne de Firestore applique les modifications localement tout
/// de suite, puis les envoie au serveur dès que le réseau est disponible.
final class RemoteSync: FamilyRemote {
    let householdId: String
    let uid: String
    var authorName: String
    private weak var store: FamilyStore?
    private var listeners: [ListenerRegistration] = []
    private let db = Firestore.firestore()

    var onPeopleChange: (([Person]) -> Void)?

    init(householdId: String, uid: String, authorName: String, store: FamilyStore) {
        self.householdId = householdId
        self.uid = uid
        self.authorName = authorName
        self.store = store
    }

    private var household: DocumentReference { db.collection("households").document(householdId) }
    private var people: CollectionReference { household.collection("people") }
    private var shoppingItems: CollectionReference {
        household.collection("lists").document("courses").collection("items")
    }

    // MARK: - Écoutes

    func start() {
        stop()
        store?.remote = self

        listeners.append(household.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data() else { return }
            self.store?.householdName = data["name"] as? String ?? "La tribu"
            let budgets = data["budgets"] as? [String: Any] ?? [:]
            self.store?.budgets = budgets.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        })

        listeners.append(people.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let documents = snapshot?.documents else { return }
            let list = documents
                .compactMap { Self.person(id: $0.documentID, data: $0.data()) }
                .sorted { ($0.birthDate ?? .distantPast) < ($1.birthDate ?? .distantPast) }
            self.store?.people = list
            self.onPeopleChange?(list)
        })

        listeners.append(shoppingItems.order(by: "createdAt", descending: true).addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let documents = snapshot?.documents else { return }
            self.store?.shopping = documents.map { Self.shoppingItem(id: $0.documentID, data: $0.data()) }
        })

        listen(Reminder.self)
        listen(FamilyEvent.self)
        listen(Recipe.self) { $0.order(by: "createdAt", descending: true) }
        let since = Meal.key(for: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now)
        listen(Meal.self) { $0.whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: since) }
        listen(TaskItem.self)
        listen(Expense.self) { $0.order(by: "issueDate", descending: true) }
        listen(Activity.self)
        listen(FeedEntry.self) { $0.order(by: "createdAt", descending: true).limit(to: 40) }
        listen(Doctor.self)
        listen(MedicalVisit.self) { $0.order(by: "date", descending: true) }
    }

    /// Écoute une collection de la tribu et remplit la liste correspondante du magasin.
    private func listen<T: FamilyDocument>(_ type: T.Type, query: ((CollectionReference) -> Query)? = nil) {
        let collection = household.collection(T.collection)
        let q: Query = query?(collection) ?? collection
        listeners.append(q.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let store = self.store, let documents = snapshot?.documents else { return }
            store[keyPath: T.storePath] = documents.compactMap { T(id: $0.documentID, data: $0.data()) }
        })
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        if store?.remote === self { store?.remote = nil }
    }

    deinit { listeners.forEach { $0.remove() } }

    // MARK: - FamilyRemote

    func savePerson(_ person: Person) {
        var data: [String: Any] = [
            "firstName": person.firstName,
            "colorHex": Int(person.colorHex),
            "allergies": person.allergies,
            "notes": person.notes,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let birthDate = person.birthDate {
            data["birthDate"] = Timestamp(date: birthDate)
        } else {
            data["birthDate"] = FieldValue.delete()
        }
        if let bloodType = person.bloodType {
            data["bloodType"] = bloodType
        } else {
            data["bloodType"] = FieldValue.delete()
        }
        if let linked = person.linkedUid { data["linkedUid"] = linked }
        people.document(person.id).setData(data, merge: true)
    }

    func deletePerson(_ personId: String) {
        people.document(personId).delete()
    }

    func saveSize(_ size: SizeEntry, personId: String) {
        var entry: [String: Any] = [
            "label": size.label,
            "value": size.value,
            "updatedAt": Timestamp(date: size.updatedAt),
            "updatedBy": size.updatedBy,
        ]
        if let detail = size.detail, !detail.isEmpty { entry["detail"] = detail }
        if let previous = size.previousValue { entry["previousValue"] = previous }
        people.document(personId).updateData(["sizes.\(size.id)": entry])
    }

    func deleteSize(_ sizeId: String, personId: String) {
        people.document(personId).updateData(["sizes.\(sizeId)": FieldValue.delete()])
    }

    func saveGrowth(_ point: GrowthPoint, personId: String) {
        var entry: [String: Any] = ["date": Timestamp(date: point.date)]
        if let height = point.heightCm { entry["heightCm"] = height }
        if let weight = point.weightKg { entry["weightKg"] = weight }
        people.document(personId).updateData(["growth.\(point.id)": entry])
    }

    func addShopping(name: String, quantity: String?, origin: String?) {
        var data: [String: Any] = [
            "name": name,
            "checked": false,
            "addedBy": authorName,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let quantity, !quantity.isEmpty { data["quantity"] = quantity }
        if let origin, !origin.isEmpty { data["origin"] = origin }
        shoppingItems.addDocument(data: data)
    }

    func updateShoppingQuantity(_ item: ShoppingItem, quantity: String) {
        shoppingItems.document(item.id).updateData(["quantity": quantity])
    }

    func saveDocument(_ entry: IdentityDocument, personId: String) {
        var data: [String: Any] = ["kind": entry.kind, "number": entry.number]
        if let expires = entry.expiresAt {
            data["expiresAt"] = Timestamp(date: expires)
        } else {
            data["expiresAt"] = NSNull()
        }
        people.document(personId).updateData(["documents.\(entry.id)": data])
    }

    func deleteDocument(_ documentId: String, personId: String) {
        people.document(personId).updateData(["documents.\(documentId)": FieldValue.delete()])
    }

    func save(collection: String, id: String, data: [String: Any]) {
        household.collection(collection).document(id).setData(data, merge: true)
    }

    func update(collection: String, id: String, fields: [String: Any]) {
        household.collection(collection).document(id).updateData(fields)
    }

    func delete(collection: String, id: String) {
        household.collection(collection).document(id).delete()
    }

    func saveBudgets(_ budgets: [String: Double]) {
        household.updateData(["budgets": budgets])
    }

    func uploadImage(_ data: Data, name: String) async throws -> String {
        let path = "households/\(householdId)/\(name)"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata)
        return path
    }

    func imageURL(path: String) async -> URL? {
        try? await Storage.storage().reference(withPath: path).downloadURL()
    }

    func setShopping(_ item: ShoppingItem, checked: Bool) {
        var data: [String: Any] = ["checked": checked]
        if checked {
            data["checkedBy"] = authorName
        } else {
            data["checkedBy"] = FieldValue.delete()
        }
        shoppingItems.document(item.id).updateData(data)
    }

    func deleteShopping(_ itemIds: [String]) {
        let batch = db.batch()
        itemIds.forEach { batch.deleteDocument(shoppingItems.document($0)) }
        batch.commit()
    }

    // MARK: - Lecture des documents

    static func person(id: String, data: [String: Any]) -> Person? {
        guard let firstName = data["firstName"] as? String else { return nil }
        let sizesMap = data["sizes"] as? [String: [String: Any]] ?? [:]
        let sizes: [SizeEntry] = sizesMap.compactMap { key, value in
            guard let label = value["label"] as? String, let val = value["value"] as? String else { return nil }
            return SizeEntry(
                id: key,
                label: label,
                value: val,
                detail: value["detail"] as? String,
                previousValue: value["previousValue"] as? String,
                updatedAt: (value["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
                updatedBy: value["updatedBy"] as? String ?? ""
            )
        }
        .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }

        let growthMap = data["growth"] as? [String: [String: Any]] ?? [:]
        let growth: [GrowthPoint] = growthMap.compactMap { key, value in
            guard let date = (value["date"] as? Timestamp)?.dateValue() else { return nil }
            return GrowthPoint(
                id: key,
                date: date,
                heightCm: (value["heightCm"] as? NSNumber)?.doubleValue,
                weightKg: (value["weightKg"] as? NSNumber)?.doubleValue
            )
        }
        .sorted { $0.date < $1.date }

        let documentsMap = data["documents"] as? [String: [String: Any]] ?? [:]
        let documents: [IdentityDocument] = documentsMap.map { key, value in
            IdentityDocument(id: key, kind: value["kind"] as? String ?? "Document", number: value["number"] as? String ?? "",
                             expiresAt: (value["expiresAt"] as? Timestamp)?.dateValue())
        }
        .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }

        return Person(
            id: id,
            linkedUid: data["linkedUid"] as? String,
            firstName: firstName,
            colorHex: UInt32(truncatingIfNeeded: (data["colorHex"] as? NSNumber)?.intValue ?? 0x888888),
            birthDate: (data["birthDate"] as? Timestamp)?.dateValue(),
            bloodType: data["bloodType"] as? String,
            allergies: data["allergies"] as? [String] ?? [],
            notes: data["notes"] as? [String] ?? [],
            sizes: sizes,
            growth: growth,
            documents: documents
        )
    }

    static func shoppingItem(id: String, data: [String: Any]) -> ShoppingItem {
        let addedBy = data["addedBy"] as? String
        return ShoppingItem(
            id: id,
            name: data["name"] as? String ?? "",
            quantity: data["quantity"] as? String,
            origin: data["origin"] as? String ?? addedBy.map { "Ajouté par \($0)" },
            isChecked: data["checked"] as? Bool ?? false
        )
    }
}

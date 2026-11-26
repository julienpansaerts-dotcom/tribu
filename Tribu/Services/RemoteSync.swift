import FirebaseFirestore
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

    func addShopping(name: String, quantity: String?) {
        var data: [String: Any] = [
            "name": name,
            "checked": false,
            "addedBy": authorName,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let quantity, !quantity.isEmpty { data["quantity"] = quantity }
        shoppingItems.addDocument(data: data)
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
            growth: growth
        )
    }

    static func shoppingItem(id: String, data: [String: Any]) -> ShoppingItem {
        let addedBy = data["addedBy"] as? String
        return ShoppingItem(
            id: id,
            name: data["name"] as? String ?? "",
            quantity: data["quantity"] as? String,
            origin: addedBy.map { "Ajouté par \($0)" },
            isChecked: data["checked"] as? Bool ?? false
        )
    }
}

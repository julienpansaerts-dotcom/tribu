import Foundation

/// Résumé de la journée partagé entre l'app, les widgets et Siri.
///
/// L'app l'écrit dans le conteneur partagé (App Group) à chaque changement ; les widgets le lisent.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Hashable {
        var time: String
        var title: String
        var detail: String
        var kind: String
        var done: Bool
        var colorHex: UInt32
    }

    static let appGroup = "group.com.julienpansaerts.tribu"
    private static let fileName = "snapshot.json"
    private static let defaultsKey = "tribu.widgetSnapshot"

    var updatedAt: Date = .now
    var style: String = "couleurs"
    var familyName: String = "La tribu"
    var day: Date = .now
    var today: [Item] = []
    var shoppingCount: Int = 0
    var shoppingItems: [String] = []
    var tonight: String?

    static let placeholder = WidgetSnapshot(
        style: "couleurs",
        familyName: "La tribu",
        today: [
            Item(time: "09:00", title: "Acheter du pain", detail: "Rappel de Camille", kind: "reminder", done: false, colorHex: 0xE8553B),
            Item(time: "10:30", title: "Vaccin de Nina", detail: "Dr Lambert", kind: "event", done: false, colorHex: 0x4F86C6),
            Item(time: "19:00", title: "Risotto aux champignons", detail: "Au menu", kind: "meal", done: false, colorHex: 0x7FAF8B),
        ],
        shoppingCount: 9,
        shoppingItems: ["Champignons", "Oignons", "Parmesan", "Lait", "Bananes"],
        tonight: "Risotto aux champignons"
    )

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        if let url = Self.fileURL { try? data.write(to: url, options: .atomic) }
    }

    static func load() -> WidgetSnapshot? {
        let data = fileURL.flatMap { try? Data(contentsOf: $0) } ?? UserDefaults.standard.data(forKey: defaultsKey)
        guard let data, var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        // Un résumé d'un autre jour ne montre plus rien d'« aujourd'hui ».
        if !Calendar.current.isDateInToday(snapshot.day) {
            snapshot.today = []
            snapshot.tonight = nil
        }
        return snapshot
    }
}

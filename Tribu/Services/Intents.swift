import AppIntents
import FirebaseAuth
import FirebaseFirestore
import Foundation

/// « Dis Siri, ajoute un article aux courses dans Tribu. »
struct AddShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter aux courses"
    static var description = IntentDescription("Ajoute un ou plusieurs articles à la liste de courses de la tribu.")

    @Parameter(title: "Article", requestValueDialog: "Qu'est-ce qu'il faut ajouter ?")
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$item) aux courses")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Backend.configureIfPossible()
        guard Backend.isConfigured, Auth.auth().currentUser != nil,
              let householdId = UserDefaults.standard.string(forKey: "tribu.householdId") else {
            return .result(dialog: "Ouvre d'abord Tribu pour te connecter à ta tribu.")
        }
        let names = Self.split(item)
        guard !names.isEmpty else { return .result(dialog: "Je n'ai pas compris l'article.") }
        let author = UserDefaults.standard.string(forKey: "tribu.authorName") ?? ""
        let items = Firestore.firestore()
            .collection("households").document(householdId)
            .collection("lists").document("courses").collection("items")
        for name in names {
            _ = try await items.addDocument(data: [
                "name": name,
                "checked": false,
                "addedBy": author,
                "origin": "Ajouté avec Siri",
                "createdAt": FieldValue.serverTimestamp(),
            ])
        }
        let list = ListFormatter.localizedString(byJoining: names.map { $0.lowercased() })
        return .result(dialog: "C'est noté : \(list) sur la liste.")
    }

    /// « lait, œufs et beurre » → ["Lait", "Œufs", "Beurre"]
    static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: " et ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}

/// « Qu'est-ce qu'on mange ce soir dans Tribu ? »
struct TonightIntent: AppIntent {
    static var title: LocalizedStringResource = "Repas de ce soir"
    static var description = IntentDescription("Dit ce qui est prévu au menu ce soir.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Backend.configureIfPossible()
        if Backend.isConfigured, Auth.auth().currentUser != nil,
           let householdId = UserDefaults.standard.string(forKey: "tribu.householdId") {
            let doc = try? await Firestore.firestore()
                .collection("households").document(householdId)
                .collection("meals").document(Meal.key(for: .now)).getDocument()
            if let title = doc?.data()?["title"] as? String {
                return .result(dialog: "Ce soir, c'est \(title).")
            }
        } else if let tonight = WidgetSnapshot.load()?.tonight {
            return .result(dialog: "Ce soir, c'est \(tonight).")
        }
        return .result(dialog: "Rien n'est prévu au menu ce soir.")
    }
}

/// « Qu'est-ce qui est prévu aujourd'hui dans Tribu ? »
struct TodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Programme du jour"
    static var description = IntentDescription("Énumère les rappels, rendez-vous et repas du jour.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = (WidgetSnapshot.load()?.today ?? []).filter { !$0.done }
        guard !items.isEmpty else {
            return .result(dialog: "Rien de prévu aujourd'hui. Profitez-en !")
        }
        let sentences = items.prefix(6).map { item -> String in
            item.time.contains(":") ? "à \(item.time), \(item.title)" : "\(item.title)"
        }
        return .result(dialog: "Aujourd'hui : \(ListFormatter.localizedString(byJoining: Array(sentences))).")
    }
}

/// Phrases reconnues par Siri, sans configuration.
struct TribuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Ajoute un article aux courses dans \(.applicationName)",
                "Ajouter aux courses dans \(.applicationName)",
                "Ajoute à la liste de courses de \(.applicationName)",
            ],
            shortTitle: "Ajouter aux courses",
            systemImageName: "basket"
        )
        AppShortcut(
            intent: TonightIntent(),
            phrases: [
                "Qu'est-ce qu'on mange ce soir dans \(.applicationName)",
                "Repas du soir dans \(.applicationName)",
            ],
            shortTitle: "Ce soir",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: TodayIntent(),
            phrases: [
                "Qu'est-ce qui est prévu aujourd'hui dans \(.applicationName)",
                "Programme du jour dans \(.applicationName)",
            ],
            shortTitle: "Aujourd'hui",
            systemImageName: "calendar"
        )
    }
}

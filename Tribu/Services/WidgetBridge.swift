import Foundation
import SwiftUI
import WidgetKit

extension WidgetSnapshot {
    /// Résumé construit à partir des données de la tribu.
    init(store: FamilyStore, style: String) {
        self.init()
        self.style = style
        familyName = store.householdName.isEmpty ? "La tribu" : store.householdName
        day = .now
        today = store.today.map { item in
            let color: UInt32 = store.person(item.personId)?.colorHex ?? {
                switch item.kind {
                case .reminder: return 0xF2B84B
                case .event: return 0x4F86C6
                case .meal: return 0x7FAF8B
                }
            }()
            let kind: String
            switch item.kind {
            case .reminder: kind = "reminder"
            case .event: kind = "event"
            case .meal: kind = "meal"
            }
            return Item(time: item.time, title: item.title, detail: item.detail, kind: kind, done: item.isDone, colorHex: color)
        }
        shoppingCount = store.remainingShopping.count
        shoppingItems = Array(store.remainingShopping.prefix(8).map(\.name))
        tonight = store.tonight?.title
    }
}

/// Garde les widgets à jour quand les données de la tribu changent.
struct WidgetSync: ViewModifier {
    @Environment(FamilyStore.self) private var store
    @AppStorage("tribu.style") private var style: String = TribuStyle.couleurs.rawValue

    func body(content: Content) -> some View {
        let snapshot = WidgetSnapshot(store: store, style: style)
        content
            .onChange(of: snapshot.comparable) { _, _ in publish(snapshot) }
            .onAppear { publish(snapshot) }
    }

    private func publish(_ snapshot: WidgetSnapshot) {
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WidgetSnapshot {
    /// Ce qui compte pour décider de rafraîchir les widgets (sans la date de mise à jour).
    var comparable: String {
        [style, familyName, String(shoppingCount), shoppingItems.joined(separator: "|"), tonight ?? "",
         today.map { "\($0.time)\($0.title)\($0.done)" }.joined(separator: "|")].joined(separator: "#")
    }
}

extension View {
    func syncWidgets() -> some View { modifier(WidgetSync()) }
}

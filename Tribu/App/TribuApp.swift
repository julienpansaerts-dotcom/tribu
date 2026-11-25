import SwiftUI

@main
struct TribuApp: App {
    @State private var store = FamilyStore.sample()
    @AppStorage("tribu.style") private var styleRaw: String = TribuStyle.couleurs.rawValue

    private var theme: Theme { Theme.make(TribuStyle(rawValue: styleRaw) ?? .couleurs) }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.theme, theme)
                .tint(theme.accent)
                .animation(.smooth(duration: 0.45), value: styleRaw)
        }
    }
}

/// Les onglets principaux.
enum AppTab: String, Hashable {
    case home, cuisine, agenda, family, more
}

struct RootView: View {
    @Environment(\.theme) private var theme
    @State private var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "tribu.tab") ?? "") ?? .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Accueil", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Cuisine", systemImage: "basket", value: AppTab.cuisine) {
                ComingSoonView(
                    title: "Cuisine",
                    module: .courses,
                    lines: [
                        "Listes de courses partagées, en temps réel",
                        "Recettes importées depuis un simple lien",
                        "Menu de la semaine relié aux courses",
                    ]
                )
            }
            Tab("Agenda", systemImage: "calendar", value: AppTab.agenda) {
                ComingSoonView(
                    title: "Agenda",
                    module: .agenda,
                    lines: [
                        "Agenda partagé de la tribu",
                        "Copie automatique dans le calendrier iCloud",
                        "Congés scolaires de la Fédération Wallonie-Bruxelles",
                    ]
                )
            }
            Tab("Famille", systemImage: "person.2", value: AppTab.family) {
                FamilyListView()
            }
            Tab("Plus", systemImage: "square.grid.2x2", value: AppTab.more) {
                MoreView()
            }
        }
    }
}

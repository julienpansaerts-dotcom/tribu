import SwiftUI

@main
struct TribuApp: App {
    @State private var model: AppModel
    @AppStorage("tribu.style") private var styleRaw: String = TribuStyle.couleurs.rawValue

    init() {
        Backend.configureIfPossible()
        _model = State(initialValue: AppModel())
    }

    private var theme: Theme { Theme.make(TribuStyle(rawValue: styleRaw) ?? .couleurs) }

    var body: some Scene {
        WindowGroup {
            PhaseView()
                .environment(model)
                .environment(model.store)
                .environment(\.theme, theme)
                .tint(theme.accent)
                .animation(.smooth(duration: 0.45), value: styleRaw)
        }
    }
}

/// Affiche l'écran qui correspond à l'étape : connexion, choix de tribu ou app.
struct PhaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    /// Pour les captures d'écran : force un écran d'accueil en mode démo.
    private let forcedScreen = UserDefaults.standard.string(forKey: "tribu.onboarding") ?? ""

    var body: some View {
        Group {
            switch forcedScreen {
            case "welcome": WelcomeView()
            case "tribe": ChooseTribeView()
            case "create": CreateTribeView()
            case "join": JoinTribeView()
            case "person": ChoosePersonView()
            default:
                switch model.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .themedBackground()
                case .signedOut: WelcomeView()
                case .needsTribe: ChooseTribeView()
                case .choosePerson: ChoosePersonView()
                case .demo, .ready: RootView()
                }
            }
        }
        .animation(.smooth, value: model.phase)
        .alert("Oups", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
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
            Tab("Courses", systemImage: "basket", value: AppTab.cuisine) {
                ShoppingListView()
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

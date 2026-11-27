import SwiftUI

/// Onglet « Plus » : les autres modules et les réglages.
struct MoreView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Environment(FamilyStore.self) private var store
    @State private var confirmSignOut = false
    @State private var path: NavigationPath = {
        var path = NavigationPath()
        if let raw = UserDefaults.standard.string(forKey: "tribu.module"), let destination = MoreDestination(rawValue: raw) {
            path.append(destination)
        }
        return path
    }()

    private var t: Typography { theme.typography }

    enum MoreDestination: String, Hashable {
        case reminders, tasks, activities, expenses, feed
    }

    private struct ModuleEntry: Identifiable {
        let title: String
        let icon: String
        let module: Module
        let destination: MoreDestination
        var id: String { title }
    }

    private let modules: [ModuleEntry] = [
        ModuleEntry(title: "Rappels", icon: "bell", module: .rappels, destination: .reminders),
        ModuleEntry(title: "Tâches et idées", icon: "checklist", module: .taches, destination: .tasks),
        ModuleEntry(title: "Activités", icon: "figure.and.child.holdinghands", module: .activites, destination: .activities),
        ModuleEntry(title: "Dépenses", icon: "eurosign", module: .depenses, destination: .expenses),
    ]

    private func subtitle(_ destination: MoreDestination) -> String {
        switch destination {
        case .reminders:
            let count = store.reminders.filter { !$0.isDone && $0.assigneeIds.contains(store.currentUserId) }.count
            return count == 0 ? "Rien pour toi" : "\(count) pour toi"
        case .tasks:
            let count = store.tasks.filter { $0.kind == .task && $0.status != .done }.count
            return "\(count) en cours"
        case .activities:
            return "\(store.activities.filter { $0.plannedDate == nil }.count) idées"
        case .expenses:
            return store.unpaidBillsCount == 0 ? "Tout est payé" : "\(store.unpaidBillsCount) à payer"
        case .feed:
            return ""
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plus").font(t.display(44)).padding(.top, 12).padding(.bottom, 6)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(modules) { entry in
                            NavigationLink(value: entry.destination) {
                                VStack(alignment: .leading, spacing: 18) {
                                    Image(systemName: entry.icon).font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title).font(t.headline(16))
                                        Text(subtitle(entry.destination)).font(t.caption(12)).opacity(0.7)
                                    }
                                }
                                .foregroundStyle(theme.ink)
                                .padding(16)
                                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .background(theme.color(for: entry.module), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink(value: MoreDestination.feed) {
                        settingsRow(icon: "list.bullet.rectangle", title: "Fil d'activité", value: store.feed.first.map { "\($0.actorName) \($0.text)" } ?? "")
                    }
                    .buttonStyle(.plain)

                    Text("Réglages").font(t.title(22)).padding(.top, 18)
                    NavigationLink {
                        StylePickerView()
                    } label: {
                        settingsRow(icon: "paintpalette", title: "Style de l'app", value: theme.style.name)
                    }
                    .buttonStyle(.plain)
                    if model.isParent && model.phase == .ready {
                        NavigationLink {
                            BotsView()
                        } label: {
                            settingsRow(icon: "sparkles", title: "Bots et IA (Grok…)", value: "")
                        }
                        .buttonStyle(.plain)
                    }
                    if model.isParent {
                        NavigationLink {
                            InviteView()
                        } label: {
                            settingsRow(icon: "person.badge.plus", title: "Inviter quelqu'un", value: store.householdName)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.phase == .ready {
                        Button {
                            model.enterDemo()
                        } label: {
                            settingsRow(icon: "person.3", title: "Voir la famille d'exemple", value: "")
                        }
                        .buttonStyle(.plain)
                        Button {
                            confirmSignOut = true
                        } label: {
                            settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Se déconnecter", value: "")
                        }
                        .buttonStyle(.plain)
                    } else if model.phase == .demo {
                        Text("Famille d'exemple : rien n'est partagé, les modifications restent sur cet iPhone.")
                            .font(t.caption(13))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.top, 4)
                        if model.isTryingDemo {
                            Button {
                                model.exitDemo()
                            } label: {
                                settingsRow(icon: "arrow.uturn.backward", title: "Quitter la famille d'exemple", value: "")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .reminders: RemindersView()
                case .tasks: TasksView()
                case .activities: ActivitiesView()
                case .expenses: ExpensesView()
                case .feed: FeedView()
                }
            }
            .confirmationDialog("Se déconnecter de Tribu ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) { model.signOut() }
            }
        }
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24)
            Text(title).font(t.body(16))
            Spacer()
            Text(value).font(t.caption(13)).foregroundStyle(theme.secondaryText).lineLimit(1)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.secondaryText)
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }
}

/// Choix de l'ambiance visuelle. Le changement s'applique instantanément à toute l'app.
struct StylePickerView: View {
    @Environment(\.theme) private var theme
    @AppStorage("tribu.style") private var styleRaw: String = TribuStyle.couleurs.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Style de l'app").font(theme.typography.display(38)).padding(.top, 8)
                Text("Chacun choisit le sien : il ne change que sur ton iPhone.")
                    .font(theme.typography.body(15))
                    .foregroundStyle(theme.secondaryText)
                ForEach(TribuStyle.allCases) { style in
                    StyleCard(style: style, isSelected: style.rawValue == styleRaw) {
                        withAnimation(.smooth(duration: 0.45)) { styleRaw = style.rawValue }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: styleRaw)
    }
}

/// Aperçu d'une ambiance, dessiné avec ses propres couleurs et polices.
private struct StyleCard: View {
    let style: TribuStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let preview = Theme.make(style)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach([Module.courses, .rappels, .famille, .agenda, .repas], id: \.self) { module in
                        RoundedRectangle(cornerRadius: min(preview.cornerRadius, 8), style: .continuous)
                            .fill(preview.color(for: module))
                            .frame(height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: min(preview.cornerRadius, 8), style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.06))
                            )
                    }
                }
                Text(style.name)
                    .font(style == .frigo ? preview.typography.hand(30) : preview.typography.display(26))
                    .foregroundStyle(preview.text)
                Text(style.summary)
                    .font(preview.typography.body(14))
                    .foregroundStyle(preview.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(preview.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? preview.text : preview.separator, lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(preview.text, preview.background)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 1 : 0.98)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Code d'invitation à envoyer à un membre de la famille.
struct InviteView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var code: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inviter quelqu'un").font(theme.typography.display(38)).padding(.top, 8)
                Text("Envoie ce code à ta compagne, à un grand-parent… Il est valable 7 jours. Dans Tribu, il ou elle choisit « Rejoindre une tribu » et le tape.")
                    .font(theme.typography.body(16))
                    .foregroundStyle(theme.secondaryText)
                if let code {
                    HStack(spacing: 8) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(theme.typography.number(34))
                                .frame(maxWidth: .infinity)
                                .frame(height: 68)
                                .background(theme.color(for: .rappels), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(theme.ink)
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    ShareLink(item: "Rejoins notre tribu dans l'app Tribu avec le code \(code) (valable 7 jours).") {
                        Label("Envoyer le code", systemImage: "square.and.arrow.up")
                            .font(theme.typography.headline(17))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(theme.background)
                    }
                    Button("Créer un autre code") { Task { await generate() } }
                        .font(theme.typography.body(15))
                        .foregroundStyle(theme.secondaryText)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 68)
                }
            }
            .padding(.horizontal, 20)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { if code == nil { await generate() } }
    }

    private func generate() async {
        guard !loading else { return }
        loading = true
        let newCode = await model.createInvite()
        withAnimation(.spring) { code = newCode }
        loading = false
    }
}

import SwiftUI

/// Connexion d'assistants IA (Grok, Claude, ChatGPT…) à Tribu via le serveur MCP.
struct BotsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var keys: [AppModel.BotKey] = []
    @State private var creating = false
    @State private var revoking: AppModel.BotKey?

    private var t: Typography { theme.typography }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bots et IA").font(t.display(38)).padding(.top, 8)
                Text("Connecte Grok (ou Claude, ChatGPT…) à Tribu : tu pourras lui demander tes tâches, le menu, le programme du jour, ou lui dire d'ajouter des courses et de créer des rappels.")
                    .font(t.body(15))
                    .foregroundStyle(theme.secondaryText)

                if model.phase == .demo {
                    EmptyState(text: "Disponible une fois connecté à ta vraie tribu.")
                } else {
                    Button {
                        creating = true
                    } label: {
                        Label("Connecter un bot", systemImage: "plus")
                            .font(t.headline(16))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(theme.background)
                    }
                    .buttonStyle(.plain)

                    ForEach(keys) { key in
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .frame(width: 40, height: 40)
                                .background(theme.color(for: .taches), in: Circle())
                                .foregroundStyle(theme.ink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.name).font(t.headline(16))
                                Text(detail(key)).font(t.caption(12)).foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            Button("Révoquer", role: .destructive) { revoking = key }
                                .font(t.body(14))
                        }
                        .padding(14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sécurité").font(t.title(20))
                        Text("Chaque bot a sa propre clé, intégrée à son adresse : garde-la secrète comme un mot de passe. Le carnet de santé et les papiers ne sont jamais accessibles aux bots. Tout ce qu'un bot modifie apparaît dans le fil d'activité.")
                            .font(t.body(14))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { keys = await model.botKeys() }
        .sheet(isPresented: $creating, onDismiss: { Task { keys = await model.botKeys() } }) { NewBotSheet() }
        .confirmationDialog("Révoquer « \(revoking?.name ?? "") » ?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button("Révoquer", role: .destructive) {
                guard let key = revoking else { return }
                Task {
                    await model.revokeBotKey(key.id)
                    keys = await model.botKeys()
                }
            }
        } message: {
            Text("Le bot n'aura plus accès à Tribu. Il faudra créer une nouvelle clé pour le reconnecter.")
        }
    }

    private func detail(_ key: AppModel.BotKey) -> String {
        var parts = [key.canWrite ? "Lecture et modification" : "Lecture seule"]
        if key.canFamily { parts.append("tailles") }
        if let last = key.lastUsedAt {
            parts.append("utilisé " + last.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_BE"))))
        } else {
            parts.append("jamais utilisé")
        }
        return parts.joined(separator: " · ")
    }
}

/// Création d'une clé : nom, droits, puis adresse à coller dans Grok.
private struct NewBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var name = "Grok"
    @State private var canWrite = true
    @State private var canFamily = false
    @State private var url: String?
    @State private var creating = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let url {
                    Section {
                        Text(url)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = url
                            copied = true
                        } label: {
                            Label(copied ? "Copiée !" : "Copier l'adresse", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .sensoryFeedback(.success, trigger: copied) { _, new in new }
                        ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up") }
                    } header: {
                        Text("Adresse du connecteur")
                    } footer: {
                        Text("Elle ne sera plus affichée : copie-la maintenant.")
                    }
                    Section("Dans Grok") {
                        Label("Ouvre grok.com/connectors (ou Réglages → Connecteurs dans l'app Grok)", systemImage: "1.circle")
                        Label("Nouveau connecteur → Personnalisé", systemImage: "2.circle")
                        Label("Nom : Tribu, puis colle l'adresse", systemImage: "3.circle")
                        Label("Demande par exemple : « Qu'est-ce que j'ai comme tâches ? »", systemImage: "4.circle")
                    }
                } else {
                    Section {
                        TextField("Nom du bot", text: $name)
                    } footer: {
                        Text("Le nom apparaît dans le fil d'activité : « Grok a ajouté du lait aux courses ».")
                    }
                    Section {
                        Toggle("Peut modifier", isOn: $canWrite)
                        Toggle("Accès aux tailles et pointures", isOn: $canFamily)
                    } footer: {
                        Text("Sans « Peut modifier », le bot peut seulement lire : programme, courses, menu, tâches, rappels. Il agit en ton nom : « moi » = toi.")
                    }
                }
            }
            .navigationTitle(url == nil ? "Connecter un bot" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(url == nil ? "Annuler" : "Terminé") { dismiss() }
                }
                if url == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if creating {
                            ProgressView()
                        } else {
                            Button("Créer") {
                                creating = true
                                Task {
                                    let result = await model.createBotKey(name: name.trimmingCharacters(in: .whitespaces), canWrite: canWrite, canFamily: canFamily)
                                    withAnimation { url = result }
                                    creating = false
                                }
                            }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
    }
}

import LocalAuthentication
import SwiftUI

/// Papiers d'identité d'une personne, protégés par Face ID.
struct DocumentsSection: View {
    let person: Person
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var unlocked = UserDefaults.standard.bool(forKey: "tribu.demo")
    @State private var editing: IdentityDocument?
    @State private var adding = false

    private var t: Typography { theme.typography }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Papiers").font(t.title(22))
                Spacer()
                if unlocked {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Ajouter un papier")
                }
            }
            if !unlocked {
                Button(action: unlock) {
                    Label("Déverrouiller avec Face ID", systemImage: "faceid")
                        .font(t.headline(15))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                if person.documents.isEmpty {
                    Text("Carte d'identité, Kids-ID, passeport… Tribu te prévient 60, 30 et 7 jours avant l'expiration.")
                        .font(t.body(14))
                        .foregroundStyle(theme.secondaryText)
                }
                ForEach(person.documents) { document in
                    Button { editing = document } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.kind).font(t.medium(15))
                                if !document.number.isEmpty {
                                    Text(document.number).font(t.caption(12).monospaced()).foregroundStyle(theme.secondaryText)
                                }
                            }
                            Spacer()
                            expiryBadge(document)
                        }
                        .padding(12)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $adding) { DocumentEditor(person: person, existing: nil) }
        .sheet(item: $editing) { DocumentEditor(person: person, existing: $0) }
    }

    @ViewBuilder private func expiryBadge(_ document: IdentityDocument) -> some View {
        if let days = document.daysLeft, let date = document.expiresAt {
            let urgent = days <= 60
            Text(days < 0 ? "Expiré" : (urgent ? "Expire dans \(days) j" : "Jusqu'au \(date.formatted(.dateTime.day().month(.abbreviated).year()))"))
                .font(t.caption(12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(urgent ? theme.color(for: .rappels) : Color.clear, in: Capsule())
                .foregroundStyle(urgent ? theme.ink : theme.secondaryText)
        }
    }

    private func unlock() {
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        context.evaluatePolicy(policy, localizedReason: "Afficher les papiers de \(person.firstName)") { success, _ in
            DispatchQueue.main.async {
                withAnimation(.smooth) { unlocked = success }
            }
        }
    }
}

struct DocumentEditor: View {
    let person: Person
    let existing: IdentityDocument?
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var kind = IdentityDocument.kinds[0]
    @State private var number = ""
    @State private var hasExpiry = true
    @State private var expiry = Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(IdentityDocument.kinds, id: \.self) { Text($0).tag($0) }
                }
                TextField("Numéro (facultatif)", text: $number)
                Toggle("Date d'expiration", isOn: $hasExpiry.animation())
                if hasExpiry {
                    DatePicker("Expire le", selection: $expiry, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "fr_BE"))
                }
                if let existing {
                    Button("Supprimer", role: .destructive) {
                        store.deleteDocument(existing.id, personId: person.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(person.firstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.saveDocument(IdentityDocument(id: existing?.id ?? UUID().uuidString, kind: kind, number: number,
                                                            expiresAt: hasExpiry ? expiry : nil), personId: person.id)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard let existing else { return }
                kind = existing.kind
                number = existing.number
                hasExpiry = existing.expiresAt != nil
                if let date = existing.expiresAt { expiry = date }
            }
        }
        .presentationDetents([.medium])
    }
}

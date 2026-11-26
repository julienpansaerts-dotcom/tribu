import AuthenticationServices
import SwiftUI

/// Premier écran : se connecter avec Apple.
struct WelcomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            FamilyLineup()
                .frame(height: 120)
                .staggeredAppear(0)
            Text("Tribu")
                .font(theme.typography.display(72))
                .tracking(-1.5)
                .staggeredAppear(1)
            Text("Les courses, l'agenda, les tailles de chacun et tout ce qu'il faut savoir — au même endroit, pour toute la famille.")
                .font(theme.typography.body(18))
                .foregroundStyle(theme.secondaryText)
                .staggeredAppear(2)
            Spacer()
            SignInWithAppleButton(.continue) { request in
                model.prepare(request)
            } onCompletion: { result in
                model.complete(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(model.isBusy)
            .overlay { if model.isBusy { ProgressView() } }
            Button("Découvrir avec une famille d'exemple") { model.enterDemo() }
                .font(theme.typography.headline(15))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, minHeight: 44)
            Text("Tes données restent privées, partagées uniquement avec ta tribu.")
                .font(theme.typography.caption(13))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .themedBackground()
    }
}

/// La famille alignée, comme sur l'icône de l'app.
struct FamilyLineup: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            figure(color: 0xF2643F, head: 34, body: CGSize(width: 74, height: 86))
            figure(color: 0x1D1B18, head: 32, body: CGSize(width: 70, height: 78))
            figure(color: 0x4F86C6, head: 24, body: CGSize(width: 52, height: 48))
            figure(color: 0xF2B84B, head: 20, body: CGSize(width: 44, height: 34))
        }
        .accessibilityHidden(true)
    }

    private func figure(color: UInt32, head: CGFloat, body: CGSize) -> some View {
        VStack(spacing: 5) {
            Circle().fill(Color(hex: color)).frame(width: head * 2, height: head * 2)
            UnevenRoundedRectangle(topLeadingRadius: body.width / 2, topTrailingRadius: body.width / 2)
                .fill(Color(hex: color))
                .frame(width: body.width, height: body.height)
        }
    }
}

/// Après la connexion : créer une tribu ou en rejoindre une.
struct ChooseTribeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var showCreate = false
    @State private var showJoin = false

    private var greeting: String {
        let name = model.suggestedFirstName
        return name.isEmpty ? "Bienvenue." : "Bienvenue, " + name + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(greeting)
                .font(theme.typography.display(40))
                .padding(.top, 40)
            Text("Tu es le premier de la famille, ou quelqu'un t'a envoyé un code ?")
                .font(theme.typography.body(17))
                .foregroundStyle(theme.secondaryText)
                .padding(.bottom, 10)

            choice(number: "01", title: "Créer une tribu", subtitle: "Tu ajoutes la famille, puis tu invites les autres.", module: .courses) {
                showCreate = true
            }
            choice(number: "02", title: "Rejoindre une tribu", subtitle: "Avec le code à 6 caractères reçu d'un membre.", module: .agenda) {
                showJoin = true
            }
            Spacer()
            Button("Découvrir avec une famille d'exemple") { model.enterDemo() }
                .font(theme.typography.headline(15))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, minHeight: 44)
            Button("Se déconnecter") { model.signOut() }
                .font(theme.typography.body(15))
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .themedBackground()
        .sheet(isPresented: $showCreate) { CreateTribeView() }
        .sheet(isPresented: $showJoin) { JoinTribeView() }
    }

    private func choice(number: String, title: String, subtitle: String, module: Module, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Text(number).font(theme.typography.headline(14)).opacity(0.7)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(theme.typography.title(24))
                    Text(subtitle).font(theme.typography.body(15)).opacity(0.8)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.title3.weight(.semibold))
            }
            .foregroundStyle(theme.ink)
            .padding(20)
            .background(theme.color(for: module), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Création d'une tribu : son nom, toi, et les autres membres de la famille.
struct CreateTribeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var name = "La tribu"
    @State private var me = AppModel.PersonDraft(colorHex: MemberColors.all[1])
    @State private var others: [AppModel.PersonDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom de la tribu") {
                    TextField("La tribu", text: $name)
                }
                Section("Toi") {
                    TextField("Ton prénom", text: $me.firstName)
                        .textContentType(.givenName)
                    ColorRow(selection: $me.colorHex)
                }
                Section {
                    ForEach($others) { $draft in
                        DraftRow(draft: $draft)
                    }
                    .onDelete { others.remove(atOffsets: $0) }
                    Button {
                        let used = [me.colorHex] + others.map(\.colorHex)
                        withAnimation { others.append(AppModel.PersonDraft(colorHex: MemberColors.next(after: used))) }
                    } label: {
                        Label("Ajouter quelqu'un", systemImage: "plus")
                    }
                } header: {
                    Text("La famille")
                } footer: {
                    Text("Conjoint, enfants… Les enfants n'ont pas besoin de compte. Les adultes pourront rejoindre la tribu avec un code d'invitation.")
                }
                Section("Pays") {
                    LabeledContent("Belgique", value: "Congés FWB")
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Nouvelle tribu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        model.createTribe(name: name, me: me, others: others)
                        dismiss()
                    }
                    .disabled(me.firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if me.firstName.isEmpty { me.firstName = model.suggestedFirstName }
                if others.isEmpty { others = [AppModel.PersonDraft(colorHex: MemberColors.all[0])] }
            }
        }
    }
}

private struct DraftRow: View {
    @Binding var draft: AppModel.PersonDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(Color(hex: draft.colorHex)).frame(width: 14, height: 14)
                TextField("Prénom", text: $draft.firstName)
            }
            Toggle("Date de naissance", isOn: Binding(
                get: { draft.birthDate != nil },
                set: { draft.birthDate = $0 ? Calendar.current.date(byAdding: .year, value: -5, to: .now) : nil }
            ))
            if let birthDate = draft.birthDate {
                DatePicker("Née / né le", selection: Binding(get: { birthDate }, set: { draft.birthDate = $0 }), in: ...Date.now, displayedComponents: .date)
            }
            ColorRow(selection: $draft.colorHex)
        }
        .padding(.vertical, 4)
    }
}

/// Choix d'une couleur de membre.
struct ColorRow: View {
    @Binding var selection: UInt32

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MemberColors.all, id: \.self) { hex in
                    Button {
                        selection = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: selection == hex ? 2.5 : 0).padding(-4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Couleur")
                    .accessibilityAddTraits(selection == hex ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Rejoindre une tribu avec un code d'invitation.
struct JoinTribeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var focused: Bool

    private var cleanCode: String { String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Le code reçu")
                    .font(theme.typography.display(36))
                Text("Demande à un membre de la tribu : Plus → Inviter quelqu'un.")
                    .font(theme.typography.body(16))
                    .foregroundStyle(theme.secondaryText)
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            let chars = Array(cleanCode)
                            Text(index < chars.count ? String(chars[index]) : "")
                                .font(theme.typography.number(30))
                                .frame(maxWidth: .infinity)
                                .frame(height: 62)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(index == chars.count && focused ? theme.accent : .clear, lineWidth: 2)
                                )
                        }
                    }
                    TextField("", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .foregroundStyle(.clear)
                        .tint(.clear)
                        .frame(height: 62)
                        .accessibilityLabel("Code d'invitation")
                }
                .onTapGesture { focused = true }

                Button {
                    model.joinTribe(code: cleanCode)
                    dismiss()
                } label: {
                    Text("Rejoindre")
                        .font(theme.typography.headline(17))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(theme.background)
                }
                .buttonStyle(.plain)
                .disabled(cleanCode.count < 6)
                .opacity(cleanCode.count < 6 ? 0.4 : 1)
                Spacer()
            }
            .padding(20)
            .themedBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .onAppear { focused = true }
        }
    }
}

/// Après avoir rejoint : « Qui es-tu dans la famille ? »
struct ChoosePersonView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Environment(FamilyStore.self) private var store
    @State private var newName = ""
    @State private var newColor = MemberColors.all[4]

    private var candidates: [Person] { store.people.filter { $0.linkedUid == nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Qui es-tu dans \(store.householdName.isEmpty ? "la tribu" : store.householdName) ?")
                    .font(theme.typography.display(36))
                    .padding(.top, 40)
                ForEach(candidates) { person in
                    Button {
                        model.choosePerson(person, newFirstName: "", colorHex: person.colorHex)
                    } label: {
                        HStack(spacing: 14) {
                            Avatar(person: person, size: 48)
                            Text(person.firstName).font(theme.typography.title(22))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Je ne suis pas dans la liste").font(theme.typography.headline(16))
                    TextField("Ton prénom", text: $newName)
                        .font(theme.typography.body(17))
                        .padding(12)
                        .background(theme.background, in: RoundedRectangle(cornerRadius: 10))
                    ColorRow(selection: $newColor)
                    Button("Continuer") {
                        model.choosePerson(nil, newFirstName: newName, colorHex: newColor)
                    }
                    .font(theme.typography.headline(16))
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
            }
            .padding(.horizontal, 20)
        }
        .themedBackground()
        .onAppear { newName = model.suggestedFirstName }
    }
}

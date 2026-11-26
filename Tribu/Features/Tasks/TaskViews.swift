import SwiftUI

/// Tâches et idées : liste par statut, tableau d'idées avec votes.
struct TasksView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var kind: TaskItem.Kind = .task
    @State private var creating = false
    @State private var showDone = false

    private var t: Typography { theme.typography }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: kind == .task ? "Tâches" : "Idées", module: .taches) { creating = true }
                Picker("Type", selection: $kind) {
                    Text("Tâches").tag(TaskItem.Kind.task)
                    Text("Idées").tag(TaskItem.Kind.idea)
                }
                .pickerStyle(.segmented)

                if kind == .task {
                    ForEach([TaskItem.Status.doing, .todo], id: \.self) { status in
                        let list = tasks(status)
                        if !list.isEmpty {
                            Text(status.label).font(t.title(20)).padding(.top, 4)
                            ForEach(list) { task in
                                NavigationLink(value: task.id) { TaskRow(task: task) }.buttonStyle(.plain)
                            }
                        }
                    }
                    let done = tasks(.done)
                    if !done.isEmpty {
                        Button {
                            withAnimation { showDone.toggle() }
                        } label: {
                            Label("\(done.count) terminée\(done.count > 1 ? "s" : "")", systemImage: showDone ? "chevron.down" : "chevron.right")
                                .font(t.headline(15))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        if showDone {
                            ForEach(done) { task in
                                NavigationLink(value: task.id) { TaskRow(task: task) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if store.tasks.filter({ $0.kind == .task }).isEmpty {
                        EmptyState(text: "Aucune tâche. Ajoute ce qu'il y a à faire à la maison : chacun peut commenter, ajouter des liens et des coûts.")
                    }
                } else {
                    let ideas = store.tasks.filter { $0.kind == .idea }.sorted { $0.voterIds.count > $1.voterIds.count }
                    if ideas.isEmpty {
                        EmptyState(text: "Note ici les idées à discuter : projets, achats, voyages… et votez pour vos préférées.")
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(ideas) { idea in
                            NavigationLink(value: idea.id) { IdeaCard(task: idea) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { TaskDetailView(taskId: $0) }
        .sheet(isPresented: $creating) { NewTaskSheet(kind: kind) }
    }

    private func tasks(_ status: TaskItem.Status) -> [TaskItem] {
        store.tasks.filter { $0.kind == .task && $0.status == status }
            .sorted { ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt) }
    }
}

struct TaskRow: View {
    let task: TaskItem
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : (task.status == .doing ? "circle.lefthalf.filled" : "circle"))
                .font(.title3)
                .foregroundStyle(task.status == .done ? theme.accent : theme.secondaryText)
            VStack(alignment: .leading, spacing: 4) {
                StrikeText(text: task.title, isStruck: task.status == .done, font: theme.typography.medium(16), color: theme.text)
                HStack(spacing: 10) {
                    if !task.assigneeIds.isEmpty { Label(store.names(task.assigneeIds), systemImage: "person") }
                    if let due = task.dueDate {
                        Label(due.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE"))), systemImage: "calendar")
                            .foregroundStyle(due < .now && task.status != .done ? Color(hex: 0xD9480F) : theme.secondaryText)
                    }
                    if !task.checklist.isEmpty {
                        Label("\(task.checklist.filter(\.done).count)/\(task.checklist.count)", systemImage: "checklist")
                    }
                    if !task.comments.isEmpty { Label("\(task.comments.count)", systemImage: "bubble.left") }
                    if let cost = task.actualCost ?? task.estimatedCost { Text(Decimal(cost).euros) }
                }
                .font(theme.typography.caption(12))
                .foregroundStyle(theme.secondaryText)
                .labelStyle(CompactLabelStyle())
            }
            Spacer()
            if task.followerUids.contains(store.currentUid) {
                Image(systemName: "bell.fill").font(.caption).foregroundStyle(theme.accent).accessibilityLabel("Suivie")
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

struct IdeaCard: View {
    let task: TaskItem
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(theme.typography.headline(16)).multilineTextAlignment(.leading)
            if !task.notes.isEmpty {
                Text(task.notes).font(theme.typography.body(13)).lineLimit(3).opacity(0.8)
            }
            Spacer(minLength: 0)
            HStack {
                Label("\(task.voterIds.count)", systemImage: "hand.thumbsup.fill")
                Spacer()
                if let cost = task.estimatedCost { Text("≈ " + Decimal(cost).euros) }
            }
            .font(theme.typography.caption(12))
        }
        .foregroundStyle(theme.ink)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(theme.color(for: .activites), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .rotationEffect(.degrees(theme.style == .frigo ? Double(abs(task.id.hashValue) % 5) - 2 : 0))
    }
}

/// Ajout rapide d'une tâche ou d'une idée.
struct NewTaskSheet: View {
    let kind: TaskItem.Kind
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var title = ""
    @State private var notes = ""
    @State private var follow = true

    var body: some View {
        NavigationStack {
            Form {
                TextField(kind == .task ? "Que faut-il faire ?" : "Quelle idée ?", text: $title)
                TextField("Détails (facultatif)", text: $notes, axis: .vertical)
                Toggle("Suivre (être notifié des modifications)", isOn: $follow)
            }
            .navigationTitle(kind == .task ? "Nouvelle tâche" : "Nouvelle idée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let task = TaskItem(
                            title: title.trimmingCharacters(in: .whitespaces), notes: notes, kind: kind,
                            followerUids: follow && !store.currentUid.isEmpty ? [store.currentUid] : [],
                            createdByName: store.authorName, lastEditedByUid: store.currentUid,
                            lastEditedByName: store.authorName, lastChange: "a créé la tâche"
                        )
                        store.save(task)
                        store.post("a ajouté \(kind == .task ? "la tâche" : "l'idée") « \(task.title) »", icon: kind == .task ? "checklist" : "lightbulb")
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Fiche d'une tâche : tout est modifiable sur place, chaque modification est signée.
struct TaskDetailView: View {
    let taskId: String
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var newComment = ""
    @State private var newLink = ""
    @State private var newCheck = ""
    @State private var editingNotes = false
    @State private var notesDraft = ""
    @State private var confirmDelete = false

    private var t: Typography { theme.typography }

    var body: some View {
        if let task = store.tasks.first(where: { $0.id == taskId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(task)
                    if task.kind == .task { statusPicker(task) }
                    fields(task)
                    notesSection(task)
                    checklist(task)
                    links(task)
                    comments(task)
                    Button("Supprimer", role: .destructive) { confirmDelete = true }
                        .font(t.body(15))
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { followButton(task) }
            }
            .confirmationDialog("Supprimer « \(task.title) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    store.delete(task)
                    dismiss()
                }
            }
        }
    }

    /// Enregistre une modification signée (déclenche les notifications des personnes qui suivent).
    private func commit(_ task: TaskItem, change: String, notify: Bool = true, _ edit: (inout TaskItem) -> Void) {
        var updated = task
        edit(&updated)
        if notify {
            updated.updatedAt = .now
            updated.lastEditedByUid = store.currentUid
            updated.lastEditedByName = store.authorName
            updated.lastChange = change
        }
        store.save(updated)
    }

    private func header(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.kind == .task ? "TÂCHE" : "IDÉE").font(t.headline(12)).tracking(1).foregroundStyle(theme.secondaryText)
            Text(task.title).font(t.display(32))
            Text("Créée par \(task.createdByName)\(task.lastEditedByName.isEmpty ? "" : " · modifiée par \(task.lastEditedByName) \(task.updatedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_BE"))))")")
                .font(t.caption(12))
                .foregroundStyle(theme.secondaryText)
            if task.kind == .idea {
                let voted = task.voterIds.contains(store.currentUserId)
                Button {
                    commit(task, change: voted ? "a retiré son vote" : "a voté pour l'idée", notify: false) {
                        if voted { $0.voterIds.removeAll { $0 == store.currentUserId } } else { $0.voterIds.append(store.currentUserId) }
                    }
                } label: {
                    Label("\(task.voterIds.count) · \(voted ? "J'aime" : "Voter")", systemImage: voted ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(t.headline(15))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(voted ? theme.text : theme.surface, in: Capsule())
                        .foregroundStyle(voted ? theme.background : theme.text)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: voted)
                Button("Transformer en tâche") {
                    commit(task, change: "a transformé l'idée en tâche") { $0.kind = .task }
                }
                .font(t.body(14))
            }
        }
    }

    private func followButton(_ task: TaskItem) -> some View {
        let following = task.followerUids.contains(store.currentUid)
        return Button {
            commit(task, change: "", notify: false) {
                if following { $0.followerUids.removeAll { $0 == store.currentUid } } else { $0.followerUids.append(store.currentUid) }
            }
        } label: {
            Label(following ? "Suivie" : "Suivre", systemImage: following ? "bell.fill" : "bell")
        }
        .disabled(store.currentUid.isEmpty)
        .sensoryFeedback(.selection, trigger: following)
    }

    private func statusPicker(_ task: TaskItem) -> some View {
        Picker("Statut", selection: Binding(
            get: { task.status },
            set: { status in commit(task, change: "a passé la tâche à « \(status.label.lowercased()) »") { $0.status = status } }
        )) {
            ForEach(TaskItem.Status.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func fields(_ task: TaskItem) -> some View {
        VStack(spacing: 0) {
            row("Qui", icon: "person") {
                Menu {
                    ForEach(store.people) { person in
                        let on = task.assigneeIds.contains(person.id)
                        Button {
                            commit(task, change: on ? "a retiré \(person.firstName)" : "a confié la tâche à \(person.firstName)") {
                                if on { $0.assigneeIds.removeAll { $0 == person.id } } else { $0.assigneeIds.append(person.id) }
                            }
                        } label: {
                            Label(person.firstName, systemImage: on ? "checkmark" : "")
                        }
                    }
                } label: {
                    Text(task.assigneeIds.isEmpty ? "Personne" : store.names(task.assigneeIds))
                }
            }
            row("Échéance", icon: "calendar") {
                if let due = task.dueDate {
                    DatePicker("", selection: Binding(get: { due }, set: { d in commit(task, change: "a changé l'échéance") { $0.dueDate = d } }),
                               displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "fr_BE"))
                    Button { commit(task, change: "a retiré l'échéance") { $0.dueDate = nil } } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(theme.secondaryText)
                } else {
                    Button("Ajouter") {
                        commit(task, change: "a fixé une échéance") { $0.dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) }
                    }
                }
            }
            row("Coût estimé", icon: "eurosign") {
                CostField(value: task.estimatedCost) { v in commit(task, change: "a estimé le coût") { $0.estimatedCost = v } }
            }
            row("Coût réel", icon: "creditcard") {
                CostField(value: task.actualCost) { v in commit(task, change: "a noté le coût réel") { $0.actualCost = v } }
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }

    private func row<Content: View>(_ label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Label(label, systemImage: icon).font(t.body(15))
            Spacer()
            content().font(t.headline(15))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    private func notesSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes").font(t.title(20))
                Spacer()
                Button(editingNotes ? "OK" : "Modifier") {
                    if editingNotes {
                        commit(task, change: "a modifié les notes") { $0.notes = notesDraft }
                    } else {
                        notesDraft = task.notes
                    }
                    editingNotes.toggle()
                }
                .font(t.body(15))
            }
            if editingNotes {
                TextField("Notes, idées, mesures…", text: $notesDraft, axis: .vertical)
                    .lineLimit(3...)
                    .padding(12)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text(task.notes.isEmpty ? "Aucune note." : task.notes)
                    .font(t.body(16))
                    .foregroundStyle(task.notes.isEmpty ? theme.secondaryText : theme.text)
            }
        }
    }

    private func checklist(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Étapes").font(t.title(20))
            ForEach(task.checklist) { entry in
                Button {
                    commit(task, change: entry.done ? "a décoché « \(entry.text) »" : "a coché « \(entry.text) »") {
                        if let i = $0.checklist.firstIndex(where: { $0.id == entry.id }) { $0.checklist[i].done.toggle() }
                    }
                } label: {
                    HStack {
                        Image(systemName: entry.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(entry.done ? theme.accent : theme.secondaryText)
                        StrikeText(text: entry.text, isStruck: entry.done, font: t.body(16), color: theme.text)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Supprimer", role: .destructive) {
                        commit(task, change: "a retiré une étape") { $0.checklist.removeAll { $0.id == entry.id } }
                    }
                }
            }
            HStack {
                TextField("Ajouter une étape", text: $newCheck).onSubmit { addCheck(task) }
                Button("Ajouter") { addCheck(task) }.disabled(newCheck.isEmpty)
            }
            .font(t.body(15))
        }
    }

    private func addCheck(_ task: TaskItem) {
        let text = newCheck.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        commit(task, change: "a ajouté l'étape « \(text) »") { $0.checklist.append(ChecklistEntry(text: text)) }
        newCheck = ""
    }

    private func links(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Liens").font(t.title(20))
            ForEach(task.links, id: \.self) { link in
                Button {
                    if let url = URL(string: link) { openURL(url) }
                } label: {
                    Label(URL(string: link)?.host() ?? link, systemImage: "link").font(t.body(15)).lineLimit(1)
                }
                .contextMenu {
                    Button("Retirer", role: .destructive) { commit(task, change: "a retiré un lien") { $0.links.removeAll { $0 == link } } }
                }
            }
            HStack {
                TextField("Coller un lien", text: $newLink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .onSubmit { addLink(task) }
                Button("Ajouter") { addLink(task) }.disabled(newLink.isEmpty)
            }
            .font(t.body(15))
        }
    }

    private func addLink(_ task: TaskItem) {
        var link = newLink.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty else { return }
        if !link.hasPrefix("http") { link = "https://" + link }
        commit(task, change: "a ajouté un lien") { $0.links.append(link) }
        newLink = ""
    }

    private func comments(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commentaires").font(t.title(20))
            ForEach(task.comments) { comment in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(comment.authorName).font(t.headline(14))
                        Spacer()
                        Text(comment.at.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_BE"))))
                            .font(t.caption(12)).foregroundStyle(theme.secondaryText)
                    }
                    Text(comment.text).font(t.body(15))
                }
                .padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(alignment: .bottom) {
                TextField("Écrire un commentaire", text: $newComment, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    commit(task, change: "a commenté : « \(text.prefix(60)) »") {
                        $0.comments.append(TaskComment(text: text, authorName: store.authorName))
                    }
                    newComment = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// Champ de montant en euros, enregistré quand on valide.
struct CostField: View {
    let value: Double?
    let onCommit: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("—", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
            .focused($focused)
            .onAppear { text = value.map { IngredientParser.format($0) } ?? "" }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                let number = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces))
                if number != value { onCommit(number) }
            }
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("OK") { focused = false }
                    }
                }
            }
    }
}

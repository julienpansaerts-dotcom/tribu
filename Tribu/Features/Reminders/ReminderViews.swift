import SwiftUI

/// Liste des rappels : pour moi, envoyés par moi, faits.
struct RemindersView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var filter = 0
    @State private var editing: Reminder?
    @State private var creating = false

    private var t: Typography { theme.typography }

    private var mine: [Reminder] {
        store.reminders.filter { !$0.isDone && $0.assigneeIds.contains(store.currentUserId) }.sorted { $0.dueAt < $1.dueAt }
    }
    private var sent: [Reminder] {
        store.reminders.filter { !$0.isDone && $0.createdById == store.currentUserId && !$0.assigneeIds.contains(store.currentUserId) }
            .sorted { $0.dueAt < $1.dueAt }
    }
    private var others: [Reminder] {
        store.reminders.filter { !$0.isDone && $0.createdById != store.currentUserId && !$0.assigneeIds.contains(store.currentUserId) }
            .sorted { $0.dueAt < $1.dueAt }
    }
    private var done: [Reminder] {
        store.reminders.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }.prefix(20).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: "Rappels", module: .rappels) { creating = true }
                Picker("Filtre", selection: $filter) {
                    Text("Pour moi").tag(0)
                    Text("Envoyés").tag(1)
                    Text("Faits").tag(2)
                }
                .pickerStyle(.segmented)

                let list = filter == 0 ? mine : (filter == 1 ? sent + others : done)
                if list.isEmpty {
                    EmptyState(text: filter == 0 ? "Rien à faire pour toi. Profite !" : "Aucun rappel ici.")
                }
                ForEach(list) { reminder in
                    ReminderRow(reminder: reminder)
                        .onTapGesture { editing = reminder }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { ReminderEditor(existing: nil) }
        .sheet(item: $editing) { ReminderEditor(existing: $0) }
        .onAppear {
            for reminder in mine { store.markSeen(reminder) }
        }
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DoneButton(isDone: reminder.isDone, tint: theme.text) {
                withAnimation(.snappy) { store.setReminder(reminder, done: !reminder.isDone) }
            }
            .padding(-7)
            VStack(alignment: .leading, spacing: 4) {
                StrikeText(text: reminder.title, isStruck: reminder.isDone, font: theme.typography.medium(17), color: theme.text)
                Text(subtitle).font(theme.typography.caption(13)).foregroundStyle(theme.secondaryText)
                if !reminder.note.isEmpty {
                    Text(reminder.note).font(theme.typography.body(14)).foregroundStyle(theme.secondaryText).lineLimit(2)
                }
                statusLine
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(reminder.dueAt.hm).font(theme.typography.headline(15))
                Text(dayText).font(theme.typography.caption(12)).foregroundStyle(isLate ? Color(hex: 0xD9480F) : theme.secondaryText)
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
        .contentShape(Rectangle())
    }

    private var isLate: Bool { !reminder.isDone && reminder.dueAt < .now }

    private var dayText: String {
        let cal = Calendar.current
        if cal.isDateInToday(reminder.dueAt) { return isLate ? "en retard" : "aujourd'hui" }
        if cal.isDateInTomorrow(reminder.dueAt) { return "demain" }
        if cal.isDateInYesterday(reminder.dueAt) { return "hier" }
        return reminder.dueAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_BE")))
    }

    private var subtitle: String {
        let to = store.names(reminder.assigneeIds)
        var text = "De \(reminder.createdByName) pour \(to.isEmpty ? "?" : to)"
        if reminder.recurrence != .none { text += " · \(reminder.recurrence.label.lowercased())" }
        return text
    }

    @ViewBuilder private var statusLine: some View {
        if let doneAt = reminder.doneAt {
            Label("Validé par \(reminder.doneByName ?? "?") \(doneAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_BE"))))",
                  systemImage: "checkmark.seal.fill")
                .font(theme.typography.caption(12))
                .foregroundStyle(theme.accent)
        } else if reminder.createdById == store.currentUserId {
            let seen = reminder.assigneeIds.filter { reminder.seenByIds.contains($0) }
            Label(seen.isEmpty ? "Pas encore vu" : "Vu par \(store.names(seen))", systemImage: seen.isEmpty ? "eye.slash" : "eye")
                .font(theme.typography.caption(12))
                .foregroundStyle(theme.secondaryText)
        }
    }
}

/// Création ou modification d'un rappel.
struct ReminderEditor: View {
    let existing: Reminder?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var title = ""
    @State private var note = ""
    @State private var dueAt = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var offsets: Set<Int> = [0]
    @State private var recurrence: Recurrence = .none
    @State private var assignees: Set<String> = []
    @State private var confirmDelete = false

    private let offsetChoices = [0, 10, 30, 60, 120, 1440]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Quoi ? (ex. Acheter du pain)", text: $title)
                        .font(theme.typography.title(22))
                    TextField("Détails (facultatif)", text: $note, axis: .vertical)
                }
                Section("Pour qui") {
                    PeoplePicker(selection: $assignees)
                }
                Section("Quand") {
                    DatePicker("Jour et heure", selection: $dueAt)
                        .environment(\.locale, Locale(identifier: "fr_BE"))
                    Picker("Répéter", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(offsetChoices, id: \.self) { minutes in
                            let on = offsets.contains(minutes)
                            Button {
                                if on { offsets.remove(minutes) } else { offsets.insert(minutes) }
                            } label: {
                                Text(Reminder.offsetLabel(minutes))
                                    .font(theme.typography.body(14))
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .background(on ? theme.text : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(theme.separator))
                                    .foregroundStyle(on ? theme.background : theme.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(footer)
                }
                if let existing {
                    Section {
                        Button(existing.isDone ? "Remettre à faire" : "Marquer comme fait") {
                            store.setReminder(existing, done: !existing.isDone)
                            dismiss()
                        }
                        Button("Supprimer le rappel", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle(existing == nil ? "Nouveau rappel" : "Rappel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Envoyer" : "Enregistrer", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || assignees.isEmpty)
                }
            }
            .confirmationDialog("Supprimer ce rappel ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private var footer: String {
        let times = offsets.sorted(by: >).map { minutes -> String in
            let date = dueAt.addingTimeInterval(TimeInterval(-minutes * 60))
            return minutes >= 1440
                ? date.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_BE"))) + " " + date.hm
                : date.hm
        }
        guard !times.isEmpty else { return "Aucune notification : le rappel sera seulement visible dans l'app." }
        return "Notifications à " + ListFormatter.localizedString(byJoining: times) + "."
    }

    private func load() {
        if let existing {
            title = existing.title
            note = existing.note
            dueAt = existing.dueAt
            offsets = Set(existing.offsets)
            recurrence = existing.recurrence
            assignees = Set(existing.assigneeIds)
        } else if assignees.isEmpty {
            if let other = store.people.first(where: { $0.linkedUid != nil && $0.id != store.currentUserId }) {
                assignees = [other.id]
            } else if !store.currentUserId.isEmpty {
                assignees = [store.currentUserId]
            }
        }
    }

    private func save() {
        var reminder = existing ?? Reminder(
            title: "", dueAt: dueAt, assigneeIds: [], createdById: store.currentUserId, createdByName: store.authorName
        )
        reminder.title = title.trimmingCharacters(in: .whitespaces)
        reminder.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.dueAt = dueAt
        reminder.offsets = offsets.sorted(by: >)
        reminder.recurrence = recurrence
        reminder.assigneeIds = Array(assignees)
        if existing != nil, existing?.dueAt != dueAt { reminder.seenByIds = [] }
        store.save(reminder)
        if existing == nil {
            store.post("a laissé un rappel pour \(store.names(reminder.assigneeIds)) : « \(reminder.title) »", icon: "bell")
        }
        dismiss()
    }
}

/// Sélection de personnes de la famille, avec leurs pastilles.
struct PeoplePicker: View {
    @Binding var selection: Set<String>
    var onlyAccounts = false
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(store.people.filter { !onlyAccounts || $0.linkedUid != nil }) { person in
                let on = selection.contains(person.id)
                Button {
                    if on { selection.remove(person.id) } else { selection.insert(person.id) }
                } label: {
                    HStack(spacing: 6) {
                        Avatar(person: person, size: 22)
                        Text(person.id == store.currentUserId ? "Moi" : person.firstName)
                            .font(theme.typography.body(15))
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                    .frame(height: 34)
                    .background(on ? theme.text : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.separator))
                    .foregroundStyle(on ? theme.background : theme.text)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// En-tête de module : grand titre et bouton d'ajout.
struct ModuleHeader: View {
    let title: String
    let module: Module
    var action: (() -> Void)?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(theme.typography.display(42))
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(theme.color(for: module), in: Circle())
                        .foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter")
            }
        }
        .padding(.top, 8)
    }
}

struct EmptyState: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(theme.typography.body(16))
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
    }
}

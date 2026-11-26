import SwiftUI

/// Idées d'activités : étiquettes, votes, « planifier » vers l'agenda.
struct ActivitiesView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var tag: String?
    @State private var creating = false
    @State private var planning: Activity?

    private var t: Typography { theme.typography }

    private var tags: [String] {
        Array(Set(store.activities.flatMap(\.tags))).sorted()
    }

    private var list: [Activity] {
        store.activities
            .filter { tag == nil || $0.tags.contains(tag!) }
            .sorted { ($0.plannedDate == nil ? 0 : 1, -$0.voterIds.count) < ($1.plannedDate == nil ? 0 : 1, -$1.voterIds.count) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: "Activités", module: .activites) { creating = true }
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("Toutes", selected: tag == nil) { tag = nil }
                            ForEach(tags, id: \.self) { value in
                                chip(value, selected: tag == value) { tag = tag == value ? nil : value }
                            }
                        }
                    }
                }
                if list.isEmpty {
                    EmptyState(text: "Notez les sorties, balades et ateliers qui vous tentent. Votez, puis planifiez-les dans l'agenda.")
                }
                ForEach(list) { activity in
                    ActivityCard(activity: activity) { planning = activity }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { ActivityEditor() }
        .sheet(item: $planning) { PlanActivitySheet(activity: $0) }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Text(text)
                .font(t.body(14))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selected ? theme.text : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.separator))
                .foregroundStyle(selected ? theme.background : theme.text)
        }
        .buttonStyle(.plain)
    }
}

struct ActivityCard: View {
    let activity: Activity
    let onPlan: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(FamilyStore.self) private var store
    @State private var confirmDelete = false

    var body: some View {
        let voted = activity.voterIds.contains(store.currentUserId)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.title).font(theme.typography.title(20))
                    if !activity.details.isEmpty {
                        Text(activity.details).font(theme.typography.body(14)).opacity(0.85)
                    }
                }
                Spacer()
                Menu {
                    if let url = URL(string: activity.link), !activity.link.isEmpty {
                        Button("Ouvrir le lien", systemImage: "safari") { openURL(url) }
                    }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32)
                }
            }
            if !activity.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(activity.tags, id: \.self) { tag in
                        Text(tag).font(theme.typography.caption(12))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.45), in: Capsule())
                    }
                }
            }
            HStack {
                Button {
                    var updated = activity
                    if voted { updated.voterIds.removeAll { $0 == store.currentUserId } } else { updated.voterIds.append(store.currentUserId) }
                    withAnimation(.spring) { store.save(updated) }
                } label: {
                    Label("\(activity.voterIds.count)", systemImage: voted ? "heart.fill" : "heart")
                        .font(theme.typography.headline(14))
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: voted)
                Spacer()
                if let planned = activity.plannedDate {
                    Label(planned.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE"))), systemImage: "calendar.badge.checkmark")
                        .font(theme.typography.caption(13))
                } else {
                    Button(action: onPlan) {
                        Label("Planifier", systemImage: "calendar.badge.plus")
                            .font(theme.typography.headline(14))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(theme.ink, in: Capsule())
                            .foregroundStyle(theme.color(for: .activites))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(theme.ink)
        .padding(16)
        .background(theme.color(for: .activites), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .confirmationDialog("Supprimer « \(activity.title) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { store.delete(activity) }
        }
    }
}

struct ActivityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var title = ""
    @State private var details = ""
    @State private var link = ""
    @State private var tags: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Idée d'activité", text: $title)
                TextField("Détails, prix, horaires…", text: $details, axis: .vertical)
                TextField("Lien (facultatif)", text: $link).keyboardType(.URL).textInputAutocapitalization(.never)
                Section("Étiquettes") {
                    FlowLayout(spacing: 8) {
                        ForEach(Activity.suggestedTags, id: \.self) { tag in
                            let on = tags.contains(tag)
                            Button {
                                if on { tags.remove(tag) } else { tags.insert(tag) }
                            } label: {
                                Text(tag)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(on ? Color.primary : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                                    .foregroundStyle(on ? Color(uiColor: .systemBackground) : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Nouvelle activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        var url = link.trimmingCharacters(in: .whitespaces)
                        if !url.isEmpty && !url.hasPrefix("http") { url = "https://" + url }
                        let activity = Activity(title: title.trimmingCharacters(in: .whitespaces), details: details, link: url,
                                                tags: tags.sorted(), voterIds: store.currentUserId.isEmpty ? [] : [store.currentUserId],
                                                createdByName: store.authorName)
                        store.save(activity)
                        store.post("propose une activité : « \(activity.title) »", icon: "figure.walk")
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Planifier une activité : crée l'événement dans l'agenda.
struct PlanActivitySheet: View {
    let activity: Activity
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var date = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 10, weekday: 7), matchingPolicy: .nextTime) ?? .now
    @State private var allDay = false
    @State private var people: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Toute la journée", isOn: $allDay)
                DatePicker("Quand", selection: $date, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    .environment(\.locale, Locale(identifier: "fr_BE"))
                Section("Qui vient") { PeoplePicker(selection: $people) }
            }
            .navigationTitle(activity.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Planifier") {
                        let start = allDay ? Calendar.current.startOfDay(for: date) : date
                        let end = allDay ? start.addingTimeInterval(86_400) : start.addingTimeInterval(3 * 3600)
                        store.save(FamilyEvent(title: activity.title, start: start, end: end, allDay: allDay, personIds: Array(people),
                                               notes: activity.details, alertMinutes: allDay ? nil : 60, createdByName: store.authorName))
                        var updated = activity
                        updated.plannedDate = start
                        store.save(updated)
                        store.post("a planifié « \(activity.title) »", icon: "calendar.badge.checkmark")
                        dismiss()
                    }
                }
            }
            .onAppear { people = Set(store.people.map(\.id)) }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Fil d'activité de la tribu.
struct FeedView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Fil d'activité").font(theme.typography.display(38)).padding(.vertical, 8)
                if store.feed.isEmpty {
                    EmptyState(text: "Ce que fait chacun dans Tribu apparaîtra ici.")
                }
                ForEach(store.feed.sorted { $0.createdAt > $1.createdAt }) { entry in
                    FeedRow(entry: entry)
                    Divider().overlay(theme.separator)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedRow: View {
    let entry: FeedEntry
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.icon)
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .background(theme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                (Text(entry.actorName).font(theme.typography.headline(15)) + Text(" " + entry.text).font(theme.typography.body(15)))
                Text(entry.createdAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_BE"))))
                    .font(theme.typography.caption(12))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.vertical, 10)
    }
}

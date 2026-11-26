import SwiftUI

/// Agenda partagé : bande de jours, programme du jour choisi et ce qui arrive.
struct AgendaView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var weekOffset = 0
    @State private var creating = false
    @State private var editing: FamilyEvent?
    @AppStorage("tribu.calendarSync") private var syncEnabled = false
    @State private var showSettings = false

    private var t: Typography { theme.typography }
    private let cal = Calendar.current

    private var weekDays: [Date] {
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -weekday + weekOffset * 7, to: today) ?? today
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Agenda").font(t.display(42))
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: syncEnabled ? "icloud.fill" : "icloud")
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel("Copie dans le calendrier iPhone")
                        Button { creating = true } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(theme.color(for: .agenda), in: Circle())
                                .foregroundStyle(theme.ink)
                        }
                        .accessibilityLabel("Nouvel événement")
                    }
                    .padding(.top, 8)

                    weekStrip
                    dayProgram
                    upcoming
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .themedBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $creating) { EventEditor(existing: nil, defaultDay: selectedDay) }
            .sheet(item: $editing) { EventEditor(existing: $0, defaultDay: selectedDay) }
            .sheet(isPresented: $showSettings) { CalendarSyncSheet().presentationDetents([.medium]) }
            .onChange(of: store.events) { _, events in CalendarSync.shared.sync(events, people: store.people) }
            .onAppear { CalendarSync.shared.sync(store.events, people: store.people) }
        }
    }

    // MARK: Bande de jours

    private var weekStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Text(weekDays[0].formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE"))).capitalizedFirst)
                    .font(t.headline(15))
                Spacer()
                Button { withAnimation(.snappy) { weekOffset -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                Button {
                    withAnimation(.snappy) {
                        weekOffset = 0
                        selectedDay = cal.startOfDay(for: .now)
                    }
                } label: { Text("Aujourd'hui").font(t.caption(13)) }
                Button { withAnimation(.snappy) { weekOffset += 1 } } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
            }
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    let selected = cal.isDate(day, inSameDayAs: selectedDay)
                    let hasItems = !items(on: day).isEmpty
                    let isHoliday = !BelgianCalendar.labels(for: day).isEmpty
                    Button {
                        withAnimation(.snappy) { selectedDay = day }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "fr_BE"))).uppercased())
                                .font(t.caption(11))
                            Text(day.formatted(.dateTime.day())).font(t.number(20))
                            Circle()
                                .fill(hasItems ? (selected ? theme.background : theme.accent) : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            selected ? theme.text : (isHoliday ? theme.color(for: .agenda).opacity(0.35) : theme.surface),
                            in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous)
                        )
                        .foregroundStyle(selected ? theme.background : (cal.isDateInToday(day) ? theme.accent : theme.text))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Programme du jour

    private struct DayItem: Identifiable {
        enum Kind { case event(FamilyEvent), reminder(Reminder), birthday(Person), meal(Meal) }
        let id: String
        let time: String
        let title: String
        let detail: String
        let color: Color
        let kind: Kind
        let sort: Date
    }

    private func items(on day: Date) -> [DayItem] {
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        var list: [DayItem] = []
        for event in store.events {
            for occurrence in event.occurrences(in: interval) {
                let color = store.person(occurrence.personIds.first).map { Color(hex: $0.colorHex) } ?? theme.color(for: .agenda)
                list.append(DayItem(
                    id: "e\(event.id)\(occurrence.start.timeIntervalSince1970)",
                    time: occurrence.allDay ? "Journée" : occurrence.start.hm,
                    title: occurrence.title,
                    detail: [store.names(occurrence.personIds), occurrence.location].filter { !$0.isEmpty }.joined(separator: " · "),
                    color: color, kind: .event(event), sort: occurrence.allDay ? start : occurrence.start))
            }
        }
        for reminder in store.reminders where interval.contains(reminder.dueAt) {
            list.append(DayItem(id: "r\(reminder.id)", time: reminder.dueAt.hm,
                                title: reminder.title, detail: "Rappel pour \(store.names(reminder.assigneeIds))",
                                color: theme.color(for: .rappels), kind: .reminder(reminder), sort: reminder.dueAt))
        }
        for person in store.people {
            guard let birth = person.birthDate else { continue }
            let b = cal.dateComponents([.month, .day], from: birth)
            let d = cal.dateComponents([.month, .day], from: day)
            if b.month == d.month && b.day == d.day {
                let age = cal.dateComponents([.year], from: birth, to: day).year ?? 0
                list.append(DayItem(id: "b\(person.id)", time: "Journée", title: "Anniversaire de \(person.firstName)",
                                    detail: "\(age) an\(age > 1 ? "s" : "")", color: Color(hex: person.colorHex),
                                    kind: .birthday(person), sort: start))
            }
        }
        if let meal = store.meals.first(where: { $0.id == Meal.key(for: day) }) {
            list.append(DayItem(id: "m\(meal.id)", time: "Soir", title: meal.title, detail: "Au menu",
                                color: theme.color(for: .repas), kind: .meal(meal),
                                sort: cal.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? day))
        }
        return list.sorted { $0.sort < $1.sort }
    }

    private var dayProgram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE"))).capitalizedFirst)
                .font(t.title(24))
            ForEach(BelgianCalendar.labels(for: selectedDay), id: \.self) { label in
                Label(label, systemImage: label.hasPrefix("Férié") ? "flag" : "sun.max")
                    .font(t.caption(13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.color(for: .agenda).opacity(0.5), in: Capsule())
                    .foregroundStyle(theme.ink)
            }
            let list = items(on: selectedDay)
            if list.isEmpty {
                EmptyState(text: "Rien de prévu ce jour-là.")
            }
            ForEach(list) { item in
                Button {
                    if case .event(let event) = item.kind { editing = event }
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(t.medium(16)).multilineTextAlignment(.leading)
                            if !item.detail.isEmpty {
                                Text(item.detail).font(t.caption(13)).foregroundStyle(theme.secondaryText)
                            }
                        }
                        Spacer()
                        Text(item.time).font(t.headline(14)).foregroundStyle(theme.secondaryText)
                    }
                    .padding(12)
                    .frame(minHeight: 56)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: À venir

    private struct UpcomingEntry: Identifiable {
        let day: Date
        let item: DayItem
        var id: String { item.id + String(day.timeIntervalSince1970) }
    }

    private var upcomingEntries: [UpcomingEntry] {
        var result: [UpcomingEntry] = []
        for offset in 1...21 {
            let day = cal.date(byAdding: .day, value: offset, to: selectedDay) ?? selectedDay
            for item in items(on: day) {
                if case .meal = item.kind { continue }
                result.append(UpcomingEntry(day: day, item: item))
            }
            if result.count >= 8 { break }
        }
        return Array(result.prefix(8))
    }

    private var upcoming: some View {
        let next = upcomingEntries
        return VStack(alignment: .leading, spacing: 8) {
            if !next.isEmpty {
                Text("À venir").font(t.title(22)).padding(.top, 8)
            }
            ForEach(next) { entry in
                let day = entry.day
                let item = entry.item
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_BE"))).uppercased()).font(t.caption(10))
                        Text(day.formatted(.dateTime.day())).font(t.number(18))
                    }
                    .frame(width: 40)
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(item.title).font(t.body(15)).lineLimit(1)
                    Spacer()
                    Text(item.time).font(t.caption(12)).foregroundStyle(theme.secondaryText)
                }
                .frame(minHeight: 40)
            }
        }
    }
}

/// Création ou modification d'un événement.
struct EventEditor: View {
    let existing: FamilyEvent?
    let defaultDay: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var title = ""
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var allDay = false
    @State private var people: Set<String> = []
    @State private var location = ""
    @State private var notes = ""
    @State private var recurrence: Recurrence = .none
    @State private var alert: Int = -1
    @State private var confirmDelete = false

    private let alertChoices: [(Int, String)] = [(-1, "Aucune"), (0, "À l'heure"), (15, "15 min avant"), (60, "1 h avant"), (1440, "La veille")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre (ex. Piscine, dentiste…)", text: $title)
                    TextField("Lieu", text: $location)
                }
                Section {
                    Toggle("Toute la journée", isOn: $allDay.animation())
                    DatePicker("Début", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Fin", selection: $end, in: start..., displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    Picker("Répéter", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Notification", selection: $alert) {
                        ForEach(alertChoices.indices, id: \.self) { index in
                            Text(alertChoices[index].1).tag(alertChoices[index].0)
                        }
                    }
                }
                .environment(\.locale, Locale(identifier: "fr_BE"))
                Section("Qui") {
                    PeoplePicker(selection: $people)
                }
                Section("Notes") {
                    TextField("Infos utiles", text: $notes, axis: .vertical)
                }
                if existing != nil {
                    Section {
                        Button("Supprimer l'événement", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Nouvel événement" : "Événement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: start) { old, new in
                let duration = end.timeIntervalSince(old)
                end = new.addingTimeInterval(max(duration, allDay ? 0 : 1800))
            }
            .confirmationDialog("Supprimer cet événement ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let existing {
            title = existing.title
            start = existing.start
            end = existing.end
            allDay = existing.allDay
            people = Set(existing.personIds)
            location = existing.location
            notes = existing.notes
            recurrence = existing.recurrence
            alert = existing.alertMinutes ?? -1
        } else {
            let base = Calendar.current.isDateInToday(defaultDay) ? Date.now : defaultDay
            let hour = Calendar.current.component(.hour, from: base)
            start = Calendar.current.date(bySettingHour: min(max(hour + 1, 8), 20), minute: 0, second: 0, of: defaultDay) ?? defaultDay
            end = start.addingTimeInterval(3600)
            alert = 60
        }
    }

    private func save() {
        var event = existing ?? FamilyEvent(title: "", start: start, end: end, createdByName: store.authorName)
        event.title = title.trimmingCharacters(in: .whitespaces)
        event.start = allDay ? Calendar.current.startOfDay(for: start) : start
        event.end = allDay ? (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end) : end
        event.allDay = allDay
        event.personIds = Array(people)
        event.location = location
        event.notes = notes
        event.recurrence = recurrence
        event.alertMinutes = alert >= 0 ? alert : nil
        store.save(event)
        if existing == nil {
            store.post("a ajouté « \(event.title) » à l'agenda", icon: "calendar")
        }
        dismiss()
    }
}

/// Réglage de la copie vers le calendrier de l'iPhone.
struct CalendarSyncSheet: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @AppStorage("tribu.calendarSync") private var syncEnabled = false
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendrier de l'iPhone").font(theme.typography.display(30))
            Text("Tribu peut copier l'agenda de la famille dans un calendrier « Tribu » (dans iCloud), visible dans l'app Calendrier d'Apple, sur ta montre et ton Mac. Les modifications se font dans Tribu.")
                .font(theme.typography.body(15))
                .foregroundStyle(theme.secondaryText)
            Toggle("Copier l'agenda dans iCloud", isOn: Binding(
                get: { syncEnabled },
                set: { on in
                    Task { @MainActor in
                        if on {
                            let granted = await CalendarSync.shared.enable()
                            syncEnabled = granted
                            denied = !granted
                            if granted { CalendarSync.shared.sync(store.events, people: store.people) }
                        } else {
                            CalendarSync.shared.disable()
                            syncEnabled = false
                        }
                    }
                }
            ))
            .font(theme.typography.headline(16))
            if denied {
                Text("Accès refusé : autorise Tribu dans Réglages → Confidentialité → Calendriers.")
                    .font(theme.typography.caption(13))
                    .foregroundStyle(Color(hex: 0xD9480F))
            }
            Spacer()
        }
        .padding(24)
        .themedBackground()
    }
}

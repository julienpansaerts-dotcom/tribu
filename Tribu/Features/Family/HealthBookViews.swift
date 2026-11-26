import LocalAuthentication
import SwiftUI

/// Accès au carnet de santé depuis la fiche d'une personne.
struct HealthBookLink: View {
    let person: Person
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        let visits = store.visits.filter { $0.personId == person.id }
        let next = visits.compactMap(\.nextAppointment).filter { $0 > .now }.min()
        NavigationLink {
            HealthBookView(personId: person.id)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "cross.case.fill")
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .background(theme.color(for: .famille), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Carnet de santé").font(theme.typography.headline(17))
                    Text(subtitle(visits: visits.count, next: next))
                        .font(theme.typography.caption(13))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Image(systemName: "faceid").foregroundStyle(theme.secondaryText)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.secondaryText)
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(visits: Int, next: Date?) -> String {
        var parts = ["\(visits) visite\(visits > 1 ? "s" : "")"]
        if let next {
            parts.append("prochain RDV " + next.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE"))))
        }
        return parts.joined(separator: " · ")
    }
}

/// Carnet de santé d'une personne : médecins, visites, vaccins, traitements.
struct HealthBookView: View {
    let personId: String
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var unlocked = UserDefaults.standard.bool(forKey: "tribu.demo")
    @State private var addingVisit = false
    @State private var editingVisit: MedicalVisit?
    @State private var addingDoctor = false
    @State private var editingDoctor: Doctor?
    @State private var filterDoctor: String?

    private var t: Typography { theme.typography }

    var body: some View {
        if let person = store.person(personId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CARNET DE SANTÉ").font(t.headline(12)).tracking(1).foregroundStyle(theme.secondaryText)
                        Text(person.firstName).font(t.display(40))
                        Text([person.ageText, person.bloodType.map { "Groupe \($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(t.caption(14)).foregroundStyle(theme.secondaryText)
                    }
                    if unlocked {
                        content(person)
                    } else {
                        lockScreen(person)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if unlocked {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Nouvelle visite", systemImage: "stethoscope") { addingVisit = true }
                            Button("Nouveau médecin", systemImage: "person.badge.plus") { addingDoctor = true }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $addingVisit) { VisitEditor(person: person, existing: nil) }
            .sheet(item: $editingVisit) { VisitEditor(person: person, existing: $0) }
            .sheet(isPresented: $addingDoctor) { DoctorEditor(existing: nil, defaultPersonId: person.id) }
            .sheet(item: $editingDoctor) { DoctorEditor(existing: $0, defaultPersonId: person.id) }
        }
    }

    private func lockScreen(_ person: Person) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(theme.secondaryText)
            Text("Les informations médicales sont protégées.").font(t.body(16)).foregroundStyle(theme.secondaryText)
            Button {
                unlock(person)
            } label: {
                Label("Déverrouiller avec Face ID", systemImage: "faceid")
                    .font(t.headline(16))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(theme.text, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(theme.background)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 40)
        .onAppear { unlock(person) }
    }

    @ViewBuilder private func content(_ person: Person) -> some View {
        let visits = store.visits.filter { $0.personId == person.id }.sorted { $0.date > $1.date }
        let doctorIds = Set(visits.compactMap(\.doctorId))
        let doctors = store.doctors.filter { $0.personIds.contains(person.id) || doctorIds.contains($0.id) }
        let upcoming = visits.compactMap { visit -> (MedicalVisit, Date)? in
            guard let next = visit.nextAppointment, next > .now else { return nil }
            return (visit, next)
        }.sorted { $0.1 < $1.1 }.first

        if !person.allergies.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xFFCF4D))
                Text("Allergies : " + person.allergies.joined(separator: ", ")).font(t.headline(15))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color(hex: 0x2B2A26), in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
        }

        if let upcoming {
            let doctor = store.doctors.first { $0.id == upcoming.0.doctorId }
            VStack(alignment: .leading, spacing: 6) {
                Text("Prochain rendez-vous").font(t.headline(13)).opacity(0.75)
                Text(upcoming.1.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE"))).capitalizedFirst + " · " + upcoming.1.hm)
                    .font(t.title(22))
                Text([doctor?.name, doctor?.specialty, upcoming.0.reason.isEmpty ? nil : "suite : " + upcoming.0.reason]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(t.body(14))
            }
            .foregroundStyle(theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(for: .agenda), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        }

        // Médecins
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Médecins").font(t.title(22))
                Spacer()
                Button { addingDoctor = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter un médecin")
            }
            if doctors.isEmpty {
                Text("Ajoute le pédiatre, le médecin traitant, les spécialistes… avec leurs coordonnées.")
                    .font(t.body(14)).foregroundStyle(theme.secondaryText)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(doctors) { doctor in
                        DoctorCard(doctor: doctor, visits: visits.filter { $0.doctorId == doctor.id }.count,
                                   selected: filterDoctor == doctor.id) {
                            editingDoctor = doctor
                        } onFilter: {
                            withAnimation(.snappy) { filterDoctor = filterDoctor == doctor.id ? nil : doctor.id }
                        }
                    }
                }
            }
        }

        // Visites
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Visites").font(t.title(22))
                if let filterDoctor, let name = store.doctors.first(where: { $0.id == filterDoctor })?.name {
                    Button {
                        withAnimation { self.filterDoctor = nil }
                    } label: {
                        Label(name, systemImage: "xmark.circle.fill").font(t.caption(12))
                    }
                }
                Spacer()
                Button { addingVisit = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter une visite")
            }
            let shown = visits.filter { filterDoctor == nil || $0.doctorId == filterDoctor }
            if shown.isEmpty {
                Text("Après chaque rendez-vous, note ce qui a été vu et dit : tout le monde pourra le relire.")
                    .font(t.body(14)).foregroundStyle(theme.secondaryText)
            }
            ForEach(shown) { visit in
                Button { editingVisit = visit } label: { VisitRow(visit: visit) }.buttonStyle(.plain)
            }
        }

        // Vaccins
        let vaccines = visits.flatMap { visit in visit.vaccines.map { (visit.date, $0) } }
        if !vaccines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vaccins").font(t.title(22))
                ForEach(Array(vaccines.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Image(systemName: "syringe").foregroundStyle(theme.secondaryText)
                        Text(entry.1).font(t.body(15))
                        Spacer()
                        Text(entry.0.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_BE"))))
                            .font(t.caption(12)).foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
    }

    private func unlock(_ person: Person) {
        guard !unlocked else { return }
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        context.evaluatePolicy(policy, localizedReason: "Afficher le carnet de santé de \(person.firstName)") { success, _ in
            DispatchQueue.main.async { withAnimation(.smooth) { unlocked = success } }
        }
    }
}

struct DoctorCard: View {
    let doctor: Doctor
    let visits: Int
    let selected: Bool
    let onEdit: () -> Void
    let onFilter: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onFilter) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(doctor.specialty.uppercased()).font(theme.typography.headline(11)).tracking(0.6).opacity(0.7)
                    Text(doctor.name).font(theme.typography.title(18)).lineLimit(1)
                    Text("\(visits) visite\(visits > 1 ? "s" : "")").font(theme.typography.caption(12)).opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                if let url = URL(string: "tel:" + doctor.phone.filter { $0.isNumber || $0 == "+" }), !doctor.phone.isEmpty {
                    circleButton("phone.fill", label: "Appeler") { openURL(url) }
                }
                if let url = URL(string: "mailto:" + doctor.email), !doctor.email.isEmpty {
                    circleButton("envelope.fill", label: "Écrire") { openURL(url) }
                }
                if !doctor.address.isEmpty,
                   let url = URL(string: "http://maps.apple.com/?q=" + (doctor.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                    circleButton("map.fill", label: "Itinéraire") { openURL(url) }
                }
                Spacer()
                circleButton("pencil", label: "Modifier", action: onEdit)
            }
        }
        .foregroundStyle(theme.ink)
        .padding(14)
        .frame(width: 210)
        .background(theme.color(for: .famille), in: RoundedRectangle(cornerRadius: min(theme.cornerRadius + 4, 18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: min(theme.cornerRadius + 4, 18), style: .continuous)
                .strokeBorder(theme.ink, lineWidth: selected ? 2 : 0)
        )
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct VisitRow: View {
    let visit: MedicalVisit
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        let doctor = store.doctors.first { $0.id == visit.doctorId }
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(visit.date.formatted(.dateTime.day())).font(theme.typography.number(22))
                Text(visit.date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "fr_BE"))).uppercased())
                    .font(theme.typography.caption(10))
                Text(visit.date.formatted(.dateTime.year())).font(theme.typography.caption(10)).foregroundStyle(theme.secondaryText)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(visit.reason.isEmpty ? "Consultation" : visit.reason).font(theme.typography.medium(16))
                if let doctor {
                    Text("\(doctor.name) · \(doctor.specialty)").font(theme.typography.caption(12)).foregroundStyle(theme.secondaryText)
                }
                if !visit.summary.isEmpty {
                    Text(visit.summary).font(theme.typography.body(14)).lineLimit(3).multilineTextAlignment(.leading)
                }
                HStack(spacing: 10) {
                    if let height = visit.heightCm { Label(IngredientParser.format(height) + " cm", systemImage: "ruler") }
                    if let weight = visit.weightKg { Label(IngredientParser.format(weight) + " kg", systemImage: "scalemass") }
                    if !visit.vaccines.isEmpty { Label("\(visit.vaccines.count) vaccin\(visit.vaccines.count > 1 ? "s" : "")", systemImage: "syringe") }
                    if !visit.treatment.isEmpty { Label("Traitement", systemImage: "pills") }
                }
                .font(theme.typography.caption(12))
                .foregroundStyle(theme.secondaryText)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
    }
}

/// Saisie d'une visite : motif, résumé, mesures, vaccins, traitement, prochain rendez-vous.
struct VisitEditor: View {
    let person: Person
    let existing: MedicalVisit?
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var visit = MedicalVisit(personId: "")
    @State private var height = ""
    @State private var weight = ""
    @State private var head = ""
    @State private var newVaccine = ""
    @State private var hasNext = false
    @State private var nextDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var addToAgenda = true
    @State private var addingDoctor = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $visit.date)
                    Picker("Médecin", selection: Binding(get: { visit.doctorId ?? "" }, set: { visit.doctorId = $0.isEmpty ? nil : $0 })) {
                        Text("Aucun").tag("")
                        ForEach(store.doctors) { Text("\($0.name) · \($0.specialty)").tag($0.id) }
                    }
                    Button("Ajouter un médecin", systemImage: "person.badge.plus") { addingDoctor = true }
                    TextField("Motif (bilan, fièvre, vaccin…)", text: $visit.reason)
                }
                Section("Ce qui a été vu et dit") {
                    TextField("Résumé de la visite, conseils du médecin…", text: $visit.summary, axis: .vertical)
                        .lineLimit(4...)
                }
                Section("Mesures") {
                    measure("Taille", unit: "cm", text: $height)
                    measure("Poids", unit: "kg", text: $weight)
                    if person.isChild { measure("Périmètre crânien", unit: "cm", text: $head) }
                }
                Section("Vaccins") {
                    ForEach(visit.vaccines, id: \.self) { Text($0) }
                        .onDelete { visit.vaccines.remove(atOffsets: $0) }
                    HStack {
                        TextField("Ajouter un vaccin", text: $newVaccine).onSubmit(addVaccine)
                        Button("Ajouter", action: addVaccine).disabled(newVaccine.isEmpty)
                    }
                }
                Section("Traitement") {
                    TextField("Médicament, dose, durée", text: $visit.treatment, axis: .vertical)
                }
                Section {
                    Toggle("Prochain rendez-vous", isOn: $hasNext.animation())
                    if hasNext {
                        DatePicker("Le", selection: $nextDate, in: Date.now...)
                        Toggle("Ajouter à l'agenda (avec rappel la veille)", isOn: $addToAgenda)
                    }
                }
                if existing != nil {
                    Section { Button("Supprimer la visite", role: .destructive) { confirmDelete = true } }
                }
            }
            .environment(\.locale, Locale(identifier: "fr_BE"))
            .navigationTitle(existing == nil ? "Visite · \(person.firstName)" : "Visite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save) }
            }
            .sheet(isPresented: $addingDoctor) { DoctorEditor(existing: nil, defaultPersonId: person.id) }
            .onChange(of: store.doctors.count) { old, new in
                if new > old, let latest = store.doctors.last { visit.doctorId = latest.id }
            }
            .confirmationDialog("Supprimer cette visite ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func measure(_ label: String, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func addVaccine() {
        let value = newVaccine.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        visit.vaccines.append(value)
        newVaccine = ""
    }

    private func load() {
        if let existing {
            visit = existing
            height = existing.heightCm.map(IngredientParser.format) ?? ""
            weight = existing.weightKg.map(IngredientParser.format) ?? ""
            head = existing.headCm.map(IngredientParser.format) ?? ""
            hasNext = existing.nextAppointment != nil
            if let next = existing.nextAppointment { nextDate = next }
            addToAgenda = false
        } else {
            visit = MedicalVisit(personId: person.id, createdByName: store.authorName)
            visit.doctorId = store.doctors.first { $0.personIds.contains(person.id) }?.id
        }
    }

    private func save() {
        addVaccine()
        visit.heightCm = number(height)
        visit.weightKg = number(weight)
        visit.headCm = number(head)
        visit.nextAppointment = hasNext ? nextDate : nil
        store.save(visit)

        // Les mesures alimentent aussi la courbe de croissance.
        if existing == nil, visit.heightCm != nil || visit.weightKg != nil {
            store.saveGrowth(GrowthPoint(date: visit.date, heightCm: visit.heightCm, weightKg: visit.weightKg), personId: person.id)
        }
        // Prochain rendez-vous dans l'agenda partagé.
        if hasNext, addToAgenda {
            let doctor = store.doctors.first { $0.id == visit.doctorId }
            store.save(FamilyEvent(
                title: "\(person.firstName) · \(doctor?.specialty ?? "Médecin")",
                start: nextDate, end: nextDate.addingTimeInterval(1800),
                personIds: [person.id], location: doctor.map { [$0.name, $0.address].filter { !$0.isEmpty }.joined(separator: ", ") } ?? "",
                notes: visit.reason, alertMinutes: 1440, createdByName: store.authorName
            ))
        }
        if existing == nil {
            store.post("a noté une visite de \(person.firstName)\(visit.reason.isEmpty ? "" : " : « \(visit.reason) »")", icon: "stethoscope")
        }
        dismiss()
    }
}

/// Fiche d'un médecin.
struct DoctorEditor: View {
    let existing: Doctor?
    let defaultPersonId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var doctor = Doctor(name: "")
    @State private var people: Set<String> = []
    @State private var customSpecialty = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom (ex. Dr Lambert)", text: $doctor.name)
                    Picker("Spécialité", selection: $doctor.specialty) {
                        ForEach(Doctor.specialties, id: \.self) { Text($0).tag($0) }
                        if !Doctor.specialties.contains(doctor.specialty) { Text(doctor.specialty).tag(doctor.specialty) }
                    }
                    if doctor.specialty == "Autre" {
                        TextField("Laquelle ?", text: $customSpecialty)
                    }
                }
                Section("Coordonnées") {
                    TextField("Téléphone", text: $doctor.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("E-mail", text: $doctor.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Adresse du cabinet", text: $doctor.address, axis: .vertical).textContentType(.fullStreetAddress)
                }
                Section("Suit") {
                    PeoplePicker(selection: $people)
                }
                Section("Notes") {
                    TextField("Horaires, consultations sans RDV, secrétariat…", text: $doctor.notes, axis: .vertical)
                }
                if existing != nil {
                    Section { Button("Supprimer ce médecin", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Nouveau médecin" : doctor.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if doctor.specialty == "Autre", !customSpecialty.trimmingCharacters(in: .whitespaces).isEmpty {
                            doctor.specialty = customSpecialty.trimmingCharacters(in: .whitespaces)
                        }
                        doctor.personIds = Array(people)
                        store.save(doctor)
                        dismiss()
                    }
                    .disabled(doctor.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Supprimer ce médecin ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            }
            .onAppear {
                if let existing {
                    doctor = existing
                    people = Set(existing.personIds)
                } else {
                    people = [defaultPersonId]
                }
            }
        }
    }
}

import SwiftUI

/// Ajout ou modification d'une taille.
struct SizeEditor: View {
    let person: Person
    let existing: SizeEntry?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var label = ""
    @State private var value = ""
    @State private var detail = ""
    @State private var confirmDelete = false
    @FocusState private var valueFocused: Bool

    private var templates: [SizeTemplate] {
        let all = person.isChild ? SizeTemplates.child : SizeTemplates.adult
        let used = Set(person.sizes.map { $0.label.lowercased() })
        return all.filter { !used.contains($0.label.lowercased()) }
    }

    private var hint: String {
        (SizeTemplates.adult + SizeTemplates.child).first { $0.label == label }?.hint ?? "Taille"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if existing == nil {
                        Text("Quoi ?").font(theme.typography.headline(15)).foregroundStyle(theme.secondaryText)
                        FlowLayout(spacing: 8) {
                            ForEach(templates) { template in
                                Button {
                                    withAnimation(.snappy) { label = template.label }
                                    valueFocused = true
                                } label: {
                                    Text(template.label)
                                        .font(theme.typography.body(15))
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(
                                            label == template.label ? theme.text : theme.surface,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(label == template.label ? theme.background : theme.text)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        field("Ou un autre nom", text: $label)
                    } else {
                        Text(label).font(theme.typography.display(36))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Taille").font(theme.typography.headline(15)).foregroundStyle(theme.secondaryText)
                        TextField(hint, text: $value)
                            .font(theme.typography.number(44))
                            .focused($valueFocused)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if let previous = existing?.value, !value.isEmpty, value != previous {
                            Text("L'ancienne taille (\(previous)) sera gardée en mémoire.")
                                .font(theme.typography.caption(13))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    field("Note (coupe, marque, à racheter…)", text: $detail)

                    if existing != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Supprimer cette taille", systemImage: "trash")
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(20)
            }
            .themedBackground()
            .navigationTitle(existing == nil ? "Nouvelle taille · \(person.firstName)" : person.firstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Supprimer cette taille ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { store.deleteSize(existing.id, personId: person.id) }
                    dismiss()
                }
            }
            .onAppear {
                if let existing {
                    label = existing.label
                    value = existing.value
                    detail = existing.detail ?? ""
                    valueFocused = true
                }
            }
        }
        .presentationDetents([.large])
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(theme.typography.body(17))
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func save() {
        let newValue = value.trimmingCharacters(in: .whitespaces)
        var previous = existing?.previousValue
        if let old = existing?.value, old != newValue { previous = old }
        let entry = SizeEntry(
            id: existing?.id ?? UUID().uuidString,
            label: label.trimmingCharacters(in: .whitespaces),
            value: newValue,
            detail: detail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : detail.trimmingCharacters(in: .whitespaces),
            previousValue: previous,
            updatedAt: .now,
            updatedBy: store.currentUser?.firstName ?? ""
        )
        store.saveSize(entry, personId: person.id)
        dismiss()
    }
}

/// Ajout ou modification d'une personne.
struct PersonEditor: View {
    let existing: Person?
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var firstName = ""
    @State private var colorHex: UInt32 = MemberColors.all[0]
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -5, to: .now) ?? .now
    @State private var bloodType = ""
    @State private var allergies: [String] = []
    @State private var notes: [String] = []
    @State private var newAllergy = ""
    @State private var newNote = ""
    @State private var confirmDelete = false

    private let bloodTypes = ["", "O+", "O−", "A+", "A−", "B+", "B−", "AB+", "AB−"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Prénom", text: $firstName)
                    ColorRow(selection: $colorHex)
                }
                Section {
                    Toggle("Date de naissance", isOn: $hasBirthDate.animation())
                    if hasBirthDate {
                        DatePicker("Née / né le", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                    }
                    Picker("Groupe sanguin", selection: $bloodType) {
                        ForEach(bloodTypes, id: \.self) { Text($0.isEmpty ? "Inconnu" : $0).tag($0) }
                    }
                }
                Section("Allergies") {
                    ForEach(allergies, id: \.self) { Text($0) }
                        .onDelete { allergies.remove(atOffsets: $0) }
                    HStack {
                        TextField("Ajouter une allergie", text: $newAllergy)
                            .onSubmit(addAllergy)
                        Button("Ajouter", action: addAllergy).disabled(newAllergy.isEmpty)
                    }
                }
                Section {
                    ForEach(notes, id: \.self) { Text($0) }
                        .onDelete { notes.remove(atOffsets: $0) }
                    HStack {
                        TextField("Ajouter une note", text: $newNote)
                            .onSubmit(addNote)
                        Button("Ajouter", action: addNote).disabled(newNote.isEmpty)
                    }
                } header: {
                    Text("À savoir")
                } footer: {
                    Text("Doudou, peurs, habitudes, traitement… tout ce qui est utile à la personne qui garde.")
                }
                if existing != nil {
                    Section {
                        Button("Retirer de la tribu", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Nouvelle personne" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Retirer \(firstName) de la tribu ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Retirer", role: .destructive) {
                    if let existing { store.deletePerson(existing.id) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let existing else {
            colorHex = MemberColors.next(after: store.people.map(\.colorHex))
            return
        }
        firstName = existing.firstName
        colorHex = existing.colorHex
        hasBirthDate = existing.birthDate != nil
        if let date = existing.birthDate { birthDate = date }
        bloodType = existing.bloodType ?? ""
        allergies = existing.allergies
        notes = existing.notes
    }

    private func addAllergy() {
        let value = newAllergy.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !allergies.contains(value) else { return }
        allergies.append(value)
        newAllergy = ""
    }

    private func addNote() {
        let value = newNote.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !notes.contains(value) else { return }
        notes.append(value)
        newNote = ""
    }

    private func save() {
        addAllergy()
        addNote()
        let person = Person(
            id: existing?.id ?? UUID().uuidString,
            linkedUid: existing?.linkedUid,
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            colorHex: colorHex,
            birthDate: hasBirthDate ? birthDate : nil,
            bloodType: bloodType.isEmpty ? nil : bloodType,
            allergies: allergies,
            notes: notes,
            sizes: existing?.sizes ?? [],
            growth: existing?.growth ?? [],
            documents: existing?.documents ?? []
        )
        store.savePerson(person)
        dismiss()
    }
}

/// Nouvelle mesure de croissance.
struct GrowthEditor: View {
    let person: Person
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var date = Date.now
    @State private var height = ""
    @State private var weight = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                LabeledContent("Taille (cm)") {
                    TextField("106", text: $height).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Poids (kg)") {
                    TextField("16,8", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Mesure · \(person.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.saveGrowth(GrowthPoint(date: date, heightCm: number(height), weightKg: number(weight)), personId: person.id)
                        dismiss()
                    }
                    .disabled(number(height) == nil && number(weight) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}

/// Disposition en lignes qui passent à la ligne quand il n'y a plus de place.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

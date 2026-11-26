import PhotosUI
import SwiftUI

/// Dépenses du compte commun : à payer, payées, budget du mois par catégorie.
struct ExpensesView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var creating = false
    @State private var editing: Expense?
    @State private var editingBudget = false

    private var t: Typography { theme.typography }
    private let cal = Calendar.current

    private var monthExpenses: [Expense] {
        store.expenses.filter { cal.isDate($0.paidAt ?? $0.issueDate, equalTo: month, toGranularity: .month) }
    }
    private var toPay: [Expense] {
        store.unpaidExpenses.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var paid: [Expense] {
        monthExpenses.filter(\.isPaid).sorted { ($0.paidAt ?? .distantPast) > ($1.paidAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ModuleHeader(title: "Dépenses", module: .depenses) { creating = true }
                summary
                budgets
                if !toPay.isEmpty {
                    section("À payer", toPay)
                }
                section("Payées en \(month.formatted(.dateTime.month(.wide).locale(Locale(identifier: "fr_BE"))))", paid)
                warranties
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { ExpenseEditor(existing: nil) }
        .sheet(item: $editing) { ExpenseEditor(existing: $0) }
        .sheet(isPresented: $editingBudget) { BudgetEditor() }
    }

    private var summary: some View {
        let spent = paid.reduce(0) { $0 + $1.amount }
        let due = toPay.reduce(0) { $0 + $1.amount }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button { withAnimation { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } } label: { Image(systemName: "chevron.left") }
                    Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE"))).capitalizedFirst)
                        .font(t.headline(13))
                    Button { withAnimation { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
                Text(Decimal(spent).euros).font(t.number(30)).contentTransition(.numericText())
                Text("dépensé").font(t.caption(12)).opacity(0.75)
            }
            .foregroundStyle(theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(for: .depenses), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("À payer").font(t.headline(13))
                Text(Decimal(due).euros).font(t.number(30)).contentTransition(.numericText())
                Text("\(toPay.count) facture\(toPay.count > 1 ? "s" : "")").font(t.caption(12)).opacity(0.75)
            }
            .foregroundStyle(theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(for: .rappels), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var budgets: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Budget du mois").font(t.title(20))
                Spacer()
                Button("Modifier") { editingBudget = true }.font(t.body(14))
            }
            if store.budgets.isEmpty {
                Text("Fixe un budget mensuel par catégorie pour suivre où va l'argent.")
                    .font(t.body(14)).foregroundStyle(theme.secondaryText)
            }
            ForEach(ExpenseCategory.allCases.filter { store.budgets[$0.rawValue] != nil }) { category in
                let limit = store.budgets[category.rawValue] ?? 0
                let spent = monthExpenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
                let ratio = limit > 0 ? spent / limit : 0
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(category.label, systemImage: category.icon).font(t.body(14))
                        Spacer()
                        Text("\(Decimal(spent).euros) / \(Decimal(limit).euros)")
                            .font(t.caption(12))
                            .foregroundStyle(ratio > 1 ? Color(hex: 0xC0392B) : theme.secondaryText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.separator)
                            Capsule()
                                .fill(ratio > 1 ? Color(hex: 0xC0392B) : (ratio > 0.8 ? Color(hex: 0xE58E26) : theme.text))
                                .frame(width: geo.size.width * min(ratio, 1))
                        }
                    }
                    .frame(height: 8)
                    .accessibilityLabel("\(category.label) : \(Int(ratio * 100)) % du budget")
                }
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
    }

    private func section(_ title: String, _ list: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(t.title(20))
            if list.isEmpty {
                EmptyState(text: "Rien pour l'instant. Touche + pour scanner ou encoder une facture.")
            }
            ForEach(list) { expense in
                Button { editing = expense } label: { ExpenseRow(expense: expense) }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var warranties: some View {
        let list = store.expenses.filter { ($0.warrantyUntil ?? .distantPast) > .now }.sorted { ($0.warrantyUntil ?? .now) < ($1.warrantyUntil ?? .now) }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Garanties").font(t.title(20))
                ForEach(list) { expense in
                    HStack {
                        Label(expense.vendor, systemImage: "checkmark.shield")
                        Spacer()
                        Text("jusqu'au \(expense.warrantyUntil?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                            .foregroundStyle(theme.secondaryText)
                    }
                    .font(t.body(14))
                }
            }
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .frame(width: 38, height: 38)
                .background(theme.color(for: .depenses).opacity(0.6), in: Circle())
                .foregroundStyle(theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.vendor).font(theme.typography.medium(16))
                Text(detail).font(theme.typography.caption(12)).foregroundStyle(late ? Color(hex: 0xC0392B) : theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Decimal(expense.amount).euros).font(theme.typography.headline(16))
                if expense.recurrence != .none {
                    Image(systemName: "repeat").font(.caption2).foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }

    private var late: Bool { !expense.isPaid && (expense.dueDate ?? .distantFuture) < .now }

    private var detail: String {
        if let paidAt = expense.paidAt {
            return "Payée le \(paidAt.formatted(date: .abbreviated, time: .omitted))\(expense.paidByName.map { " par \($0)" } ?? "")"
        }
        if let due = expense.dueDate {
            return late ? "En retard depuis le \(due.formatted(date: .abbreviated, time: .omitted))" : "À payer avant le \(due.formatted(date: .abbreviated, time: .omitted))"
        }
        return expense.category.label
    }
}

/// Encodage d'une facture : scan, lecture automatique, paiement.
struct ExpenseEditor: View {
    let existing: Expense?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var expense = Expense(vendor: "", amount: 0)
    @State private var amountText = ""
    @State private var hasDue = false
    @State private var hasWarranty = false
    @State private var image: UIImage?
    @State private var remoteImage: URL?
    @State private var scanning = false
    @State private var photoItem: PhotosPickerItem?
    @State private var reading = false
    @State private var saving = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                    } else if let remoteImage {
                        AsyncImage(url: remoteImage) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(maxHeight: 220).frame(maxWidth: .infinity)
                    }
                    HStack {
                        if DocumentScanner.isAvailable {
                            Button { scanning = true } label: { Label("Scanner", systemImage: "doc.viewfinder") }
                        }
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Photo", systemImage: "photo")
                        }
                    }
                    .buttonStyle(.borderless)
                    if reading {
                        Label("Lecture de la facture…", systemImage: "text.viewfinder").foregroundStyle(theme.secondaryText)
                    }
                } footer: {
                    Text("Tribu lit le montant, les dates, l'IBAN et la communication structurée. Vérifie avant d'enregistrer.")
                }

                Section {
                    TextField("Fournisseur", text: $expense.vendor)
                    HStack {
                        TextField("Montant", text: $amountText).keyboardType(.decimalPad)
                        Text("€").foregroundStyle(theme.secondaryText)
                    }
                    Picker("Catégorie", selection: $expense.category) {
                        ForEach(ExpenseCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    DatePicker("Date", selection: $expense.issueDate, displayedComponents: .date)
                    Toggle("Échéance de paiement", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Payer avant le", selection: Binding(get: { expense.dueDate ?? .now }, set: { expense.dueDate = $0 }), displayedComponents: .date)
                    }
                    Picker("Revient", selection: $expense.recurrence) {
                        ForEach(Recurrence.allCases.filter { $0 != .daily && $0 != .weekly }) { Text($0.label).tag($0) }
                    }
                }
                .environment(\.locale, Locale(identifier: "fr_BE"))

                if !expense.iban.isEmpty || !expense.communication.isEmpty || existing == nil {
                    Section("Virement") {
                        CopyRow(label: "IBAN", value: $expense.iban)
                        CopyRow(label: "Communication", value: $expense.communication)
                    }
                }

                Section {
                    Toggle("Payée", isOn: Binding(
                        get: { expense.paidAt != nil },
                        set: { paid in
                            expense.paidAt = paid ? .now : nil
                            expense.paidByName = paid ? store.authorName : nil
                        }
                    ))
                    Toggle("Garantie", isOn: $hasWarranty.animation())
                    if hasWarranty {
                        DatePicker("Jusqu'au", selection: Binding(get: { expense.warrantyUntil ?? .now }, set: { expense.warrantyUntil = $0 }), displayedComponents: .date)
                    }
                    TextField("Note", text: $expense.note, axis: .vertical)
                }
                .environment(\.locale, Locale(identifier: "fr_BE"))

                if existing != nil {
                    Section { Button("Supprimer", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Nouvelle dépense" : expense.vendor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") { Task { await save() } }
                            .disabled(expense.vendor.trimmingCharacters(in: .whitespaces).isEmpty || amount == nil)
                    }
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { scanned in handle(scanned) }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        await MainActor.run { handle(picked) }
                    }
                }
            }
            .confirmationDialog("Supprimer cette dépense ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            }
            .task { await load() }
        }
    }

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private func load() async {
        guard let existing else { return }
        expense = existing
        amountText = IngredientParser.format(existing.amount)
        hasDue = existing.dueDate != nil
        hasWarranty = existing.warrantyUntil != nil
        if !existing.imagePath.isEmpty {
            remoteImage = await store.remote?.imageURL(path: existing.imagePath)
        }
    }

    private func handle(_ scanned: UIImage) {
        image = scanned
        reading = true
        Task {
            let result = await InvoiceReader.read(scanned)
            await MainActor.run {
                withAnimation {
                    if expense.vendor.isEmpty { expense.vendor = result.vendor }
                    if amountText.isEmpty, let value = result.amount { amountText = IngredientParser.format(value) }
                    if let issue = result.issueDate { expense.issueDate = issue }
                    if let due = result.dueDate { expense.dueDate = due; hasDue = true }
                    if expense.iban.isEmpty { expense.iban = result.iban }
                    if expense.communication.isEmpty { expense.communication = result.communication }
                    reading = false
                }
            }
        }
    }

    private func save() async {
        guard let amount else { return }
        saving = true
        expense.amount = amount
        if !hasDue { expense.dueDate = nil }
        if !hasWarranty { expense.warrantyUntil = nil }
        if existing == nil { expense.createdByName = store.authorName }
        if let image, let data = image.jpegData(compressionQuality: 0.7), let remote = store.remote {
            if let path = try? await remote.uploadImage(data, name: "expenses/\(expense.id).jpg") {
                expense.imagePath = path
            }
        }
        let wasPaid = existing?.isPaid ?? false
        store.save(expense)
        if existing == nil {
            store.post("a ajouté la facture \(expense.vendor) (\(Decimal(amount).euros))", icon: "doc.text")
        } else if !wasPaid && expense.isPaid {
            store.post("a payé \(expense.vendor) (\(Decimal(amount).euros))", icon: "checkmark.circle")
        }
        // Facture récurrente payée : on prépare la suivante.
        if !wasPaid, expense.isPaid, expense.recurrence != .none, let component = expense.recurrence.component {
            var next = Expense(vendor: expense.vendor, amount: expense.amount, category: expense.category,
                               issueDate: Calendar.current.date(byAdding: component, value: 1, to: expense.issueDate) ?? .now,
                               iban: expense.iban, communication: "", recurrence: expense.recurrence, createdByName: store.authorName)
            next.dueDate = expense.dueDate.flatMap { Calendar.current.date(byAdding: component, value: 1, to: $0) }
            store.save(next)
        }
        saving = false
        dismiss()
    }
}

/// Ligne avec un bouton pour copier la valeur (IBAN, communication).
struct CopyRow: View {
    let label: String
    @Binding var value: String
    @State private var copied = false

    var body: some View {
        HStack {
            TextField(label, text: $value)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
            if !value.isEmpty {
                Button {
                    UIPasteboard.general.string = value.replacingOccurrences(of: " ", with: "")
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
                .accessibilityLabel("Copier")
            }
        }
    }
}

/// Budget mensuel par catégorie.
struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var values: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ExpenseCategory.allCases) { category in
                        HStack {
                            Label(category.label, systemImage: category.icon)
                            Spacer()
                            TextField("—", text: Binding(get: { values[category.rawValue] ?? "" }, set: { values[category.rawValue] = $0 }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("€").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Laisse vide pour ne pas suivre une catégorie.")
                }
            }
            .navigationTitle("Budget mensuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        var budgets: [String: Double] = [:]
                        for (key, text) in values {
                            if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 { budgets[key] = value }
                        }
                        store.saveBudgets(budgets)
                        dismiss()
                    }
                }
            }
            .onAppear {
                values = store.budgets.mapValues { IngredientParser.format($0) }
            }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

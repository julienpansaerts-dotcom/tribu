import SwiftUI

/// Onglet Cuisine : courses, menu de la semaine et recettes.
struct CuisineView: View {
    enum Section: String, CaseIterable, Identifiable {
        case courses = "Courses", menu = "Menu", recettes = "Recettes"
        var id: String { rawValue }
    }

    @Environment(\.theme) private var theme
    @State private var section: Section = Section(rawValue: UserDefaults.standard.string(forKey: "tribu.cuisine") ?? "") ?? .courses

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Cuisine", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)
                switch section {
                case .courses: ShoppingListView()
                case .menu: MenuWeekView()
                case .recettes: RecipeListView()
                }
            }
            .themedBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipeId: $0.id) }
        }
    }
}

// MARK: - Image de recette

struct RecipeImage: View {
    let url: String
    var height: CGFloat = 120
    var corner: CGFloat = 12

    var body: some View {
        Color(hex: 0xC98E5A)
            .frame(height: height)
            .overlay {
                if let link = URL(string: url), !url.isEmpty {
                    AsyncImage(url: link, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill().transition(.opacity)
                        default: Image(systemName: "fork.knife").font(.title2).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                } else {
                    Image(systemName: "fork.knife").font(.title2).foregroundStyle(.white.opacity(0.8))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Liste des recettes

struct RecipeListView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var link = ""
    @State private var importing = false
    @State private var importError: String?
    @State private var query = ""
    @State private var showManual = false
    @State private var favoritesOnly = false

    private var t: Typography { theme.typography }

    private var filtered: [Recipe] {
        store.recipes
            .filter { !favoritesOnly || $0.favorite }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.ingredients.contains { $0.localizedCaseInsensitiveContains(query) } }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: "Recettes", module: .repas) { showManual = true }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(theme.secondaryText)
                        TextField("Coller le lien d'une recette", text: $link)
                            .font(t.body(16))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(importLink)
                        if importing {
                            ProgressView()
                        } else if !link.isEmpty {
                            Button("Ajouter", action: importLink).font(t.headline(15))
                        } else {
                            Button {
                                if let pasted = UIPasteboard.general.string { link = pasted; importLink() }
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .accessibilityLabel("Coller")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
                    if importing {
                        Text("Lecture de la recette : image, ingrédients, étapes…")
                            .font(t.caption(13)).foregroundStyle(theme.secondaryText)
                    }
                    if let importError {
                        Text(importError).font(t.caption(13)).foregroundStyle(Color(hex: 0xD9480F))
                    }
                }

                HStack {
                    TextField("Chercher une recette ou un ingrédient", text: $query)
                        .font(t.body(15))
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(theme.surface.opacity(0.6), in: Capsule())
                    Button {
                        withAnimation { favoritesOnly.toggle() }
                    } label: {
                        Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Favoris seulement")
                }

                if filtered.isEmpty {
                    EmptyState(text: "Colle le lien d'une recette trouvée sur internet : Tribu récupère tout seul la photo, les ingrédients et les étapes.")
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(filtered) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showManual) { RecipeEditor(existing: nil) }
    }

    private func importLink() {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !importing else { return }
        importing = true
        importError = nil
        Task {
            do {
                let recipe = try await RecipeImporter.importRecipe(from: value, author: store.authorName)
                await MainActor.run {
                    withAnimation(.spring) { store.save(recipe) }
                    store.post("a ajouté la recette « \(recipe.title) »", icon: "fork.knife")
                    link = ""
                    importing = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    importing = false
                }
            }
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipeImage(url: recipe.imageURL, height: 118, corner: min(theme.cornerRadius + 4, 16))
                .overlay(alignment: .topTrailing) {
                    if recipe.favorite {
                        Image(systemName: "heart.fill").font(.caption).foregroundStyle(.white).padding(8)
                    }
                }
            Text(recipe.title)
                .font(theme.typography.headline(15))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text([recipe.totalMinutes.map { "\($0) min" }, "\(recipe.servings) pers.", recipe.host.isEmpty ? nil : recipe.host]
                .compactMap { $0 }.joined(separator: " · "))
                .font(theme.typography.caption(12))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - Fiche recette

struct RecipeDetailView: View {
    let recipeId: String
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(FamilyStore.self) private var store
    @State private var servings = 4
    @State private var cooking = false
    @State private var planning = false
    @State private var editing = false
    @State private var doneSteps: Set<Int> = []

    private var t: Typography { theme.typography }

    var body: some View {
        if let recipe = store.recipes.first(where: { $0.id == recipeId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RecipeImage(url: recipe.imageURL, height: 260, corner: 0)
                        .padding(.horizontal, -20)
                    Text(recipe.title).font(t.display(34))
                    HStack(spacing: 14) {
                        if let minutes = recipe.totalMinutes { Label("\(minutes) min", systemImage: "clock") }
                        if !recipe.host.isEmpty {
                            Button { if let url = URL(string: recipe.url) { openURL(url) } } label: {
                                Label(recipe.host, systemImage: "safari")
                            }
                        }
                    }
                    .font(t.caption(14))
                    .foregroundStyle(theme.secondaryText)

                    HStack(spacing: 10) {
                        Button {
                            planning = true
                        } label: {
                            Label("Au menu", systemImage: "calendar.badge.plus")
                                .font(t.headline(16))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(theme.text, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(theme.background)
                        }
                        Button {
                            var updated = recipe
                            updated.favorite.toggle()
                            store.save(updated)
                        } label: {
                            Image(systemName: recipe.favorite ? "heart.fill" : "heart")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .sensoryFeedback(.impact, trigger: recipe.favorite)
                        Button {
                            cooking.toggle()
                        } label: {
                            Image(systemName: cooking ? "flame.fill" : "flame")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(cooking ? theme.color(for: .courses) : theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .accessibilityLabel("Mode cuisine : l'écran reste allumé")
                    }
                    .buttonStyle(.plain)

                    if !recipe.ingredients.isEmpty {
                        HStack {
                            Text("Ingrédients").font(t.title(22))
                            Spacer()
                            Stepper(value: $servings, in: 1...20) {
                                Text("\(servings) pers.").font(t.headline(15)).contentTransition(.numericText())
                            }
                            .fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(scaledIngredients(recipe), id: \.raw) { ingredient in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(ingredient.quantityText ?? "—")
                                        .font(t.headline(15))
                                        .frame(width: 92, alignment: .leading)
                                        .contentTransition(.numericText())
                                    Text(ingredient.name).font(t.body(16))
                                }
                            }
                        }
                    }

                    if !recipe.steps.isEmpty {
                        Text("Étapes").font(t.title(22)).padding(.top, 6)
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            Button {
                                withAnimation(.snappy) {
                                    if doneSteps.contains(index) { doneSteps.remove(index) } else { doneSteps.insert(index) }
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(t.headline(15))
                                        .frame(width: 30, height: 30)
                                        .background(doneSteps.contains(index) ? theme.text : theme.color(for: .repas), in: Circle())
                                        .foregroundStyle(doneSteps.contains(index) ? theme.background : theme.ink)
                                    Text(step)
                                        .font(t.body(cooking ? 19 : 16))
                                        .foregroundStyle(theme.text.opacity(doneSteps.contains(index) ? 0.45 : 1))
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)
            .themedBackground()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Modifier", systemImage: "pencil") { editing = true }
                        Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(recipe) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear { servings = recipe.servings }
            .onChange(of: cooking) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .sheet(isPresented: $planning) { AddToMenuSheet(recipe: recipe, servings: servings) }
            .sheet(isPresented: $editing) { RecipeEditor(existing: recipe) }
        }
    }

    private func scaledIngredients(_ recipe: Recipe) -> [ParsedIngredient] {
        let factor = Double(servings) / Double(max(recipe.servings, 1))
        return recipe.ingredients.map { IngredientParser.parse($0).scaled(by: factor) }
    }
}

// MARK: - Ajouter au menu

struct AddToMenuSheet: View {
    let recipe: Recipe
    @State var servings: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var date = Date.now
    @State private var excluded: Set<String> = []
    @State private var addToShopping = true

    private var ingredients: [ParsedIngredient] {
        let factor = Double(servings) / Double(max(recipe.servings, 1))
        return recipe.ingredients.map { IngredientParser.parse($0).scaled(by: factor) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Jour", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "fr_BE"))
                    Stepper("\(servings) personnes", value: $servings, in: 1...20)
                }
                if !recipe.ingredients.isEmpty {
                    Section {
                        Toggle("Ajouter aux courses", isOn: $addToShopping.animation())
                        if addToShopping {
                            ForEach(ingredients) { ingredient in
                                let on = !excluded.contains(ingredient.raw)
                                Button {
                                    if on { excluded.insert(ingredient.raw) } else { excluded.remove(ingredient.raw) }
                                } label: {
                                    HStack {
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(on ? theme.accent : theme.secondaryText)
                                        Text(ingredient.name)
                                        Spacer()
                                        Text(ingredient.quantityText ?? "").foregroundStyle(theme.secondaryText)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } footer: {
                        Text("Décoche ce que tu as déjà. Les articles déjà sur la liste sont additionnés.")
                    }
                }
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter", action: save) }
            }
        }
    }

    private func save() {
        let meal = Meal(id: Meal.key(for: date), recipeId: recipe.id, title: recipe.title, imageURL: recipe.imageURL,
                        minutes: recipe.totalMinutes ?? 0, servings: servings)
        store.save(meal)
        if addToShopping {
            store.addIngredients(ingredients.filter { !excluded.contains($0.raw) }, origin: recipe.title)
        }
        dismiss()
    }
}

// MARK: - Saisie manuelle

struct RecipeEditor: View {
    let existing: Recipe?
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilyStore.self) private var store
    @State private var title = ""
    @State private var url = ""
    @State private var imageURL = ""
    @State private var servings = 4
    @State private var minutes = ""
    @State private var ingredients = ""
    @State private var steps = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom de la recette", text: $title)
                    Stepper("\(servings) personnes", value: $servings, in: 1...20)
                    TextField("Temps total (minutes)", text: $minutes).keyboardType(.numberPad)
                }
                Section("Ingrédients, un par ligne") {
                    TextField("200 g de farine", text: $ingredients, axis: .vertical).lineLimit(4...)
                }
                Section("Étapes, une par ligne") {
                    TextField("Préchauffer le four…", text: $steps, axis: .vertical).lineLimit(4...)
                }
                Section("Liens (facultatif)") {
                    TextField("Lien de la recette", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Lien de la photo", text: $imageURL).keyboardType(.URL).textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(existing == nil ? "Nouvelle recette" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let existing else { return }
                title = existing.title
                url = existing.url
                imageURL = existing.imageURL
                servings = existing.servings
                minutes = existing.totalMinutes.map(String.init) ?? ""
                ingredients = existing.ingredients.joined(separator: "\n")
                steps = existing.steps.joined(separator: "\n")
            }
        }
    }

    private func save() {
        func lines(_ text: String) -> [String] {
            text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var recipe = existing ?? Recipe(title: "", createdByName: store.authorName)
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.url = url
        recipe.imageURL = imageURL
        recipe.servings = servings
        recipe.totalMinutes = Int(minutes)
        recipe.ingredients = lines(ingredients)
        recipe.steps = lines(steps)
        store.save(recipe)
        dismiss()
    }
}

// MARK: - Menu de la semaine

struct MenuWeekView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var weekOffset = 0
    @State private var choosingFor: Date?

    private var t: Typography { theme.typography }

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // lundi = 0
        let monday = cal.date(byAdding: .day, value: -weekday + weekOffset * 7, to: today) ?? today
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu").font(t.display(42))
                        Text("Semaine \(Calendar(identifier: .iso8601).component(.weekOfYear, from: days[0]))")
                            .font(t.body(15)).foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { weekOffset -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                    Button { withAnimation(.snappy) { weekOffset += 1 } } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                }
                .padding(.top, 8)

                ForEach(days, id: \.self) { day in
                    dayRow(day)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .sheet(item: Binding(get: { choosingFor.map { DayChoice(date: $0) } }, set: { choosingFor = $0?.date })) { choice in
            RecipeChooser(date: choice.date)
        }
    }

    private func dayRow(_ day: Date) -> some View {
        let meal = store.meals.first { $0.id == Meal.key(for: day) }
        let isToday = Calendar.current.isDateInToday(day)
        return HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_BE"))).uppercased())
                    .font(t.caption(11))
                Text(day.formatted(.dateTime.day())).font(t.number(22))
            }
            .frame(width: 46)
            .foregroundStyle(isToday ? theme.accent : (theme.style != .couleurs && isToday ? theme.ink : theme.text))

            if let meal {
                NavigationLink(value: store.recipes.first { $0.id == meal.recipeId } ?? Recipe(title: meal.title)) {
                    HStack(spacing: 12) {
                        RecipeImage(url: meal.imageURL, height: 52, corner: 10).frame(width: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.title).font(t.headline(16)).lineLimit(2).multilineTextAlignment(.leading)
                            Text("\(meal.servings) pers.\(meal.minutes > 0 ? " · \(meal.minutes) min" : "")")
                                .font(t.caption(12)).foregroundStyle(theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Changer", systemImage: "arrow.triangle.2.circlepath") { choosingFor = day }
                    Button("Retirer du menu", systemImage: "trash", role: .destructive) { store.delete(meal) }
                }
            } else {
                Button {
                    choosingFor = day
                } label: {
                    Label("Choisir un repas", systemImage: "plus")
                        .font(t.body(15))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 12)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.separator, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(isToday ? theme.color(for: .repas).opacity(theme.style == .couleurs ? 0.5 : 1) : theme.surface,
                    in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 16), style: .continuous))
        .foregroundStyle(isToday && theme.style != .couleurs ? theme.ink : theme.text)
    }
}

private struct DayChoice: Identifiable {
    let date: Date
    var id: Date { date }
}

/// Choix d'une recette (ou d'un repas libre) pour un jour.
struct RecipeChooser: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var freeText = ""
    @State private var chosen: Recipe?

    var body: some View {
        NavigationStack {
            List {
                Section("Repas libre") {
                    HStack {
                        TextField("Pâtes, restes, pizza…", text: $freeText)
                        Button("OK") {
                            store.save(Meal(id: Meal.key(for: date), title: freeText.trimmingCharacters(in: .whitespaces)))
                            dismiss()
                        }
                        .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let random = store.recipes.filter(\.favorite).randomElement() ?? store.recipes.randomElement() {
                    Section {
                        Button {
                            chosen = random
                        } label: {
                            Label("Au hasard : \(random.title)", systemImage: "dice")
                        }
                    }
                }
                Section("Recettes") {
                    ForEach(store.recipes.sorted { ($0.favorite ? 0 : 1, $0.title) < ($1.favorite ? 0 : 1, $1.title) }) { recipe in
                        Button {
                            chosen = recipe
                        } label: {
                            HStack(spacing: 12) {
                                RecipeImage(url: recipe.imageURL, height: 44, corner: 8).frame(width: 44)
                                Text(recipe.title).foregroundStyle(theme.text)
                                Spacer()
                                if recipe.favorite { Image(systemName: "heart.fill").foregroundStyle(theme.accent) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE"))).capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .sheet(item: $chosen) { recipe in
                AddToMenuSheetForDate(recipe: recipe, date: date) { added in
                    chosen = nil
                    if added { dismiss() }
                }
            }
        }
    }
}

/// Variante de l'ajout au menu avec une date déjà choisie.
struct AddToMenuSheetForDate: View {
    let recipe: Recipe
    let date: Date
    let onDone: (Bool) -> Void
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var servings = 4
    @State private var addToShopping = true
    @State private var excluded: Set<String> = []

    private var ingredients: [ParsedIngredient] {
        let factor = Double(servings) / Double(max(recipe.servings, 1))
        return recipe.ingredients.map { IngredientParser.parse($0).scaled(by: factor) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(servings) personnes", value: $servings, in: 1...20)
                if !recipe.ingredients.isEmpty {
                    Section {
                        Toggle("Ajouter aux courses", isOn: $addToShopping.animation())
                        if addToShopping {
                            ForEach(ingredients) { ingredient in
                                let on = !excluded.contains(ingredient.raw)
                                Button {
                                    if on { excluded.insert(ingredient.raw) } else { excluded.remove(ingredient.raw) }
                                } label: {
                                    HStack {
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(on ? theme.accent : theme.secondaryText)
                                        Text(ingredient.name)
                                        Spacer()
                                        Text(ingredient.quantityText ?? "").foregroundStyle(theme.secondaryText)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { onDone(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        store.save(Meal(id: Meal.key(for: date), recipeId: recipe.id, title: recipe.title, imageURL: recipe.imageURL,
                                        minutes: recipe.totalMinutes ?? 0, servings: servings))
                        if addToShopping {
                            store.addIngredients(ingredients.filter { !excluded.contains($0.raw) }, origin: recipe.title)
                        }
                        onDone(true)
                    }
                }
            }
            .onAppear { servings = recipe.servings }
        }
    }
}

import SwiftUI

/// Liste de courses partagée en temps réel.
struct ShoppingListView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var newItem = ""
    @FocusState private var addFocused: Bool

    private var t: Typography { theme.typography }
    private var remaining: [ShoppingItem] { store.shopping.filter { !$0.isChecked } }
    private var inCart: [ShoppingItem] { store.shopping.filter { $0.isChecked } }

    private let usual = ["Lait", "Pain", "Œufs", "Bananes", "Yaourts", "Beurre", "Pommes", "Café"]

    private var usualSuggestions: [String] {
        let present = Set(remaining.map { $0.name.lowercased() })
        return usual.filter { !present.contains($0.lowercased()) }
    }

    var body: some View {
        List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
                    addField
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    usualChips
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 0))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if remaining.isEmpty && inCart.isEmpty {
                    Text("La liste est vide. Ajoute ce qu'il manque : tout le monde le verra tout de suite.")
                        .font(t.body(16))
                        .foregroundStyle(theme.secondaryText)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(remaining) { item in
                        row(item)
                    }
                    .onDelete { offsets in store.deleteShopping(offsets.map { remaining[$0] }) }
                }
                .listRowBackground(theme.surface)

                if !inCart.isEmpty {
                    Section {
                        ForEach(inCart) { item in
                            row(item)
                        }
                        .onDelete { offsets in store.deleteShopping(offsets.map { inCart[$0] }) }
                    } header: {
                        HStack {
                            Text("Dans le panier · \(inCart.count)")
                            Spacer()
                            Button("Vider") {
                                withAnimation { store.deleteShopping(inCart) }
                            }
                        }
                        .font(t.headline(13))
                        .foregroundStyle(theme.secondaryText)
                    }
                    .listRowBackground(theme.surface.opacity(0.6))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .themedBackground()
            .animation(.snappy, value: store.shopping)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Courses").font(t.display(44))
            Text("\(remaining.count) article\(remaining.count > 1 ? "s" : "") à prendre")
                .font(t.body(15))
                .foregroundStyle(theme.secondaryText)
                .contentTransition(.numericText())
        }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").foregroundStyle(theme.secondaryText)
            TextField("Ajouter un article", text: $newItem)
                .font(t.body(17))
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit(add)
            if !newItem.isEmpty {
                Button("Ajouter", action: add)
                    .font(t.headline(15))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(theme.color(for: .courses).opacity(theme.style == .couleurs ? 0.25 : 1), in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
        // Sur un fond de couleur plein, le texte reste foncé, même en mode sombre.
        .foregroundStyle(theme.style == .couleurs ? theme.text : theme.ink)
    }

    private var usualChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(usualSuggestions, id: \.self) { name in
                    Button {
                        store.addShopping(name: name, quantity: nil)
                    } label: {
                        Text(name)
                            .font(t.body(14))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .overlay(Capsule().strokeBorder(theme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 16)
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            withAnimation(.snappy) { store.toggleShopping(item) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.text.opacity(item.isChecked ? 0 : 0.6), lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.text)
                        .opacity(item.isChecked ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.background)
                        .opacity(item.isChecked ? 1 : 0)
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    StrikeText(text: item.name, isStruck: item.isChecked, font: t.body(17), color: theme.text)
                    if let origin = item.origin {
                        Text(origin).font(t.caption(12)).foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
                if let quantity = item.quantity {
                    Text(quantity).font(t.headline(14)).foregroundStyle(theme.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.isChecked)
    }

    private func add() {
        store.addShopping(name: newItem, quantity: nil)
        newItem = ""
        addFocused = true
    }
}

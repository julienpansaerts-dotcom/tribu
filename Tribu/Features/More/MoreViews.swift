import SwiftUI

/// Onglet « Plus » : les autres modules et les réglages.
struct MoreView: View {
    @Environment(\.theme) private var theme

    private var t: Typography { theme.typography }

    private struct ModuleEntry: Identifiable {
        let title: String
        let icon: String
        let module: Module
        var id: String { title }
    }

    private let modules: [ModuleEntry] = [
        ModuleEntry(title: "Rappels", icon: "bell", module: .rappels),
        ModuleEntry(title: "Tâches et idées", icon: "checklist", module: .taches),
        ModuleEntry(title: "Activités", icon: "figure.and.child.holdinghands", module: .activites),
        ModuleEntry(title: "Dépenses", icon: "eurosign", module: .depenses),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plus").font(t.display(44)).padding(.top, 12).padding(.bottom, 6)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(modules) { entry in
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: entry.icon).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).font(t.headline(16))
                                    Text("Bientôt").font(t.caption(12)).opacity(0.7)
                                }
                            }
                            .foregroundStyle(theme.ink)
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .background(theme.color(for: entry.module), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
                        }
                    }

                    Text("Réglages").font(t.title(22)).padding(.top, 18)
                    NavigationLink {
                        StylePickerView()
                    } label: {
                        settingsRow(icon: "paintpalette", title: "Style de l'app", value: theme.style.name)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .themedBackground()
        }
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24)
            Text(title).font(t.body(16))
            Spacer()
            Text(value).font(t.caption(13)).foregroundStyle(theme.secondaryText).lineLimit(1)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.secondaryText)
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }
}

/// Choix de l'ambiance visuelle. Le changement s'applique instantanément à toute l'app.
struct StylePickerView: View {
    @Environment(\.theme) private var theme
    @AppStorage("tribu.style") private var styleRaw: String = TribuStyle.couleurs.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Style de l'app").font(theme.typography.display(38)).padding(.top, 8)
                Text("Chacun choisit le sien : il ne change que sur ton iPhone.")
                    .font(theme.typography.body(15))
                    .foregroundStyle(theme.secondaryText)
                ForEach(TribuStyle.allCases) { style in
                    StyleCard(style: style, isSelected: style.rawValue == styleRaw) {
                        withAnimation(.smooth(duration: 0.45)) { styleRaw = style.rawValue }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: styleRaw)
    }
}

/// Aperçu d'une ambiance, dessiné avec ses propres couleurs et polices.
private struct StyleCard: View {
    let style: TribuStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let preview = Theme.make(style)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach([Module.courses, .rappels, .famille, .agenda, .repas], id: \.self) { module in
                        RoundedRectangle(cornerRadius: min(preview.cornerRadius, 8), style: .continuous)
                            .fill(preview.color(for: module))
                            .frame(height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: min(preview.cornerRadius, 8), style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.06))
                            )
                    }
                }
                Text(style.name)
                    .font(style == .frigo ? preview.typography.hand(30) : preview.typography.display(26))
                    .foregroundStyle(preview.text)
                Text(style.summary)
                    .font(preview.typography.body(14))
                    .foregroundStyle(preview.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(preview.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? preview.text : preview.separator, lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(preview.text, preview.background)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 1 : 0.98)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

import SwiftUI

/// Pastille ronde avec l'initiale d'une personne, dans sa couleur.
struct Avatar: View {
    let person: Person
    var size: CGFloat = 38
    @Environment(\.theme) private var theme

    var body: some View {
        Circle()
            .fill(Color(hex: person.colorHex))
            .frame(width: size, height: size)
            .overlay {
                Text(person.initial)
                    .font(theme.typography.headline(size * 0.4))
                    .foregroundStyle(Color(hex: 0xFFFFFF))
            }
            .accessibilityLabel(person.firstName)
    }
}

/// Fond plein écran de l'ambiance courante.
struct ThemedBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.background.ignoresSafeArea())
            .foregroundStyle(theme.text)
    }
}

extension View {
    func themedBackground() -> some View { modifier(ThemedBackground()) }
}

/// Apparition en douceur, décalée selon l'ordre de l'élément.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// Écran d'attente pour les modules des prochains jalons.
struct ComingSoonView: View {
    let title: String
    let module: Module
    let lines: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(theme.typography.display(44))
                    .padding(.top, 24)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Bientôt dans Tribu")
                        .font(theme.typography.headline(14))
                        .foregroundStyle(theme.ink.opacity(0.75))
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(theme.ink).frame(width: 6, height: 6)
                            Text(line).font(theme.typography.body(17))
                        }
                        .foregroundStyle(theme.ink)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color(for: module), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            }
            .padding(.horizontal, 20)
        }
        .themedBackground()
    }
}

extension Decimal {
    var euros: String {
        formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_BE")))
    }
}

extension Date {
    var tribuDayTitle: String {
        formatted(.dateTime.weekday(.wide).day().locale(Locale(identifier: "fr_BE"))).capitalizedFirst
    }

    var tribuLongDate: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE"))).capitalizedFirst
    }
}

extension String {
    /// Majuscule sur la première lettre seulement (« Mercredi 25 novembre »).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Les trois dernières lignes du fil d'activité, pour l'écran d'accueil.
struct FeedPreview: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    var body: some View {
        let entries = Array(store.feed.sorted { $0.createdAt > $1.createdAt }.prefix(3))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Du côté de la tribu").font(theme.typography.headline(14)).foregroundStyle(theme.secondaryText)
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        (Text(entry.actorName).font(theme.typography.headline(14)) + Text(" " + entry.text).font(theme.typography.body(14)))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text(entry.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow).locale(Locale(identifier: "fr_BE"))))
                            .font(theme.typography.caption(11))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

extension Date {
    /// Heure au format belge, toujours sur 24 h (« 09:00 »).
    var hm: String {
        formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "fr_BE")))
    }
}

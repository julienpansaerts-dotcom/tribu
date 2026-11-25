import SwiftUI

/// L'écran d'accueil change complètement de mise en page selon l'ambiance choisie.
struct HomeView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            switch theme.style {
            case .frigo: FrigoHomeView()
            case .album: AlbumHomeView()
            case .couleurs: CouleursHomeView()
            }
        }
        .id(theme.style)
        .transition(.opacity)
    }
}

/// Bouton rond « c'est fait » avec coche animée et retour haptique.
struct DoneButton: View {
    let isDone: Bool
    var tint: Color
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(tint.opacity(isDone ? 0 : 0.55), lineWidth: 1.5)
                Circle()
                    .fill(tint)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isDone ? 1 : 0.4)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: size, height: size)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDone)
        .sensoryFeedback(.success, trigger: isDone) { _, new in new }
        .accessibilityLabel(isDone ? "Fait" : "Marquer comme fait")
    }
}

/// Texte barré qui se trace de gauche à droite.
struct StrikeText: View {
    let text: String
    let isStruck: Bool
    let font: Font
    var color: Color

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color.opacity(isStruck ? 0.5 : 1))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(color.opacity(0.7))
                        .frame(width: isStruck ? geo.size.width : 0, height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isStruck)
    }
}

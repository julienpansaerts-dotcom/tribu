import SwiftUI
import UIKit

/// Les trois ambiances visuelles de Tribu. Chaque membre choisit la sienne dans Réglages.
enum TribuStyle: String, CaseIterable, Identifiable {
    case frigo
    case album
    case couleurs

    var id: String { rawValue }

    var name: String {
        switch self {
        case .frigo: return "La porte du frigo"
        case .album: return "L'album du soir"
        case .couleurs: return "Les couleurs de la maison"
        }
    }

    var summary: String {
        switch self {
        case .frigo: return "Post-it, aimants et photos tenues de travers. Ludique et fait main."
        case .album: return "Votre photo de famille en grand, une écriture élégante. Doux et intime."
        case .couleurs: return "Une couleur par module, de gros chiffres. Joyeux et lisible d'un coup d'œil."
        }
    }
}

/// Couleurs proposées pour les membres de la famille.
enum MemberColors {
    static let all: [UInt32] = [0xE8553B, 0x4F86C6, 0xF2B84B, 0x7FAF8B, 0xF6A1B5, 0x2F6B4F, 0xC98E5A, 0x3FA7A0, 0x1D1B18]

    static func next(after used: [UInt32]) -> UInt32 {
        all.first { !used.contains($0) } ?? all[used.count % all.count]
    }
}

/// Les modules de l'app, utilisés pour leur couleur propre.
enum Module: CaseIterable {
    case courses, rappels, famille, agenda, repas, depenses, taches, activites
}

/// Jeu de polices d'une ambiance. Toutes les tailles suivent la taille de texte choisie sur l'iPhone.
struct Typography {
    let displayName: String
    let titleName: String
    let headlineName: String
    let bodyName: String
    let mediumName: String
    let handName: String?

    func display(_ size: CGFloat) -> Font { .custom(displayName, size: size, relativeTo: .largeTitle) }
    func title(_ size: CGFloat) -> Font { .custom(titleName, size: size, relativeTo: .title) }
    func headline(_ size: CGFloat = 15) -> Font { .custom(headlineName, size: size, relativeTo: .headline) }
    func body(_ size: CGFloat = 16) -> Font { .custom(bodyName, size: size, relativeTo: .body) }
    func medium(_ size: CGFloat = 16) -> Font { .custom(mediumName, size: size, relativeTo: .body) }
    func caption(_ size: CGFloat = 13) -> Font { .custom(bodyName, size: size, relativeTo: .caption) }
    func number(_ size: CGFloat) -> Font { .custom(displayName, size: size, relativeTo: .largeTitle) }
    func hand(_ size: CGFloat) -> Font { .custom(handName ?? titleName, size: size, relativeTo: .title) }
}

/// Toutes les valeurs visuelles d'une ambiance.
struct Theme {
    let style: TribuStyle
    let background: Color
    let surface: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let onAccent: Color
    let separator: Color
    let tabBar: Color
    let cornerRadius: CGFloat
    let typography: Typography
    /// Couleur d'encre posée sur les couleurs de module (toujours foncée, même en mode sombre).
    let ink: Color

    func color(for module: Module) -> Color {
        switch style {
        case .frigo:
            switch module {
            case .courses, .rappels: return Color(hex: 0xFFE58A)
            case .famille: return Color(hex: 0xBFD9F2)
            case .depenses: return Color(hex: 0xF4B6B0)
            case .agenda, .repas: return Color(hex: 0xFFFFFF)
            case .taches: return Color(hex: 0xCFE6C4)
            case .activites: return Color(hex: 0xFFD3A8)
            }
        case .album:
            switch module {
            case .courses: return Color(hex: 0xF0A04B)
            case .rappels: return Color(hex: 0xFDE7C8)
            case .famille: return Color(hex: 0xE2EDE5)
            case .agenda: return Color(hex: 0xE2EDE5)
            case .repas: return Color(hex: 0xF3F6F2)
            case .depenses: return Color(hex: 0xF6DDD3)
            case .taches: return Color(hex: 0xE4E9F2)
            case .activites: return Color(hex: 0xFBE6B8)
            }
        case .couleurs:
            switch module {
            case .courses: return Color(hex: 0xF2643F)
            case .rappels: return Color(hex: 0xFFCF4D)
            case .famille: return Color(hex: 0xF6B8C6)
            case .agenda: return Color(hex: 0xA9D3F5)
            case .repas: return Color(hex: 0xB9D8B4)
            case .depenses: return Color(hex: 0xFFB27A)
            case .taches: return Color(hex: 0xC9E4E0)
            case .activites: return Color(hex: 0xF7D9A8)
            }
        }
    }

    static func make(_ style: TribuStyle) -> Theme {
        switch style {
        case .frigo:
            return Theme(
                style: style,
                background: .dynamic(light: 0xE6EBE1, dark: 0x1C211D),
                surface: .dynamic(light: 0xFFFFFF, dark: 0x2A302B),
                text: .dynamic(light: 0x2B2A26, dark: 0xEDEDE6),
                secondaryText: .dynamic(light: 0x5C6157, dark: 0xA7AD9F),
                accent: Color(hex: 0xE8553B),
                onAccent: .white,
                separator: .dynamic(light: 0xD6D9D0, dark: 0x3A4139),
                tabBar: .dynamic(light: 0x2B2A26, dark: 0x2B2A26),
                cornerRadius: 4,
                typography: Typography(
                    displayName: "TribuBricolage-ExtraBold",
                    titleName: "TribuBricolage-ExtraBold",
                    headlineName: "TribuBricolage-SemiBold",
                    bodyName: "TribuBricolage-Regular",
                    mediumName: "TribuBricolage-SemiBold",
                    handName: "TribuCaveat-Bold"
                ),
                ink: Color(hex: 0x2B2A26)
            )
        case .album:
            return Theme(
                style: style,
                background: .dynamic(light: 0xFFFFFF, dark: 0x111613),
                surface: .dynamic(light: 0xF3F6F2, dark: 0x1D2420),
                text: .dynamic(light: 0x22312A, dark: 0xE8EEE9),
                secondaryText: .dynamic(light: 0x5E6B64, dark: 0x9DAAA2),
                accent: .dynamic(light: 0x2F6B4F, dark: 0x6FBF94),
                onAccent: .dynamic(light: 0xFFFFFF, dark: 0x0E1A14),
                separator: .dynamic(light: 0xE4E8E3, dark: 0x2A332E),
                tabBar: .dynamic(light: 0xFFFFFF, dark: 0x1D2420),
                cornerRadius: 16,
                typography: Typography(
                    displayName: "TribuNewsreaderItalic-Medium",
                    titleName: "TribuNewsreader-Medium",
                    headlineName: "TribuHanken-SemiBold",
                    bodyName: "TribuHanken-Regular",
                    mediumName: "TribuHanken-Medium",
                    handName: nil
                ),
                ink: Color(hex: 0x22312A)
            )
        case .couleurs:
            return Theme(
                style: style,
                background: .dynamic(light: 0xFFFCF7, dark: 0x171513),
                surface: .dynamic(light: 0xF4EFE8, dark: 0x24211E),
                text: .dynamic(light: 0x1D1B18, dark: 0xF5F0E8),
                secondaryText: .dynamic(light: 0x6A645B, dark: 0xA79F94),
                accent: Color(hex: 0xF2643F),
                onAccent: Color(hex: 0x1D1B18),
                separator: .dynamic(light: 0xE6DFD5, dark: 0x34302B),
                tabBar: .dynamic(light: 0x1D1B18, dark: 0x24211E),
                cornerRadius: 22,
                typography: Typography(
                    displayName: "TribuFamiljen-Bold",
                    titleName: "TribuFamiljen-Bold",
                    headlineName: "TribuFamiljen-SemiBold",
                    bodyName: "TribuFamiljen-Regular",
                    mediumName: "TribuFamiljen-SemiBold",
                    handName: nil
                ),
                ink: Color(hex: 0x1D1B18)
            )
        }
    }
}

// MARK: - Environnement

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.make(.couleurs)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Couleurs

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Couleur qui change entre le mode clair et le mode sombre.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

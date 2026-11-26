import SwiftUI
import WidgetKit

// MARK: - Données

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        // On se rafraîchit au plus tard dans 30 minutes, et juste après minuit.
        let soon = Date.now.addingTimeInterval(30 * 60)
        let midnight = Calendar.current.startOfDay(for: Date.now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: snapshot)], policy: .after(min(soon, midnight))))
    }
}

extension WidgetSnapshot {
    var theme: Theme { Theme.make(TribuStyle(rawValue: style) ?? .couleurs) }
}

// MARK: - Widget « Aujourd'hui »

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TribuToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Aujourd'hui")
        .description("Les rappels, rendez-vous et le repas du jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var theme: Theme { snapshot.theme }
    private var t: Typography { theme.typography }
    private var pending: [WidgetSnapshot.Item] { snapshot.today.filter { !$0.done } }

    /// Le fond « post-it » du frigo reste clair même en mode sombre : le texte doit donc rester foncé.
    private var lightBackground: Bool { theme.style == .frigo }
    private var primary: Color { lightBackground ? theme.ink : theme.text }
    private var secondary: Color { lightBackground ? theme.ink.opacity(0.68) : theme.secondaryText }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(pending.first.map { "\($0.time) · \($0.title)" } ?? "Rien de prévu aujourd'hui")
                    .containerBackground(for: .widget) { Color.clear }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aujourd'hui").font(.caption2.weight(.semibold)).widgetAccentable()
                    if pending.isEmpty {
                        Text("Rien de prévu").font(.caption)
                    }
                    ForEach(pending.prefix(2), id: \.self) { item in
                        Text("\(item.time) \(item.title)").font(.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(for: .widget) { Color.clear }
            default:
                homeScreen
            }
        }
        .widgetURL(URL(string: "tribu://aujourdhui"))
    }

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        default: return 7
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().locale(Locale(identifier: "fr_BE"))).capitalized)
                    .font(t.display(family == .systemSmall ? 18 : 22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text("\(pending.count) à venir").font(t.caption(12)).foregroundStyle(secondary)
                }
            }
            if pending.isEmpty {
                Spacer(minLength: 0)
                Text("Rien de prévu aujourd'hui.")
                    .font(theme.style == .frigo ? t.hand(20) : t.body(14))
                    .foregroundStyle(secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(pending.prefix(maxItems), id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: item.colorHex)).frame(width: 3)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title).font(t.headline(family == .systemSmall ? 13 : 14)).lineLimit(1)
                            Text(family == .systemSmall ? item.time : [item.time, item.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(t.caption(11))
                                .foregroundStyle(secondary)
                                .lineLimit(1)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if family == .systemLarge, snapshot.shoppingCount > 0 {
                Divider()
                Label("\(snapshot.shoppingCount) article\(snapshot.shoppingCount > 1 ? "s" : "") sur la liste de courses", systemImage: "basket")
                    .font(t.caption(12))
                    .foregroundStyle(secondary)
            }
        }
        .foregroundStyle(primary)
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var background: some View {
        switch theme.style {
        case .frigo: theme.color(for: .rappels)
        case .album: theme.background
        case .couleurs: theme.background
        }
    }
}

// MARK: - Widget « Courses »

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TribuShopping", provider: SnapshotProvider()) { entry in
            ShoppingWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Courses")
        .description("Ce qu'il reste à acheter sur la liste de la tribu.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ShoppingWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var theme: Theme { snapshot.theme }
    private var t: Typography { theme.typography }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "basket").font(.caption)
                        Text("\(snapshot.shoppingCount)").font(.title3.weight(.bold))
                    }
                }
                .containerBackground(for: .widget) { Color.clear }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Courses · \(snapshot.shoppingCount)").font(.caption2.weight(.semibold)).widgetAccentable()
                    Text(snapshot.shoppingItems.prefix(4).joined(separator: ", ")).font(.caption).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(for: .widget) { Color.clear }
            default:
                homeScreen
            }
        }
        .widgetURL(URL(string: "tribu://courses"))
    }

    private var homeScreen: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Courses").font(t.headline(14))
                Spacer(minLength: 0)
                Text("\(snapshot.shoppingCount)").font(t.number(44)).minimumScaleFactor(0.6)
                Text(snapshot.shoppingCount > 1 ? "articles" : "article").font(t.caption(12)).opacity(0.75)
            }
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.shoppingItems.prefix(5), id: \.self) { name in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(theme.ink.opacity(0.6), lineWidth: 1.2).frame(width: 12, height: 12)
                            Text(name).font(t.body(13)).lineLimit(1)
                        }
                    }
                    if snapshot.shoppingItems.isEmpty {
                        Text("Tout est pris !").font(t.body(13))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { theme.color(for: .courses) }
    }
}

// MARK: - Ensemble

@main
struct TribuWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ShoppingWidget()
    }
}

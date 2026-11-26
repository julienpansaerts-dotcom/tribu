import SwiftUI

/// Ambiance C — une couleur par module, de gros chiffres.
struct CouleursHomeView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var pulse = false

    private var t: Typography { theme.typography }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header.staggeredAppear(0)
                coursesTile.staggeredAppear(1)
                HStack(alignment: .top, spacing: 12) {
                    reminderTile
                    sizeTile
                        .frame(width: 132)
                }
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppear(2)
                agendaTile.staggeredAppear(3)
                mealTile.staggeredAppear(4)
                FeedPreview().padding(.horizontal, 4).staggeredAppear(5)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedBackground()
    }

    private var todaySummary: String {
        let count = store.today.filter { !$0.isDone }.count
        switch count {
        case 0: return "\(store.remainingShopping.count) à acheter."
        case 1: return "1 chose aujourd'hui."
        default: return "\(count) choses aujourd'hui."
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.tribuLongDate)
                .font(t.body(15))
                .foregroundStyle(theme.secondaryText)
            Text("Salut la famille.")
                .font(t.display(40))
            Text(todaySummary)
                .font(t.display(40))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
                .contentTransition(.numericText())
        }
        .tracking(-0.8)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func tile<Content: View>(_ module: Module, @ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(theme.ink)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.color(for: module), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
    }

    private var coursesTile: some View {
        tile(.courses) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Courses").font(t.headline(15))
                    Spacer()
                    if let shopper = store.shopperName {
                        HStack(spacing: 6) {
                            Circle().fill(theme.ink).frame(width: 7, height: 7)
                                .opacity(pulse ? 0.25 : 1)
                                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                            Text("\(shopper) est au magasin").font(t.caption(13))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.35), in: Capsule())
                        .onAppear { pulse = true }
                    }
                }
                HStack(alignment: .bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(store.remainingShopping.count)")
                            .font(t.number(56))
                            .contentTransition(.numericText())
                        Text("articles").font(t.headline(20))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(store.remainingShopping.prefix(3)) { item in
                            Text(item.name).font(t.caption(13)).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var reminderTile: some View {
        let reminder = store.today.first { $0.kind == .reminder }
        return tile(.rappels) {
            VStack(alignment: .leading, spacing: 10) {
                if let reminder {
                    Text("\(store.person(reminder.personId)?.firstName ?? "Rappel") · \(reminder.time)")
                        .font(t.headline(13))
                    StrikeText(text: reminder.title, isStruck: reminder.isDone, font: t.title(22), color: theme.ink)
                    Button {
                        withAnimation(.spring) { store.toggleDone(reminder) }
                    } label: {
                        Text(reminder.isDone ? "Fait, merci !" : "C'est fait")
                            .font(t.headline(14))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(theme.ink, in: Capsule())
                            .foregroundStyle(theme.color(for: .rappels))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: reminder.isDone) { _, new in new }
                } else {
                    Text("Aucun rappel").font(t.title(20))
                }
            }
        }
    }

    private var sizeTile: some View {
        tile(.famille) {
            VStack(alignment: .leading, spacing: 0) {
                if let change = store.latestSizeChange {
                    Text(change.person.firstName).font(t.headline(13))
                    Spacer(minLength: 12)
                    Text(change.size.label).font(t.caption(13))
                    Text(change.size.value).font(t.number(42))
                    if let previous = change.size.previousValue {
                        Text("avant : \(previous)").font(t.caption(12)).opacity(0.7)
                    }
                } else {
                    Text("Tailles").font(t.headline(13))
                }
            }
        }
    }

    private var agendaTile: some View {
        tile(.agenda) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Agenda").font(t.headline(15)).padding(.bottom, 6)
                let events = store.today.filter { $0.kind == .event }
                if events.isEmpty {
                    Text("Rien de prévu aujourd'hui.").font(t.body(16)).padding(.vertical, 8)
                }
                ForEach(Array(events.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text(item.time).font(t.headline(15)).frame(width: 52, alignment: .leading)
                        Text(item.title).font(t.body(16))
                        Spacer()
                        Text(store.person(item.personId)?.firstName ?? "").font(t.caption(13))
                    }
                    .frame(minHeight: 42)
                    if index < events.count - 1 {
                        Rectangle().fill(theme.ink.opacity(0.15)).frame(height: 1)
                    }
                }
            }
        }
    }

    private var mealTile: some View {
        tile(.repas) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ce soir").font(t.headline(13))
                    Text(store.tonight?.title ?? "Rien de prévu").font(t.title(20))
                }
                Spacer()
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0xC98E5A))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "fork.knife").foregroundStyle(.white.opacity(0.85)))
            }
        }
    }
}

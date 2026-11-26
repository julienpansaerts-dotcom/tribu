import SwiftUI

/// Ambiance A — la porte du frigo : post-it, aimants, photos de travers.
struct FrigoHomeView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    private var t: Typography { theme.typography }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header.staggeredAppear(0)

                HStack(alignment: .top, spacing: 14) {
                    reminderPostIt
                        .rotationEffect(.degrees(-2))
                        .staggeredAppear(1)
                    mealPolaroid
                        .rotationEffect(.degrees(2.5))
                        .staggeredAppear(2)
                }

                todayCard
                    .rotationEffect(.degrees(-0.6))
                    .padding(.horizontal, 6)
                    .staggeredAppear(3)

                HStack(alignment: .top, spacing: 14) {
                    if store.unpaidBillsCount > 0 {
                        billsNote
                            .rotationEffect(.degrees(1.5))
                    } else {
                        shoppingNote
                            .rotationEffect(.degrees(1.5))
                    }
                    sizeNote
                        .rotationEffect(.degrees(-2))
                }
                .staggeredAppear(4)

                FeedPreview()
                    .padding(14)
                    .background(Color.white.opacity(0.7))
                    .rotationEffect(.degrees(0.8))
                    .staggeredAppear(5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bonjour \(store.currentUser?.firstName ?? "")")
                    .font(t.body(15))
                    .foregroundStyle(theme.secondaryText)
                Text(Date.now.tribuDayTitle)
                    .font(t.display(44))
                    .tracking(-0.8)
            }
            Spacer()
            HStack(spacing: -10) {
                ForEach(store.people) { person in
                    Avatar(person: person, size: 38)
                        .overlay(Circle().stroke(theme.background, lineWidth: 3))
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: Pièces du frigo

    private var reminderPostIt: some View {
        let reminder = store.today.first { $0.kind == .reminder }
        return VStack(alignment: .leading, spacing: 6) {
            if reminder == nil {
                Text("Rappels").font(t.headline(13)).foregroundStyle(Color(hex: 0x6B5A1E))
                Text("Rien à faire pour l'instant !").font(t.hand(28)).foregroundStyle(theme.ink)
            }
            if let reminder {
                Text("Pour toi · \(reminder.time)")
                    .font(t.headline(13))
                    .foregroundStyle(Color(hex: 0x6B5A1E))
                StrikeText(text: reminder.title, isStruck: reminder.isDone, font: t.hand(30), color: theme.ink)
                Spacer(minLength: 6)
                HStack {
                    Text("— \(store.person(reminder.personId)?.firstName ?? "")")
                        .font(t.hand(20))
                        .foregroundStyle(Color(hex: 0x6B5A1E))
                    Spacer()
                    DoneButton(isDone: reminder.isDone, tint: theme.ink, size: 26) {
                        store.toggleDone(reminder)
                    }
                    .padding(-8)
                }
            }
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(theme.color(for: .rappels))
        .paperShadow()
        .magnet(Color(hex: 0xE8553B), alignment: .top)
    }

    private var mealPolaroid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(hex: 0xC98E5A))
                .frame(height: 130)
                .overlay(Image(systemName: "fork.knife").font(.title2).foregroundStyle(.white.opacity(0.8)))
            Text("Ce soir").font(t.caption(12)).foregroundStyle(Color(hex: 0x5C6157))
            Text(store.tonight?.title ?? "Rien de prévu")
                .font(t.headline(17))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .paperShadow()
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(hex: 0xF4B6B0, opacity: 0.75))
                .frame(width: 60, height: 20)
                .rotationEffect(.degrees(-4))
                .offset(y: -10)
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Aujourd'hui")
                .font(t.title(22))
                .padding(.bottom, 6)
            let events = store.today.filter { $0.kind != .reminder }
            if events.isEmpty {
                Text("Rien de prévu. L'agenda arrive bientôt !").font(t.body(16)).padding(.vertical, 12)
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text(item.time).font(t.headline(15)).frame(width: 54, alignment: .leading)
                    Text(item.title).font(t.body(16))
                    Spacer()
                    Circle()
                        .fill(store.person(item.personId).map { Color(hex: $0.colorHex) } ?? theme.ink)
                        .frame(width: 10, height: 10)
                }
                .frame(minHeight: 46)
                if index < events.count - 1 {
                    DashedLine().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color(hex: 0xD6D9D0))
                        .frame(height: 1)
                }
            }
        }
        .foregroundStyle(theme.ink)
        .padding(EdgeInsets(top: 22, leading: 18, bottom: 8, trailing: 18))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
        .paperShadow()
        .magnet(Color(hex: 0x4F86C6), alignment: .top)
    }

    private var billsNote: some View {
        VStack(alignment: .leading) {
            Text("Factures à payer").font(t.headline(13)).foregroundStyle(Color(hex: 0x6E2F28))
            Spacer(minLength: 12)
            Text(store.unpaidBillsTotal.euros).font(t.display(28)).foregroundStyle(theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(theme.color(for: .depenses))
        .paperShadow()
        .magnet(Color(hex: 0x7FAF8B), alignment: .topLeading)
    }

    private var shoppingNote: some View {
        VStack(alignment: .leading) {
            Text("Courses").font(t.headline(13)).foregroundStyle(Color(hex: 0x6E2F28))
            Spacer(minLength: 12)
            Text("\(store.remainingShopping.count) à prendre").font(t.display(26)).foregroundStyle(theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(theme.color(for: .depenses))
        .paperShadow()
        .magnet(Color(hex: 0x7FAF8B), alignment: .topLeading)
    }

    private var sizeNote: some View {
        VStack(alignment: .leading) {
            if let change = store.latestSizeChange {
                Text("\(change.person.firstName) a grandi").font(t.headline(13)).foregroundStyle(Color(hex: 0x23415F))
                Spacer(minLength: 12)
                Text("\(change.size.label) \(change.size.previousValue ?? "") → \(change.size.value)")
                    .font(t.headline(17))
                    .foregroundStyle(theme.ink)
            } else {
                Text("Famille").font(t.headline(13)).foregroundStyle(Color(hex: 0x23415F))
                Spacer(minLength: 12)
                Text("\(store.people.count) personne\(store.people.count > 1 ? "s" : "")")
                    .font(t.headline(17))
                    .foregroundStyle(theme.ink)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(theme.color(for: .famille))
        .paperShadow()
        .magnet(Color(hex: 0xF2B84B), alignment: .topTrailing)
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

private extension View {
    func paperShadow() -> some View {
        shadow(color: Color(hex: 0x2B2A26, opacity: 0.14), radius: 7, x: 0, y: 6)
    }

    /// Aimant rond posé sur le bord haut de l'élément.
    func magnet(_ color: Color, alignment: Alignment) -> some View {
        overlay(alignment: alignment) {
            Circle()
                .fill(color)
                .overlay(Circle().fill(.black.opacity(0.12)).padding(3).offset(x: 1.5, y: 1.5).blendMode(.multiply))
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 2)
                .offset(x: alignment == .topLeading ? 20 : (alignment == .topTrailing ? -20 : 0), y: -9)
        }
    }
}

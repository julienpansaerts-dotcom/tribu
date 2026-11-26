import PhotosUI
import SwiftUI

/// Ambiance B — l'album du soir : la photo de famille en grand.
struct AlbumHomeView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var photoItem: PhotosPickerItem?
    @State private var cover: UIImage? = CoverPhoto.load()

    private var t: Typography { theme.typography }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                sheet
                    .background(theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
                    .offset(y: -30)
                    .padding(.bottom, -30)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .themedBackground()
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    CoverPhoto.save(data)
                    withAnimation(.smooth) { cover = image }
                }
            }
        }
    }

    private var hero: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover {
                        Color.clear.overlay {
                            Image(uiImage: cover).resizable().scaledToFill()
                        }
                    } else {
                        Rectangle().fill(Color(hex: 0xB8774A))
                            .overlay(alignment: .topTrailing) {
                                Label("Choisir la photo de famille", systemImage: "photo")
                                    .font(t.caption(12))
                                    .foregroundStyle(Color(hex: 0xF7E6D8))
                                    .padding(.top, 70).padding(.trailing, 16)
                            }
                    }
                }
                .frame(height: 340)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom))

                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.tribuLongDate)
                        .font(t.headline(14))
                    Text("\(greeting), la tribu.")
                        .font(t.display(46))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 52)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo de famille, toucher pour la changer")
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 18 || hour < 5 ? "Bonsoir" : "Bonjour"
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            members.staggeredAppear(0)
            mealCard.staggeredAppear(1)
            todayList.staggeredAppear(2)
            FeedPreview().padding(.horizontal, 4).staggeredAppear(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 32)
    }

    private var members: some View {
        HStack(spacing: 14) {
            ForEach(store.people) { person in
                let busy = store.today.contains { $0.personId == person.id && !$0.isDone }
                VStack(spacing: 6) {
                    Avatar(person: person, size: 46)
                        .padding(3)
                        .overlay(Circle().strokeBorder(busy ? Color(hex: 0xF0A04B) : theme.separator, lineWidth: 2.5))
                    Text(person.firstName).font(t.caption(12))
                }
            }
        }
    }

    private var mealCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xC98E5A))
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "fork.knife").foregroundStyle(.white.opacity(0.85)))
            VStack(alignment: .leading, spacing: 4) {
                Text("CE SOIR").font(t.headline(12)).tracking(0.8).foregroundStyle(theme.accent)
                Text(store.tonight?.title ?? "Rien de prévu").font(t.title(22))
                if let meal = store.tonight {
                    Text("\(meal.minutes) min · \(meal.note.lowercased())").font(t.caption(13)).foregroundStyle(theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aujourd'hui").font(t.title(24)).padding(.bottom, 6)
            if store.today.filter({ $0.kind != .meal }).isEmpty {
                Text("Une journée calme. Il reste \(store.remainingShopping.count) article\(store.remainingShopping.count > 1 ? "s" : "") sur la liste de courses.")
                    .font(t.body(16))
                    .foregroundStyle(theme.secondaryText)
            }
            ForEach(store.today.filter { $0.kind != .meal }) { item in
                HStack(spacing: 12) {
                    Text(item.time)
                        .font(t.headline(13))
                        .padding(.vertical, 5)
                        .frame(width: 58)
                        .background(item.kind == .reminder ? Color(hex: 0xFDE7C8) : Color(hex: 0xE2EDE5), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(item.kind == .reminder ? Color(hex: 0x6B3E0B) : Color(hex: 0x1F4D37))
                    VStack(alignment: .leading, spacing: 1) {
                        StrikeText(text: item.title, isStruck: item.isDone, font: t.medium(16), color: theme.text)
                        Text(item.detail).font(t.caption(13)).foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    if item.kind == .reminder {
                        DoneButton(isDone: item.isDone, tint: theme.accent) { store.toggleDone(item) }
                    }
                }
                .frame(minHeight: 52)
            }
        }
    }
}

/// La photo de couverture est gardée sur l'iPhone pour ce premier jalon.
enum CoverPhoto {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cover.jpg")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ data: Data) {
        try? data.write(to: url, options: .atomic)
    }
}

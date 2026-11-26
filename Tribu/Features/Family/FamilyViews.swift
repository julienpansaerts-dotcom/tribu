import Charts
import SwiftUI

/// Liste des membres de la famille.
struct FamilyListView: View {
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store

    @State private var showNewPerson = false
    @State private var path: [String] = {
        let id = UserDefaults.standard.string(forKey: "tribu.person") ?? ""
        return id.isEmpty ? [] : [id]
    }()

    private var t: Typography { theme.typography }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Famille")
                            .font(t.display(44))
                        Spacer()
                        Button {
                            showNewPerson = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(theme.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ajouter une personne")
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    if store.people.isEmpty {
                        Text("Ajoute les membres de la famille pour noter leurs tailles, allergies et infos utiles.")
                            .font(t.body(16))
                            .foregroundStyle(theme.secondaryText)
                    }
                    ForEach(Array(store.people.enumerated()), id: \.element.id) { index, person in
                        NavigationLink(value: person.id) {
                            PersonRow(person: person)
                        }
                        .buttonStyle(.plain)
                        .staggeredAppear(index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationDestination(for: String.self) { id in
                PersonDetailView(personId: id)
            }
            .sheet(isPresented: $showNewPerson) { PersonEditor(existing: nil) }
        }
    }
}

private struct PersonRow: View {
    let person: Person
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Avatar(person: person, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.firstName).font(theme.typography.title(22))
                Text(summary).font(theme.typography.caption(13)).foregroundStyle(theme.secondaryText)
            }
            Spacer()
            if !person.allergies.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: 0xD9480F))
                    .accessibilityLabel("Allergie")
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.secondaryText)
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
    }

    private var summary: String {
        let pieces = person.sizes.prefix(3).map { "\($0.label) \($0.value)" }
        return ([person.ageText].compactMap { $0 } + pieces).joined(separator: " · ")
    }
}

/// Fiche d'une personne : alertes, tailles, croissance, notes.
struct PersonDetailView: View {
    let personId: String
    @Environment(\.theme) private var theme
    @Environment(FamilyStore.self) private var store
    @State private var editingSize: SizeEntry?
    @State private var addingSize = false
    @State private var editingPerson = false
    @State private var addingGrowth = false

    private var t: Typography { theme.typography }

    var body: some View {
        if let person = store.person(personId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(person)
                    ForEach(person.allergies, id: \.self) { allergy in
                        allergyBanner(allergy, notes: person.notes.first)
                    }
                    sizesGrid(person)
                    if person.growth.count > 1 {
                        GrowthChart(points: person.growth)
                    }
                    if person.isChild {
                        Button {
                            addingGrowth = true
                        } label: {
                            Label("Ajouter une mesure (taille, poids)", systemImage: "ruler")
                                .font(t.body(15))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.secondaryText)
                    }
                    if !person.notes.isEmpty {
                        notes(person)
                    }
                    DocumentsSection(person: person)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Modifier") { editingPerson = true }
                }
            }
            .sheet(item: $editingSize) { size in SizeEditor(person: person, existing: size) }
            .sheet(isPresented: $addingSize) { SizeEditor(person: person, existing: nil) }
            .sheet(isPresented: $editingPerson) { PersonEditor(existing: person) }
            .sheet(isPresented: $addingGrowth) { GrowthEditor(person: person) }
        }
    }

    private func header(_ person: Person) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            Avatar(person: person, size: 68)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.firstName).font(t.display(42))
                Text([person.ageText, person.bloodType.map { "Groupe \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(t.caption(14))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.top, 8)
    }

    private func allergyBanner(_ allergy: String, notes: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xFFCF4D))
            VStack(alignment: .leading, spacing: 1) {
                Text("Allergie : \(allergy.lowercased())").font(t.headline(15))
                if let notes { Text(notes).font(t.caption(13)).opacity(0.85) }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color(hex: 0x2B2A26), in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }

    private func sizesGrid(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tailles").font(t.title(22))
                Spacer()
                if let last = person.sizes.max(by: { $0.updatedAt < $1.updatedAt }) {
                    Text("Mis à jour \(last.updatedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_BE")))) · \(last.updatedBy)")
                        .font(t.caption(12))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(person.sizes) { size in
                    Button {
                        editingSize = size
                    } label: {
                        SizeCell(size: size)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    addingSize = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.title3)
                        Text("Ajouter").font(t.caption(12))
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .foregroundStyle(theme.secondaryText)
                    .overlay(
                        RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous)
                            .strokeBorder(theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func notes(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("À savoir").font(t.title(22))
            ForEach(person.notes, id: \.self) { note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Color(hex: person.colorHex)).frame(width: 7, height: 7)
                    Text(note).font(t.body(16))
                }
            }
        }
    }
}

private struct SizeCell: View {
    let size: SizeEntry
    @Environment(\.theme) private var theme

    /// Mis en avant pendant 30 jours après un changement de taille.
    private var isRecent: Bool {
        size.previousValue != nil && size.updatedAt > Date.now.addingTimeInterval(-30 * 24 * 3600)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(size.label).font(theme.typography.caption(12)).foregroundStyle(isRecent ? theme.ink.opacity(0.75) : theme.secondaryText)
            Text(size.value).font(theme.typography.number(26)).foregroundStyle(isRecent ? theme.ink : theme.text)
            Text(isRecent ? "avant : \(size.previousValue ?? "")" : (size.detail ?? " "))
                .font(theme.typography.caption(11))
                .foregroundStyle(isRecent ? theme.ink.opacity(0.75) : theme.secondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(isRecent ? theme.color(for: .rappels) : theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
    }
}

/// Courbe de taille d'un enfant.
private struct GrowthChart: View {
    let points: [GrowthPoint]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Taille (cm)").font(theme.typography.title(22))
            Chart {
                ForEach(points) { point in
                    if let height = point.heightCm {
                        LineMark(x: .value("Date", point.date), y: .value("Taille", height))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(theme.text)
                        PointMark(x: .value("Date", point.date), y: .value("Taille", height))
                            .symbolSize(point.id == points.last?.id ? 90 : 40)
                            .foregroundStyle(point.id == points.last?.id ? theme.accent : theme.text)
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: .year)) { _ in
                    AxisValueLabel(format: .dateTime.year())
                }
            }
            .frame(height: 150)
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: min(theme.cornerRadius, 14), style: .continuous))
            .accessibilityLabel("Courbe de taille")
        }
    }
}

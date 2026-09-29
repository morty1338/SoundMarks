import SwiftUI

/// My profile: strict and calm — name, rank, stats, my planets
/// and the "Records" tab with all skins.
struct ProfileScreen: View {
    @Environment(AppEnvironment.self) private var environment

    /// My planets — from the fullest.
    let planets: [PlanetInfo]

    private enum Tab: Hashable { case profile, records }

    @State private var tab: Tab = .profile
    @State private var stats = ProfileStats()
    @State private var analyzed: PlanetInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                ProfileStyle.background.ignoresSafeArea()

                if environment.profiles.me == nil {
                    ProfileSetupView()
                } else {
                    ScrollView {
                        VStack(spacing: 28) {
                            if let me = environment.profiles.me {
                                ProfileHeader(nickname: me.nickname ?? "", colorHex: me.avatarColorHex,
                                              avatarData: me.avatarData,
                                              subtitle: me.uniqueCode.map { "#\($0)" },
                                              rank: stats.rank, placeCount: stats.places)
                                    .padding(.top, DS.Spacing.m)
                            }

                            UnderlineTabs(items: [
                                (Tab.profile, Text("profile.tab.profile", comment: "Profile tab")),
                                (Tab.records, Text("profile.tab.records", comment: "Records tab")),
                            ], selection: $tab)

                            switch tab {
                            case .profile: profileTab
                            case .records:
                                SkinGallery(unlockLevel: environment.settings.skinUnlockLevel(for: stats.rank),
                                            isSelectable: true)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.l)
                        .padding(.bottom, DS.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(Text("profile.title", comment: "Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if let me = environment.profiles.me {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ProfileEditView(profile: me)
                        } label: {
                            Text("profile.edit.short", comment: "Edit")
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .tint(DS.Colors.marks)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .task { reload() }
        .sheet(item: $analyzed) { planet in
            PlanetAnalysisView(planet: planet)
        }
    }

    /// Stats — with a dictionary query over the needed fields, without place snapshots.
    private func reload() {
        stats = (try? PlaceQueries.stats(scope: .mine, in: environment.persistence.viewContext)) ?? ProfileStats()
    }

    @ViewBuilder
    private var profileTab: some View {
        VStack(spacing: 10) {
            ProfileStyle.caption(Text("profile.stats", comment: "Statistics"))
            StatGrid(items: [
                .init(value: stats.places, label: Text("profile.stat.records", comment: "Records"), id: 0),
                .init(value: stats.countries, label: Text("profile.stat.countries", comment: "Countries"), id: 1),
                .init(value: stats.cities, label: Text("profile.stat.cities", comment: "Cities"), id: 2),
                .init(value: environment.profiles.friends.count, label: Text("profile.stat.friends", comment: "Friends"), id: 3),
                .init(value: planets.count, label: Text("profile.stat.planets", comment: "Planets"), id: 4),
                .init(value: stats.artists, label: Text("profile.stat.artists", comment: "Artists"), id: 5),
            ])
            if let year = stats.firstYear {
                Text("profile.firstYear \(String(year))", comment: "First memory — year")
                    .font(.caption)
                    .foregroundStyle(ProfileStyle.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        VStack(spacing: 10) {
            ProfileStyle.caption(Text("profile.planets", comment: "My planets"))
            ProfilePanel {
                let sorted = planets.sorted { $0.placeCount > $1.placeCount }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, planet in
                    if index > 0 {
                        ProfileStyle.hairline.frame(height: 1).padding(.leading, 62)
                    }
                    Button {
                        Haptics.tap()
                        analyzed = planet
                    } label: {
                        PlanetRow(planet: planet)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("profile.planets.hint", comment: "Tap a planet — analysis for a period")
                .font(.caption)
                .foregroundStyle(ProfileStyle.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Record skins in a strict grid. For me — choosing the default skin,
/// for a friend — only which ones are unlocked.
struct SkinGallery: View {
    @Environment(AppEnvironment.self) private var environment

    /// Up to which rank skins are unlocked.
    let unlockLevel: Int
    /// My profile — an unlocked skin can be chosen as the default.
    var isSelectable = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(SkinCatalog.all) { skin in
                    tile(skin)
                }
            }
            if isSelectable {
                Text("profile.skins.footer", comment: "How skins are unlocked")
                    .font(.caption)
                    .foregroundStyle(ProfileStyle.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func tile(_ skin: RecordSkin) -> some View {
        let isUnlocked = skin.requiredRank <= unlockLevel
        let isSelected = isSelectable && environment.settings.defaultSkinID == skin.id

        return Button {
            guard isSelectable else { return }
            guard isUnlocked else {
                Haptics.warning()
                return
            }
            Haptics.select()
            environment.settings.defaultSkinID = skin.id
        } label: {
            VStack(spacing: 8) {
                VinylRecordView(artworkURL: nil, skin: skin)
                    .saturation(isUnlocked ? 1 : 0)
                    .opacity(isUnlocked ? 1 : 0.3)
                    .overlay {
                        if !isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(isSelected ? DS.Colors.marks : .clear, lineWidth: 2)
                    }
                Text(verbatim: skin.name)
                    .font(.caption)
                    .foregroundStyle(isUnlocked ? .white : ProfileStyle.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if isUnlocked {
                        Text(isSelected
                             ? String(localized: "profile.skin.selected", defaultValue: "Selected")
                             : String(localized: "profile.skin.available", defaultValue: "Unlocked"))
                    } else {
                        Text(String(localized: "profile.skin.locked",
                                    defaultValue: "Rank \(skin.requiredRank + 1)"))
                    }
                }
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(isSelected ? DS.Colors.marks : ProfileStyle.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

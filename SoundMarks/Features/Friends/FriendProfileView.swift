import CoreData
import SwiftUI

/// Friend profile: rank and stats of their planets, their planets and paired ones,
/// their unlocked records and actions — exchange, paired planet, removal, block.
struct FriendProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let friend: Profile
    /// Show the planet on the home screen.
    let onShowPlanet: (PlanetPage) -> Void
    let onDataChanged: () -> Void

    private enum Tab: Hashable { case profile, records }

    @State private var tab: Tab = .profile
    @State private var stats = ProfileStats()
    @State private var planets: [PlanetInfo] = []
    @State private var sharedMaps: [MemoryMap] = []
    /// Place coordinates per map — for the dots on the friend's planets.
    @State private var coordinates: [NSManagedObjectID: [SphereMapping.Coordinate]] = [:]
    @State private var syncMessage: String?
    @State private var exportedFile: ExportedFile?
    @State private var errorMessage: String?
    @State private var isConfirmingRemove = false
    @State private var isConfirmingBlock = false

    var body: some View {
        ZStack {
            ProfileStyle.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    ProfileHeader(nickname: friend.nickname ?? "", colorHex: friend.avatarColorHex,
                                  avatarData: friend.avatarData,
                                  subtitle: friend.lastSyncedAt.map(SyncText.synced) ?? SyncText.neverSynced,
                                  rank: stats.rank, placeCount: stats.places)
                        .padding(.top, DS.Spacing.m)

                    UnderlineTabs(items: [
                        (Tab.profile, Text("profile.tab.profile", comment: "Profile tab")),
                        (Tab.records, Text("profile.tab.records", comment: "Records tab")),
                    ], selection: $tab)

                    switch tab {
                    case .profile: profileTab
                    case .records: SkinGallery(unlockLevel: stats.rank.level)
                    }
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(Text(verbatim: friend.nickname ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(DS.Colors.marks)
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .sheet(item: $exportedFile) { file in
            ActivityView(items: file.urls)
        }
        .confirmationDialog(Text("friend.remove.confirm", comment: "Remove friend?"),
                            isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button(role: .destructive) {
                perform { try environment.profiles.remove(friend) }
            } label: {
                Text("friend.remove", comment: "Remove friend")
            }
        } message: {
            Text("friend.remove.message", comment: "What happens when a friend is removed")
        }
        .confirmationDialog(Text("friend.block.confirm", comment: "Block?"),
                            isPresented: $isConfirmingBlock, titleVisibility: .visible) {
            Button(role: .destructive) {
                perform { try environment.profiles.block(friend) }
            } label: {
                Text("friend.block", comment: "Block")
            }
        } message: {
            Text("friend.block.message", comment: "What happens when blocking")
        }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(role: .cancel) { errorMessage = nil } label: { Text("common.ok", comment: "OK") }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profileTab: some View {
        VStack(spacing: 10) {
            ProfileStyle.caption(Text("profile.stats", comment: "Statistics"))
            StatGrid(items: [
                .init(value: stats.places, label: Text("profile.stat.records", comment: "Records"), id: 0),
                .init(value: stats.countries, label: Text("profile.stat.countries", comment: "Countries"), id: 1),
                .init(value: stats.cities, label: Text("profile.stat.cities", comment: "Cities"), id: 2),
                .init(value: planets.count, label: Text("profile.stat.planets", comment: "Planets"), id: 3),
                .init(value: sharedMaps.count, label: Text("friend.stat.paired", comment: "Paired"), id: 4),
                .init(value: stats.artists, label: Text("profile.stat.artists", comment: "Artists"), id: 5),
            ])
            if !friend.planetVisible {
                Label {
                    Text("friend.planetHidden", comment: "The friend hid their planet")
                } icon: {
                    Image(systemName: "eye.slash")
                }
                .font(.caption)
                .foregroundStyle(ProfileStyle.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if !planets.isEmpty || !sharedMaps.isEmpty {
            VStack(spacing: 10) {
                ProfileStyle.caption(Text("friend.planets", comment: "Planets"))
                ProfilePanel {
                    let all = planets + sharedMaps.compactMap(sharedInfo)
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, planet in
                        if index > 0 {
                            ProfileStyle.hairline.frame(height: 1).padding(.leading, 62)
                        }
                        Button {
                            Haptics.tap()
                            onShowPlanet(planet.page)
                        } label: {
                            PlanetRow(planet: planet)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        VStack(spacing: 10) {
            ProfileStyle.caption(Text("friend.actions", comment: "Actions"))
            ProfilePanel {
                ProfileActionRow(icon: "arrow.triangle.2.circlepath",
                                 title: Text("friend.sync", comment: "Sync nearby"),
                                 action: syncNearby)
                ProfileActionRow(icon: "circle.circle",
                                 title: Text("friend.createSharedMap", comment: "Create paired planet"),
                                 action: createSharedMap)
                if !sharedMaps.isEmpty {
                    ProfileActionRow(icon: "square.and.arrow.up",
                                     title: Text("friend.sharedMap.send", comment: "Send paired planet as a file"),
                                     action: exportSharedMaps)
                }
                ProfileActionRow(icon: "person.badge.minus",
                                 title: Text("friend.remove", comment: "Remove friend"),
                                 isDestructive: true) { isConfirmingRemove = true }
                ProfileActionRow(icon: "hand.raised",
                                 title: Text("friend.block", comment: "Block"),
                                 isDestructive: true, showsDivider: false) { isConfirmingBlock = true }
            }
            if let syncMessage {
                Text(verbatim: syncMessage)
                    .font(.caption)
                    .foregroundStyle(ProfileStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Data

    private func reload() {
        guard let friendID = friend.id else { return }
        let context = environment.persistence.viewContext

        let mapsRequest = MemoryMap.fetchRequest()
        mapsRequest.predicate = NSPredicate(format: "kindRaw == %@ AND ownerProfileId == %@",
                                            MemoryMapKind.friend.rawValue, friendID as CVarArg)
        mapsRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        let maps = (try? context.fetch(mapsRequest)) ?? []
        let nickname = friend.nickname ?? ""
        // Dots and counts via dictionary queries: the friend's places are not loaded as objects.
        coordinates = (try? PlaceQueries.coordinatesByMap(in: context)) ?? [:]
        planets = maps.compactMap { map in
            guard let id = map.id else { return nil }
            let dots = coordinates[map.objectID] ?? []
            let title = map.title ?? map.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(localized: "planet.friendsPlanet", defaultValue: "\(nickname)'s Planet")
            return PlanetInfo(page: .friend(id), title: title, nickname: nickname,
                              avatarColorHex: friend.avatarColorHex, avatarData: friend.avatarData,
                              updatedAt: map.lastSyncedAt, placeCount: dots.count, dots: dots)
        }

        let mapIDs = maps.compactMap(\.id)
        stats = (try? PlaceQueries.stats(scope: .maps(mapIDs), in: context)) ?? ProfileStats()
        sharedMaps = environment.sync.sharedMaps().filter { $0.participantIDs.contains(friendID) }
    }

    private func sharedInfo(_ map: MemoryMap) -> PlanetInfo? {
        guard let id = map.id else { return nil }
        let dots = coordinates[map.objectID] ?? []
        return PlanetInfo(page: .shared(id),
                          title: map.title ?? String(localized: "planet.pairedName", defaultValue: "Paired planet"),
                          nickname: friend.nickname, avatarColorHex: friend.avatarColorHex, avatarData: friend.avatarData,
                          updatedAt: map.lastSyncedAt, placeCount: dots.count, dots: dots)
    }

    // MARK: - Actions

    private func createSharedMap() {
        do {
            let map = try environment.sync.createSharedMap(with: friend)
            Haptics.success()
            onDataChanged()
            // The friend sees it after the next nearby exchange.
            environment.nearby.syncNow(with: friend)
            reload()
            if let id = map.id { onShowPlanet(.shared(id)) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func syncNearby() {
        Haptics.tap()
        syncMessage = environment.nearby.syncNow(with: friend)
            ? String(localized: "friend.sync.started", defaultValue: "Your friend is nearby – exchanging maps.")
            : String(localized: "friend.sync.notNearby",
                     defaultValue: "Your friend isn't nearby right now. Ask them to open SoundMarks close to you, or send the shared map as a file.")
    }

    private func exportSharedMaps() {
        Task {
            do {
                var urls: [URL] = []
                for map in sharedMaps {
                    guard let id = map.id else { continue }
                    urls.append(try environment.sync.exportFile(try await environment.sync.sharedMapSnapshot(mapID: id)))
                }
                exportedFile = ExportedFile(urls: urls)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            Haptics.warning()
            onDataChanged()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

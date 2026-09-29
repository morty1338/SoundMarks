import CoreLocation
import SwiftUI

/// Launch flow: splash → planets ↔ map.
///
/// Shared state of both screens lives here — places, the preview player
/// and sheets (settings, roulette, detail screen) — so they open
/// the same way from the planet and from the map.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    private enum Stage { case planet, map }

    @State private var model: MapViewModel?
    @State private var directory: PlanetDirectory?
    @State private var player = PreviewAudioPlayer()

    /// Where the home screen is: paired planet, my planet or the "Friends Marks" page.
    @State private var slot: HomeSlot = .own(UUID())
    /// A friend's planet opened from the grid.
    @State private var focus: FriendFocus?

    @State private var stage: Stage = .planet
    @State private var isShowingSplash = true
    /// The planet scene is heavy — mount it once the splash is already on screen,
    /// otherwise the first frame waits for SceneKit and an empty screen shows instead of the photo.
    @State private var isPlanetMounted = false
    /// The map is created on first entry and stays alive — re-entering is instant.
    @State private var isMapMounted = false

    @State private var mapCommand: MapCommand?
    /// How far the map has already "flowed" into the planet while zooming out: 0…1.
    /// The "map → planet" transition is a separate object so the root screen does not rebuild every frame.
    @State private var zoom = ZoomOutState()
    @State private var globeCommand: GlobeCommand?
    @State private var selectedPlaceID: UUID?
    /// The player at the bottom of the map appears after the detail screen — not before.
    @State private var isPlayerVisible = false

    @State private var isShowingSettings = false
    @State private var isShowingRoulette = false
    @State private var isShowingOnboarding = false
    @State private var isShowingFriends = false
    @State private var isShowingProfile = false
    @State private var isShowingAddPlanet = false
    @State private var tripSummary: TripRequest?
    @State private var detailPlace: DetailRequest?
    @State private var editingPlace: EditRequest?
    /// A new planet's places are read after the paging animation, not in the middle of it.
    @State private var scopeTask: Task<Void, Never>?
    @State private var deletingPlanet: PlanetPage?
    /// Friend profile — opened by tapping the block with their name above the planet.
    @State private var openedFriend: FriendRequest?

    var body: some View {
        screens
            .background(Color.black.ignoresSafeArea())
            .task {
                bootstrap()
                // While the record crackles (first ~0.8 s) it stays still — a short
                // scene load underneath it is not visible.
                try? await Task.sleep(for: .milliseconds(150))
                isPlanetMounted = true
            }
            .onChange(of: environment.notificationRouter.requestedPlaceID) { _, placeID in
                guard let placeID else { return }
                open(placeID: placeID)
                environment.notificationRouter.clear()
            }
            .onChange(of: currentScope) { _, scope in
                selectedPlaceID = nil
                isPlayerVisible = false
                player.stop()
                // Reading places and rebuilding pins of the hidden map only once the carousel
                // has stopped: otherwise they steal frames from the animation.
                scopeTask?.cancel()
                scopeTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    syncScope()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                updateNearby(for: phase)
                if phase == .active { environment.dayCycle.start() } else { environment.dayCycle.stop() }
            }
            .onChange(of: directory?.sharedPlanets) { _, _ in validateSelection() }
            .onChange(of: directory?.friendStacks) { _, _ in validateSelection() }
            .onChange(of: directory?.ownPlanets) { _, _ in validateSelection() }
            .sheet(item: $openedFriend) { request in
                if let friend = environment.profiles.profile(id: request.id) {
                    NavigationStack {
                        FriendProfileView(friend: friend,
                                          onShowPlanet: { page in
                                              openedFriend = nil
                                              show(page)
                                          },
                                          onDataChanged: {
                                              directory?.reload()
                                              reloadPlaces()
                                          })
                    }
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(DS.Radius.sheet)
                }
            }
            .modifier(planetSheets)
            .modifier(placeSheets)
            .animation(DS.Motion.standard, value: environment.trips.active)
    }

    // MARK: - Screens

    private var screens: some View {
        ZStack {
            if isPlanetMounted, let directory {
                HomeScreen(
                    directory: directory,
                    slot: $slot,
                    focus: $focus,
                    isRevealed: !isShowingSplash,
                    isDay: environment.dayCycle.isDay,
                    markerStyle: environment.settings.planetMarker,
                    command: $globeCommand,
                    zoom: zoom,
                    isMapStage: stage == .map,
                    onEnterMap: enterMap,
                    onOpenSettings: { isShowingSettings = true },
                    onOpenFriends: { isShowingFriends = true },
                    onOpenProfile: { isShowingProfile = true },
                    onOpenRoulette: {
                        syncScope()
                        isShowingRoulette = true
                    },
                    onAddPlanet: { isShowingAddPlanet = true },
                    onRename: { page, title in
                        try? directory.rename(page, to: title)
                    },
                    onDelete: { deletingPlanet = $0 },
                    onOpenFriend: { openedFriend = FriendRequest(id: $0) },
                    onRemoveStack: { ownerID in
                        withAnimation(DS.Motion.standard) {
                            try? directory.removeStackFromScreen(ownerID: ownerID)
                        }
                    }
                )
                .modifier(PlanetLayerFade(zoom: zoom, isPlanetStage: stage == .planet))
                .allowsHitTesting(stage == .planet)
            }

            if isMapMounted, let model {
                MapScreen(
                    model: model,
                    player: player,
                    selectedPlaceID: $selectedPlaceID,
                    isPlayerVisible: $isPlayerVisible,
                    command: $mapCommand,
                    isReadOnly: isReadOnly,
                    targetMapID: currentPlanet?.targetMapID,
                    isDay: environment.dayCycle.isDay,
                    onOpenSettings: { isShowingSettings = true },
                    onOpenRoulette: { isShowingRoulette = true },
                    onOpenDetail: { detailPlace = DetailRequest(id: $0) },
                    onReturnToPlanet: returnToPlanet,
                    onZoomOutProgress: { [zoom] progress, center, animated in
                        // The hidden map prepared in advance does not touch the planet.
                        guard stage == .map else { return }
                        zoom.update(progress: progress, center: center, animated: animated)
                    },
                    onBack: returnToPlanet,
                    onPlacesChanged: reloadPlaces
                )
                .modifier(MapLayerFade(zoom: zoom, isMapStage: stage == .map))
                .allowsHitTesting(stage == .map)
            }

            if let trip = environment.trips.active, !isShowingSplash {
                VStack {
                    TripBanner(trip: trip) {
                        Task {
                            if let id = await environment.trips.finish() {
                                tripSummary = TripRequest(id: id)
                            }
                        }
                    }
                    .padding(.top, DS.Spacing.s)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(5)
            }

            if isShowingSplash {
                SplashView {
                    isShowingSplash = false
                    afterSplash()
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    // MARK: - Planet sheets

    private var planetSheets: PlanetSheets {
        PlanetSheets(
            directory: directory,
            isShowingProfile: $isShowingProfile,
            isShowingAddPlanet: $isShowingAddPlanet,
            isShowingFriends: $isShowingFriends,
            deletingPlanet: $deletingPlanet,
            isDay: environment.dayCycle.isDay,
            onShow: show,
            onShowFromFriends: { page in
                isShowingFriends = false
                openedFriend = nil
                directory?.reload()
                show(page)
            },
            onDataChanged: {
                directory?.reload()
                reloadPlaces()
            },
            onDelete: deletePlanet
        )
    }

    private var placeSheets: PlaceSheets {
        PlaceSheets(
            model: model,
            player: player,
            isReadOnly: isReadOnly,
            isShowingSettings: $isShowingSettings,
            isShowingRoulette: $isShowingRoulette,
            isShowingOnboarding: $isShowingOnboarding,
            detailPlace: $detailPlace,
            editingPlace: $editingPlace,
            tripSummary: $tripSummary,
            isShowingFriends: isShowingFriends,
            onDetailDismissed: {
                // After the detail screen the player with this record stays on the map.
                if stage == .map, selectedPlaceID != nil { isPlayerVisible = true }
            },
            onPlacesChanged: reloadPlaces,
            onDelete: delete(placeID:)
        )
    }

    // MARK: - Planets

    /// Planet on the big globe; `nil` on the friends grid page.
    private var currentPlanet: PlanetPage? {
        if let focus { return focus.current.page }
        return slot.planet
    }

    /// Which places are shown: a planet, or all friend planets on the grid page.
    private var currentScope: PlaceScope {
        if let currentPlanet { return currentPlanet.scope }
        return .maps(directory?.friendMapIDs ?? [])
    }

    private var isReadOnly: Bool { currentPlanet?.isReadOnly ?? true }

    /// Show a planet: mine, paired or an added friend's planet.
    private func show(_ page: PlanetPage) {
        focus = nil
        switch page {
        case .own(let id):
            slot = .own(id)
        case .shared(let id):
            slot = .shared(id)
        case .friend(let id):
            // A single friend — their planet gets its own page; otherwise the grid page.
            if directory?.friendStacks.count == 1 {
                slot = .friend(id)
            } else {
                let index = directory?.friendStacks.firstIndex { $0.planets.contains { $0.page == page } } ?? 0
                slot = .friends(index / HomeScreen.stacksPerPage)
            }
        }
        if stage == .map { returnToPlanet() }
    }

    /// The planet was deleted or a friend hid theirs — go back to an existing one.
    private func validateSelection() {
        guard let directory else { return }
        let main = HomeSlot.own(directory.mainPlanetID)
        switch slot {
        case .own(let id):
            if !directory.ownPlanets.contains(where: { $0.page.mapID == id }) { slot = main }
        case .shared(let id):
            if !directory.sharedPlanets.contains(where: { $0.page.mapID == id }) { slot = main }
        case .friends(let page):
            let stacks = directory.friendStacks
            let pages = (stacks.count + HomeScreen.stacksPerPage - 1) / HomeScreen.stacksPerPage
            if stacks.count == 1, let first = stacks[0].planets.first {
                // Only one friend left — their page instead of the grid.
                slot = .friend(first.page.mapID)
            } else if pages == 0 {
                slot = main
            } else if page >= pages {
                slot = .friends(pages - 1)
            }
        case .friend(let id):
            let stacks = directory.friendStacks
            if stacks.count != 1 || !stacks[0].planets.contains(where: { $0.page.mapID == id }) {
                slot = stacks.isEmpty ? main : .friends(0)
            }
        }
        if let focus {
            if let stack = directory.friendStacks.first(where: { $0.ownerID == focus.stack.ownerID }) {
                self.focus?.stack = stack
                self.focus?.index = min(focus.index, stack.planets.count - 1)
            } else {
                self.focus = nil
            }
        }
    }

    /// Places of the shown planet — immediately, when they are needed right now (map, roulette).
    private func syncScope() {
        scopeTask?.cancel()
        if model?.scope != currentScope { model?.scope = currentScope }
    }

    /// My planet is deleted with its places, a paired one only on my side, a friend's planet only from the screen.
    private func deletePlanet(_ page: PlanetPage) {
        switch page {
        case .own: try? directory?.deleteOwnPlanet(page)
        case .shared: try? directory?.deleteShared(page)
        case .friend: try? directory?.removeFromScreen(page)
        }
        Haptics.warning()
        validateSelection()
        reloadPlaces()
    }

    /// Nearby friends see us only while the app is open.
    private func updateNearby(for phase: ScenePhase) {
        guard environment.profiles.me != nil else { return }
        switch phase {
        case .active: environment.nearby.start()
        case .background: environment.nearby.stop()
        default: break
        }
    }

    // MARK: - Transitions

    /// Tap on a planet dot: the map fades in while the globe camera moves onto the dot.
    private func enterMap(at coordinate: CLLocationCoordinate2D) {
        syncScope()
        isMapMounted = true
        zoom.reset()
        mapCommand = .land(latitude: coordinate.latitude, longitude: coordinate.longitude)
        withAnimation(.easeInOut(duration: 0.55)) { stage = .map }
    }

    /// Back to planets: the planet always settles the same way — on the region with the most records.
    private func returnToPlanet() {
        guard stage == .map else { return }
        selectedPlaceID = nil
        isPlayerVisible = false
        player.stop()
        globeCommand = .returnHome
        Haptics.select()
        withAnimation(.easeInOut(duration: 0.6)) {
            stage = .planet
            zoom.reset()
        }
    }

    /// Tap on an "on this day" notification: the planet holding that place and the map above it.
    private func open(placeID: UUID) {
        guard let managed = model?.managedPlace(with: placeID), let mapID = managed.map?.id else { return }
        switch managed.map?.kind {
        case .shared: show(.shared(mapID))
        case .friend: return
        default: show(.own(mapID))
        }
        model?.scope = currentScope
        guard let place = model?.place(with: placeID) else { return }
        isMapMounted = true
        withAnimation(.easeInOut(duration: 0.4)) { stage = .map }
        selectedPlaceID = place.id
        isPlayerVisible = true
        mapCommand = .center(latitude: place.latitude, longitude: place.longitude, meters: 1200)
    }

    // MARK: - Data

    private func bootstrap() {
        guard model == nil else { return }
        environment.dayCycle.start()
        // Places are read during the splash — by its end the dots are already on the planet.
        let created = PlanetDirectory(persistence: environment.persistence, profiles: environment.profiles)
        directory = created
        slot = .own(created.mainPlanetID)
        let map = MapViewModel(persistence: environment.persistence)
        map.scope = created.mainPlanet.scope
        map.reload()
        model = map
    }

    private func afterSplash() {
        if !environment.settings.hasCompletedOnboarding {
            isShowingOnboarding = true
        }

        // The map is prepared in advance, hidden: the first move from the planet runs without a hitch
        // from creating MapKit.
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            isMapMounted = true
        }

        // Notifications and geofences wake system services — only after the first planet frame.
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(600))
            await environment.prepareNotifications()
            await environment.refreshOnThisDaySchedule()
            if environment.settings.geofencesEnabled {
                await environment.geofences.refresh()
            }
            updateNearby(for: scenePhase)
            await model?.backfillPlaceInfo(using: environment.location)
        }
    }

    private func reloadPlaces() {
        model?.reload()
        directory?.reload()
        Task {
            await environment.refreshOnThisDaySchedule()
            if environment.settings.geofencesEnabled {
                await environment.geofences.refresh()
            }
        }
    }

    private func delete(placeID: UUID) {
        detailPlace = nil
        selectedPlaceID = nil
        isPlayerVisible = false
        player.stop()
        model?.delete(placeID: placeID)
        Haptics.warning()
        reloadPlaces()
    }
}

struct TripRequest: Identifiable {
    let id: UUID
}

struct FriendRequest: Identifiable {
    let id: UUID
}

struct DetailRequest: Identifiable {
    let id: UUID
}

struct EditRequest: Identifiable {
    let id: UUID
}

// MARK: - Sheets

/// Home screen sheets: profile, "Add Planet", friends, planet caption and deletion.
private struct PlanetSheets: ViewModifier {
    @Environment(AppEnvironment.self) private var environment

    let directory: PlanetDirectory?
    @Binding var isShowingProfile: Bool
    @Binding var isShowingAddPlanet: Bool
    @Binding var isShowingFriends: Bool
    @Binding var deletingPlanet: PlanetPage?
    let isDay: Bool
    let onShow: (PlanetPage) -> Void
    let onShowFromFriends: (PlanetPage) -> Void
    let onDataChanged: () -> Void
    let onDelete: (PlanetPage) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingProfile) {
                ProfileScreen(planets: directory?.ownPlanets ?? [])
            }
            .sheet(isPresented: $isShowingAddPlanet) {
                if let directory {
                    AddPlanetSheet(directory: directory, isDay: isDay, onShow: onShow)
                }
            }
            .sheet(isPresented: $isShowingFriends) {
                FriendsScreen(onShowPlanet: onShowFromFriends, onDataChanged: onDataChanged)
            }
            .sheet(item: Binding(
                get: { environment.pendingSoundmapURL.map(ImportRequest.init(url:)) },
                set: { if $0 == nil { environment.clearPendingSoundmap() } }
            )) { request in
                SoundmapImportSheet(url: request.url, onImported: onDataChanged)
            }
            .confirmationDialog(Text("planet.delete.confirm", comment: "Delete planet?"),
                                isPresented: Binding(get: { deletingPlanet != nil },
                                                     set: { if !$0 { deletingPlanet = nil } }),
                                titleVisibility: .visible) {
                Button(role: .destructive) {
                    if let page = deletingPlanet { onDelete(page) }
                    deletingPlanet = nil
                } label: {
                    Text("planet.delete", comment: "Delete planet")
                }
            } message: {
                Text("planet.delete.message", comment: "The planet's places are deleted with it")
            }
            .alert(
                Text("friends.request.title", comment: "Incoming friend request title"),
                isPresented: Binding(get: { incomingRequest != nil && !isShowingFriends }, set: { _ in }),
                presenting: incomingRequest
            ) { _ in
                Button(role: .cancel) {
                    environment.nearby.respond(accept: false)
                } label: {
                    Text("friends.request.decline", comment: "Decline")
                }
                Button {
                    Haptics.success()
                    environment.nearby.respond(accept: true)
                } label: {
                    Text("friends.request.accept", comment: "Accept")
                }
            } message: { request in
                Text("friends.request.message \(request.profile.nickname)",
                     comment: "Who wants to add you as a friend")
            }
    }

    private var incomingRequest: NearbyService.IncomingRequest? {
        guard environment.profiles.me != nil else { return nil }
        return environment.nearby.incomingRequest
    }
}

/// Place sheets: settings, roulette, detail screen, editing, import, trip, onboarding.
private struct PlaceSheets: ViewModifier {
    @Environment(AppEnvironment.self) private var environment

    let model: MapViewModel?
    let player: PreviewAudioPlayer
    let isReadOnly: Bool
    @Binding var isShowingSettings: Bool
    @Binding var isShowingRoulette: Bool
    @Binding var isShowingOnboarding: Bool
    @Binding var detailPlace: DetailRequest?
    @Binding var editingPlace: EditRequest?
    @Binding var tripSummary: TripRequest?
    let isShowingFriends: Bool
    let onDetailDismissed: () -> Void
    let onPlacesChanged: () -> Void
    let onDelete: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(onPlacesChanged: onPlacesChanged)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingRoulette) {
                if let model {
                    RouletteView(model: model, player: player,
                                 defaultSkinID: environment.settings.defaultSkinID,
                                 onChangeSkin: isReadOnly ? nil : { id, skin in model.setSkin(skin, for: id) }) { id in
                        isShowingRoulette = false
                        detailPlace = DetailRequest(id: id)
                    }
                    .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(DS.Radius.sheet)
                    // Roulette background — the blurred map or planet underneath.
                    .presentationBackground(.ultraThinMaterial)
                }
            }
            .sheet(item: $detailPlace, onDismiss: onDetailDismissed) { request in
                if let place = model?.place(with: request.id) {
                    PlaceDetailView(
                        place: place,
                        player: player,
                        loader: environment.mediaLoader,
                        onEdit: isReadOnly ? nil : {
                            detailPlace = nil
                            editingPlace = EditRequest(id: place.id)
                        },
                        onDelete: isReadOnly ? nil : { onDelete(place.id) }
                    )
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $editingPlace) { request in
                AddPlaceView(editingPlaceID: request.id, onSaved: onPlacesChanged)
                    .presentationDetents([.fraction(0.7), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(DS.Radius.sheet)
            }
            .sheet(item: Binding(
                get: { environment.pendingImportURL.map(ImportRequest.init(url:)) },
                set: { if $0 == nil { environment.clearPendingImport() } }
            )) { request in
                HistoryImportSheet(url: request.url)
            }
            .sheet(item: $tripSummary) { request in
                TripSummaryView(tripID: request.id, onSaved: onPlacesChanged)
            }
            .fullScreenCover(isPresented: $isShowingOnboarding) {
                OnboardingView(onFinish: onPlacesChanged)
            }
    }
}

import CoreLocation
import SwiftUI

/// Map screen, laid out per the sketch:
/// top right — settings, below them the vertical timeline and "my location";
/// bottom center — "+", bottom right — the record stack (roulette).
/// A long press on the map also adds a place — a dart flies into the point.
struct MapScreen: View {
    @Environment(AppEnvironment.self) private var environment

    let model: MapViewModel
    let player: PreviewAudioPlayer
    @Binding var selectedPlaceID: UUID?
    /// The player at the bottom appears after the detail screen.
    @Binding var isPlayerVisible: Bool
    @Binding var command: MapCommand?
    /// A friend's planet: view only — no "+" and no long press.
    var isReadOnly = false
    /// My or a paired planet: new places go into it.
    var targetMapID: UUID?
    var isDay = false

    let onOpenSettings: () -> Void
    let onOpenRoulette: () -> Void
    let onOpenDetail: (UUID) -> Void
    let onReturnToPlanet: () -> Void
    let onZoomOutProgress: (Double, CLLocationCoordinate2D, Bool) -> Void
    /// The "back" button — to the planet.
    let onBack: () -> Void
    let onPlacesChanged: () -> Void

    @State private var timeline = YearTimeline()
    @State private var clusterPlaces: ClusterSelection?
    @State private var pendingPlace: PendingPlace?
    @State private var tripError: String?
    /// "All" mode: a strip of records from the nearest.
    @State private var isAllMode = false
    /// Order of the "All" strip — identifiers only; snapshots are read page by page while scrolling.
    @State private var allOrder: [UUID] = []
    @State private var stripCenteredID: UUID?
    /// The map center is kept outside SwiftUI state: otherwise every map movement
    /// would rebuild the screen together with the pins.
    @State private var mapCenter = CenterBox()
    @State private var openTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            PlaceMapView(
                places: visiblePlaces,
                placesToken: .init(regionRevision: model.regionRevision, yearIndex: timeline.selectedIndex),
                pinStyle: environment.settings.pinStyle,
                defaultSkinID: environment.settings.defaultSkinID,
                isDay: isDay,
                onTapPlace: open,
                onCenterChange: { [mapCenter] in mapCenter.value = $0 },
                onVisibleRegionChange: { [model] center, latitudeDelta, longitudeDelta in
                    model.visibleRegionChanged(center: center, latitudeDelta: latitudeDelta,
                                               longitudeDelta: longitudeDelta)
                },
                selectedPlaceID: $selectedPlaceID,
                command: $command,
                dartCoordinate: pendingPlace?.coordinate,
                onOpenCluster: { clusterPlaces = ClusterSelection(places: $0) },
                onLongPress: { coordinate in
                    guard !isReadOnly else { return }
                    startAddingPlace(at: coordinate)
                },
                playingPlaceID: playingPlaceID,
                onZoomedOutToPlanet: onReturnToPlanet,
                onZoomOutProgress: onZoomOutProgress
            )
            .ignoresSafeArea()
            .animation(DS.Motion.standard, value: timeline.selectedIndex)

            controls

            VStack(spacing: DS.Spacing.s) {
                if isPlayerVisible, let place = selectedPlace {
                    CompactPlaceCard(
                        place: place,
                        player: player,
                        onOpenDetail: { onOpenDetail(place.id) },
                        onClose: closeCard
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if isAllMode {
                    AllRecordsStrip(ids: allOrder,
                                    model: model,
                                    defaultSkinID: environment.settings.defaultSkinID,
                                    centeredID: $stripCenteredID,
                                    onOpen: open)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.bottom, isAllMode ? DS.Spacing.s : 96)
        }
        .animation(DS.Motion.standard, value: isPlayerVisible)
        .animation(DS.Motion.standard, value: isAllMode)
        .animation(DS.Motion.standard, value: selectedPlaceID)
        .onAppear { timeline.rebuild(from: model.index) }
        .onChange(of: model.revision) { _, _ in
            timeline.rebuild(from: model.index)
            if isAllMode { allOrder = NearestOrdering.sorted(model.index, from: mapCenter.value).map(\.id) }
        }
        .onChange(of: selectedPlaceID) { _, newValue in
            if newValue == nil {
                player.stop()
                isPlayerVisible = false
            }
        }
        .onChange(of: stripCenteredID) { _, id in
            // The strip was scrolled — the map immediately moves to the new record.
            guard let id, let place = model.place(with: id) else { return }
            // Strip — the map immediately settles on this record from city distance.
            selectedPlaceID = id
            command = .center(latitude: place.latitude, longitude: place.longitude, meters: Self.cityMeters)
        }
        .sheet(item: $pendingPlace) { pending in
            AddPlaceView(initialCoordinate: pending.coordinate, targetMapID: targetMapID) {
                pendingPlace = nil
                onPlacesChanged()
            }
            .presentationDetents([.fraction(0.7), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(DS.Radius.sheet)
        }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { tripError != nil }, set: { if !$0 { tripError = nil } })) {
            Button(role: .cancel) { tripError = nil } label: { Text("common.ok", comment: "OK") }
        } message: {
            Text(tripError ?? "")
        }
        .sheet(item: $clusterPlaces) { selection in
            ClusterListView(places: selection.places) { place in
                clusterPlaces = nil
                open(place.id)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                GlassIconButton(systemImage: "chevron.backward", accessibilityKey: "map.back", action: onBack)
                Spacer()
                VStack(spacing: DS.Spacing.m) {
                    GlassIconButton(systemImage: "gearshape", accessibilityKey: "map.settings",
                                    action: onOpenSettings)

                    AllButton(isOn: isAllMode, action: toggleAllMode)
                        .disabled(model.isEmpty)

                    if environment.settings.timelineEnabled, !model.isEmpty {
                        VerticalTimeline(timeline: timeline)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    }

                    GlassIconButton(systemImage: "location", accessibilityKey: "map.myLocation") {
                        Task {
                            _ = await environment.location.requestWhenInUseAuthorization()
                            command = .followUser
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.s)

            Spacer()

            if !isAllMode {
                bottomButtons
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: environment.settings.timelineEnabled)
    }

    private var bottomButtons: some View {
        ZStack {
            if !isReadOnly {
                Button {
                    Haptics.tap()
                    startAddingPlace(at: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(DS.Colors.accent, in: Circle())
                        .shadow(color: DS.Colors.accent.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("map.addPlace", comment: "Add place"))
                .contextMenu {
                    // Long press on "+" — start a trip.
                    if environment.trips.active == nil {
                        Button(action: startTrip) {
                            Label {
                                Text("trip.start", comment: "Start trip")
                            } icon: {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    onOpenRoulette()
                } label: {
                    VinylStackIcon()
                        .frame(width: DS.Size.tapTarget + 8, height: DS.Size.tapTarget + 8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .liquidGlass(in: Circle())
                .disabled(model.isEmpty)
                .accessibilityLabel(Text("map.roulette", comment: "Record roulette"))
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.bottom, DS.Spacing.m)
    }

    // MARK: - State

    private var visiblePlaces: [PlaceSnapshot] {
        environment.settings.timelineEnabled ? timeline.filter(model.regionPlaces) : model.regionPlaces
    }

    private var selectedPlace: PlaceSnapshot? {
        guard let selectedPlaceID else { return nil }
        return model.place(with: selectedPlaceID)
    }

    /// The place whose preview is playing — its pin spins.
    private var playingPlaceID: UUID? {
        guard player.isPlaying, let url = player.currentURL else { return nil }
        // Only an on-screen pin spins — its snapshot is already in the loaded region.
        return model.regionPlaces.first { $0.previewURL == url }?.id
    }

    // MARK: - Actions

    /// City scale: the record itself is visible from here, not a stack.
    static let cityMeters: CLLocationDistance = 25_000

    /// Tap on a record: first the map zooms to it at city level,
    /// then the music starts and the detail screen opens.
    /// The player appears once the user leaves it.
    /// In "All" mode the first tap highlights the record in the strip, the second opens it.
    private func open(_ placeID: UUID) {
        guard let place = model.place(with: placeID) else { return }
        if isAllMode, selectedPlaceID != placeID {
            stripCenteredID = placeID
            return
        }
        openTask?.cancel()
        Haptics.select()
        isPlayerVisible = false
        selectedPlaceID = placeID
        command = .center(latitude: place.latitude, longitude: place.longitude, meters: Self.cityMeters)

        openTask = Task {
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, selectedPlaceID == placeID else { return }
            if let preview = place.previewURL { player.play(preview) }
            onOpenDetail(placeID)
        }
    }

    /// "All": the button lights up, the nearest record is highlighted and goes first in the strip.
    private func toggleAllMode() {
        Haptics.tap()
        if isAllMode {
            isAllMode = false
            stripCenteredID = nil
            return
        }
        Task {
            let origin = await nearestOrigin()
            allOrder = NearestOrdering.sorted(model.index, from: origin).map(\.id)
            isAllMode = true
            stripCenteredID = allOrder.first
        }
    }

    /// Where to look for the nearest: around me if location is allowed, otherwise at the map center.
    private func nearestOrigin() async -> CLLocationCoordinate2D {
        if await environment.location.authorization.allowsForegroundUse,
           let fix = try? await environment.location.currentFix() {
            return fix.coordinate
        }
        return mapCenter.value
    }

    /// `nil` — adding via the "+" button: the place is taken from the current location.
    private func startAddingPlace(at coordinate: CLLocationCoordinate2D?) {
        closeCard()
        pendingPlace = PendingPlace(coordinate: coordinate)
    }

    private func startTrip() {
        Task {
            do {
                try await environment.trips.start()
            } catch {
                tripError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func closeCard() {
        openTask?.cancel()
        selectedPlaceID = nil
        isPlayerVisible = false
        player.stop()
    }
}

/// The "All" circle: turns on the strip of records from the nearest.
private struct AllButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "All")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                .background {
                    if isOn {
                        Circle()
                            .fill(DS.Colors.accent)
                            .shadow(color: DS.Colors.accent.opacity(0.7), radius: 10)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text("map.all", comment: "All records, nearest first"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A point chosen with a long press, or `nil` for "+".
struct PendingPlace: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D?
}

/// A stack of places at one point.
struct ClusterSelection: Identifiable {
    let id = UUID()
    let places: [PlaceSnapshot]
}

/// Expanding a stack as a list when there is nothing left to zoom into.
struct ClusterListView: View {
    let places: [PlaceSnapshot]
    let onSelect: (PlaceSnapshot) -> Void

    var body: some View {
        NavigationStack {
            List(places) { place in
                Button {
                    onSelect(place)
                } label: {
                    HStack(spacing: DS.Spacing.m) {
                        ArtworkImage(url: place.artworkURL, cornerRadius: 6)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.displayTitle).lineLimit(1)
                            Text(place.eventDate?.formatted() ?? place.displaySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(Text("map.stack", comment: "Place stack title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// The last map center — a plain reference without observation.
final class CenterBox {
    var value = CLLocationCoordinate2D(latitude: 48, longitude: 10)
}

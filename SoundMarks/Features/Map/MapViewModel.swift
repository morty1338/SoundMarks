import CoreData
import CoreLocation
import Foundation
import Observation

/// Map data. All of the planet's places are kept only as lightweight entries (`index`),
/// full snapshots only for the area visible on the map and for strip pages.
@MainActor
@Observable
final class MapViewModel {
    /// All of the planet's places: coordinates, dates, country. For the timeline, "All", roulette and counts.
    private(set) var index: [PlaceIndexEntry] = []
    /// Snapshots of places in the visible map area plus a margin — these are what the pins show.
    private(set) var regionPlaces: [PlaceSnapshot] = [] {
        didSet { regionRevision &+= 1 }
    }
    /// Grows with every change of `regionPlaces`: the map reconciles pins only when it changed.
    private(set) var regionRevision = 0
    /// Grows with every change of places: strips and the timeline rebuild on it.
    private(set) var revision = 0
    private(set) var loadError: String?

    /// Which planet is shown: mine, a friend's or a shared map.
    var scope: PlaceScope = .mine {
        didSet { if scope != oldValue { reload() } }
    }

    var isEmpty: Bool { index.isEmpty }

    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let reader: BackgroundReader
    @ObservationIgnored private var changes: StoreChanges?
    /// Area `regionPlaces` was read for; `nil` — the map has not reported its region yet.
    @ObservationIgnored private var box: GeoBox?
    @ObservationIgnored private var regionTask: Task<Void, Never>?
    @ObservationIgnored private var regionGeneration = 0
    /// Snapshots of strip pages (roulette, "All") and opened places — as needed.
    @ObservationIgnored private var pageCache: [UUID: PlaceSnapshot] = [:]

    /// How many snapshots a strip reads at once.
    static let pageSize = 20

    init(persistence: PersistenceController) {
        self.persistence = persistence
        reader = BackgroundReader(context: persistence.newBackgroundContext())
        // Only places, tracks, media and maps: route points and geofence marks don't affect the map.
        changes = StoreChanges(entities: ["Place", "Track", "MediaItem", "MemoryMap"]) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        do {
            index = try PlaceQueries.index(scope: scope, in: persistence.viewContext)
            loadError = nil
        } catch {
            Log.persistence.error("Could not read places: \(error.localizedDescription, privacy: .public)")
            loadError = AppError.persistenceUnavailable(reason: error.localizedDescription).errorDescription
        }
        pageCache.removeAll()
        revision &+= 1
        loadRegion()
    }

    // MARK: - Map region

    /// The map reports what is visible. Places are re-read only when the visible part
    /// left the loaded area with its margin, or the map was zoomed in several times.
    func visibleRegionChanged(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) {
        let needed = GeoBox(center: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        if let box, box.contains(center: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta),
           // Zoomed in several times — release far-away pins so only the surroundings stay in memory.
           box.halfLatitude <= needed.halfLatitude * 4 {
            return
        }
        box = needed
        loadRegion()
    }

    /// Region snapshots are read in the background: the main thread does not wait for Core Data while panning.
    private func loadRegion() {
        guard let box else { return }
        regionGeneration &+= 1
        let generation = regionGeneration
        let scope = scope
        regionTask?.cancel()
        regionTask = Task { [reader] in
            let places = try? await reader.read { context in
                try PlaceQueries.snapshots(scope: scope, box: box, in: context)
            }
            guard !Task.isCancelled, generation == regionGeneration, let places else { return }
            if places != regionPlaces { regionPlaces = places }
        }
    }

    // MARK: - Snapshots on demand

    /// Snapshot of a place in a strip by position: the page around it is read — visible ones and neighbors.
    func snapshot(at position: Int, in ids: [UUID]) -> PlaceSnapshot? {
        guard ids.indices.contains(position) else { return nil }
        if let cached = pageCache[ids[position]] { return cached }
        if pageCache.count > Self.pageSize * 12 { pageCache.removeAll() }
        let start = position / Self.pageSize * Self.pageSize
        let page = Array(ids[start..<min(start + Self.pageSize, ids.count)])
        for place in (try? PlaceQueries.snapshots(ids: page, in: persistence.viewContext)) ?? [] {
            pageCache[place.id] = place
        }
        return pageCache[ids[position]]
    }

    func place(with id: UUID) -> PlaceSnapshot? {
        if let cached = pageCache[id] ?? regionPlaces.first(where: { $0.id == id }) { return cached }
        guard let place = managedPlace(with: id)?.snapshot() else { return nil }
        pageCache[id] = place
        return place
    }

    /// Managed object for screens that edit a place.
    func managedPlace(with id: UUID) -> Place? {
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? persistence.viewContext.fetch(request).first
    }

    func delete(placeID: UUID) {
        guard let place = managedPlace(with: placeID) else { return }
        place.markDeleted()
        do {
            try persistence.save()
            reload()
        } catch let error as AppError {
            loadError = error.errorDescription
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Record skin for a place; `nil` — the default skin.
    func setSkin(_ skinID: String?, for placeID: UUID) {
        guard let place = managedPlace(with: placeID) else { return }
        place.skinID = skinID
        try? persistence.save()
        reload()
    }

    /// Places from Phase 1 stored the address as one line ("Spandauer Straße, Berlin")
    /// and did not know the city and country. We fill them in in the background, one request at a time:
    /// reverse geocoding is rate-limited.
    func backfillPlaceInfo(using location: any LocationService) async {
        let request = Place.fetchRequest(scope: .mine)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            PlaceScope.mine.predicate,
            NSPredicate(format: "city == nil"),
        ])
        guard let places = try? persistence.viewContext.fetch(request), !places.isEmpty else { return }

        for place in places {
            guard !Task.isCancelled else { return }
            guard let info = await location.placeInfo(for: place.coordinate), info.city != nil else { continue }
            place.placeName = info.shortName ?? place.placeName
            place.city = info.city
            place.country = info.country
            try? persistence.save()
            try? await Task.sleep(for: .milliseconds(1200))
        }
        reload()
    }
}

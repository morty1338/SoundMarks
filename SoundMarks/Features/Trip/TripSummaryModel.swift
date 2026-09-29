import CoreData
import CoreLocation
import Foundation
import Observation

/// Trip summary: route, records along the way, photos from the trip dates, tracks.
/// The user marks which stops to save as places.
@MainActor
@Observable
final class TripSummaryModel {
    enum Phase: Equatable {
        case loading
        case ready
    }

    let tripID: UUID
    private(set) var phase: Phase = .loading
    var name = ""
    private(set) var interval: DateInterval?
    private(set) var route: [RouteSample] = []
    private(set) var stops: [TripStop] = []
    /// All significant plays during the trip.
    private(set) var plays: [PlayRecord] = []
    private(set) var photos: [PhotoAssetSnapshot] = []
    /// Places already saved from this trip.
    private(set) var savedPlaces: [PlaceSnapshot] = []
    private(set) var hasHistory = true
    private(set) var hasPhotoAccess = true

    var selectedStopIDs: Set<UUID> = []
    /// The stop's chosen track (index in `plays`), the first by default.
    var trackChoice: [UUID: Int] = [:]
    private(set) var placeInfo: [UUID: PlaceInfo] = [:]
    private(set) var isSaving = false
    var errorMessage: String?

    @ObservationIgnored private let environment: AppEnvironment

    init(tripID: UUID, environment: AppEnvironment) {
        self.tripID = tripID
        self.environment = environment
    }

    var isHistory: Bool { !savedPlaces.isEmpty }

    var selectedCount: Int { stops.filter { selectedStopIDs.contains($0.id) }.count }

    func selectedPlay(of stop: TripStop) -> PlayRecord? {
        let index = trackChoice[stop.id] ?? 0
        return stop.plays.indices.contains(index) ? stop.plays[index] : stop.plays.first
    }

    // MARK: - Loading

    func load() async {
        guard let trip = environment.trips.trip(id: tripID) else { return }
        name = trip.name ?? ""
        interval = trip.dateInterval
        route = environment.trips.route(of: tripID)
        let tripPlaces = Array((trip.places ?? []).filter { !$0.isTombstoned })
        savedPlaces = trip.managedObjectContext.map { PlaceQueries.snapshots(of: tripPlaces, in: $0) } ?? []
            .sorted { ($0.eventDate?.year ?? 0, $0.createdAt) < ($1.eventDate?.year ?? 0, $1.createdAt) }

        guard let interval else {
            phase = .ready
            return
        }

        // Last.fm history may not have finished loading — fetch it for the trip dates.
        if await environment.lastFm.isConnected {
            _ = try? await environment.lastFm.syncHistory(in: interval) { _ in }
        }
        plays = await PlayHistoryStore.shared.plays(in: interval).filter(\.isMeaningfulPlayback)
        hasHistory = !(await PlayHistoryStore.shared.isEmpty)

        do {
            photos = try await environment.photos.snapshots(in: interval, requiringLocation: false)
        } catch {
            photos = []
            hasPhotoAccess = false
        }

        let route = route, plays = plays, photos = photos
        stops = await Task.detached(priority: .userInitiated) {
            TripMatcher.stops(route: route, plays: plays, photos: photos)
        }.value
        selectedStopIDs = Set(stops.map(\.id))
        phase = .ready

        await geocodeStops()
    }

    /// Stop names — one at a time, reverse geocoding is rate-limited.
    private func geocodeStops() async {
        for stop in stops.prefix(20) where placeInfo[stop.id] == nil {
            guard !Task.isCancelled else { return }
            if let info = await environment.location.placeInfo(for: stop.coordinate) {
                placeInfo[stop.id] = info
            }
        }
    }

    // MARK: - Actions

    func toggle(_ stop: TripStop) {
        if selectedStopIDs.contains(stop.id) {
            selectedStopIDs.remove(stop.id)
        } else {
            selectedStopIDs.insert(stop.id)
        }
        Haptics.select()
    }

    func rename() {
        guard let trip = environment.trips.trip(id: tripID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != trip.name else { return }
        trip.name = trimmed
        try? environment.persistence.save()
    }

    /// Saves the marked stops as places on my planet, linked to the trip.
    /// - Returns: `true` if at least one place was saved.
    func save() async -> Bool {
        let chosen = stops.filter { selectedStopIDs.contains($0.id) }
        guard !chosen.isEmpty, let trip = environment.trips.trip(id: tripID) else { return false }
        rename()

        isSaving = true
        defer { isSaving = false }

        let context = environment.persistence.viewContext
        var created: [(Track, PlayRecord)] = []
        do {
            let map = try environment.persistence.ensurePersonalMap()
            for stop in chosen {
                guard let play = selectedPlay(of: stop),
                      let eventDate = EventDate(date: play.playedAt) else { continue }
                let info = placeInfo[stop.id]

                let place = Place(context: context)
                place.coordinate = stop.coordinate
                place.placeName = info?.shortName
                place.city = info?.city
                place.country = info?.country
                place.eventDate = eventDate
                place.map = map
                place.trip = trip
                place.authorProfileId = environment.profiles.me?.id

                let track = Track(context: context)
                track.title = play.title
                track.artist = play.artist
                track.album = play.album
                track.spotifyURI = play.spotifyURI
                track.source = play.source
                place.track = track
                created.append((track, play))

                for (index, photo) in stop.photos.prefix(6).enumerated() {
                    let media = MediaItem(context: context)
                    media.kind = photo.kind
                    media.localIdentifier = photo.id
                    media.takenAt = photo.creationDate
                    media.order = Int16(clamping: index)
                    media.place = place
                }
            }
            try environment.persistence.save()
        } catch {
            context.rollback()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }

        // Artwork and previews — from the catalog, after saving.
        for (track, play) in created {
            if let metadata = try? await environment.metadata.metadata(artist: play.artist, title: play.title) {
                track.artworkURL = metadata.artworkURL?.absoluteString
                track.previewURL = metadata.previewURL?.absoluteString
            }
        }
        try? environment.persistence.save()
        await environment.refreshOnThisDaySchedule()
        await load()
        return !created.isEmpty
    }

    func deleteTrip() -> Bool {
        do {
            try environment.trips.delete(tripID: tripID)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

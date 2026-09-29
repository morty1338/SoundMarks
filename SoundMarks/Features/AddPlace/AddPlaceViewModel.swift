import CoreLocation
import Foundation
import Observation

/// State of the add/edit place screen.
@MainActor
@Observable
final class AddPlaceViewModel {
    var coordinate = CLLocationCoordinate2D(latitude: 52.520008, longitude: 13.404954) {
        didSet { scheduleReverseGeocode() }
    }

    private(set) var placeInfo: PlaceInfo?
    private(set) var isLocating = false

    var track: TrackMetadata?
    private(set) var trackSource: MusicSourceKind = .manual
    private(set) var isDetectingTrack = false

    var media: [PickedMedia] = []
    var note = ""

    var year: Int
    var month: Int?
    var day: Int?

    private(set) var isSaving = false
    var errorMessage: String?

    /// Editing mode for an existing place.
    var isEditing: Bool { editingPlaceID != nil }

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let initialCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored private let editingPlaceID: UUID?
    @ObservationIgnored private let targetMapID: UUID?
    @ObservationIgnored private var geocodeTask: Task<Void, Never>?
    /// When loading an existing place, don't overwrite its saved name.
    @ObservationIgnored private var suppressGeocode = false

    init(environment: AppEnvironment,
         initialCoordinate: CLLocationCoordinate2D? = nil,
         editingPlaceID: UUID? = nil,
         targetMapID: UUID? = nil) {
        self.environment = environment
        self.targetMapID = targetMapID
        self.initialCoordinate = initialCoordinate
        self.editingPlaceID = editingPlaceID

        // Defaults to today.
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        year = today.year ?? 2026
        month = today.month
        day = today.day
    }

    deinit { geocodeTask?.cancel() }

    // MARK: - Derived

    var eventDate: EventDate? { EventDate(year: year, month: month, day: day) }

    var canSave: Bool { track != nil && eventDate != nil && !isSaving }

    /// What to show under the mini map.
    var placeTitle: String? {
        [placeInfo?.shortName, placeInfo?.city]
            .compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
            .nilIfEmpty
    }

    /// The earliest capture date among the chosen media.
    var photoDateSuggestion: EventDate? {
        guard let earliest = media.compactMap(\.takenAt).min(),
              let suggested = EventDate(date: earliest),
              suggested != eventDate
        else { return nil }
        return suggested
    }

    func applyPhotoDateSuggestion() {
        guard let suggestion = photoDateSuggestion else { return }
        year = suggestion.year
        month = suggestion.month
        day = suggestion.day
    }

    // MARK: - Preparation

    func prepare() async {
        if let editingPlaceID {
            loadExisting(editingPlaceID)
            return
        }

        if let initialCoordinate {
            // The point was already chosen on the map — do not request location at all.
            coordinate = initialCoordinate
        } else {
            await useCurrentLocation()
        }
        await detectNowPlaying()
    }

    func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }

        do {
            let fix = try await environment.location.currentFix()
            coordinate = fix.coordinate
        } catch let error as AppError {
            // Without location the screen keeps working: the point can be moved on the map.
            errorMessage = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: "\n")
        } catch {
            errorMessage = AppError.locationUnavailable.errorDescription
        }
    }

    /// Fills in the track from the connected source. If there is no source,
    /// the user searches for the track manually — not an error.
    func detectNowPlaying() async {
        guard track == nil, let source = environment.activeMusicSource else { return }

        isDetectingTrack = true
        defer { isDetectingTrack = false }

        guard let record = try? await source.nowPlaying() else { return }
        trackSource = record.source

        if let resolved = try? await environment.metadata.metadata(artist: record.artist,
                                                                   title: record.title) {
            track = resolved
        } else {
            track = TrackMetadata(id: record.trackKey, title: record.title, artist: record.artist)
        }
    }

    func selectTrackManually(_ metadata: TrackMetadata) {
        track = metadata
        trackSource = .manual
    }

    func addMedia(_ picked: [PickedMedia]) {
        media.append(contentsOf: picked)
    }

    func removeMedia(_ item: PickedMedia) {
        media.removeAll { $0.id == item.id }
    }

    // MARK: - Saving

    private func targetMap() throws -> MemoryMap? {
        guard let targetMapID else { return nil }
        // My planet (there may be several) or a paired one; adding to a friend's planet is not allowed.
        guard let map = environment.sync.map(id: targetMapID), map.kind != .friend else {
            throw SyncService.Failure.mapNotFound
        }
        return map
    }

    /// - Returns: `true` if the place was saved.
    func save() async -> Bool {
        guard let track, let eventDate else {
            errorMessage = AppError.invalidEventDate.errorDescription
            return false
        }

        isSaving = true
        defer { isSaving = false }

        let context = environment.persistence.viewContext

        do {
            let place: Place
            if let editingPlaceID, let existing = fetchPlace(editingPlaceID) {
                place = existing
            } else {
                place = Place(context: context)
                place.map = try targetMap() ?? environment.persistence.ensurePersonalMap()
                // The shared map needs the author: it shows which of the two added the place.
                place.authorProfileId = environment.profiles.me?.id
            }

            place.coordinate = coordinate
            place.placeName = placeInfo?.shortName
            place.city = placeInfo?.city
            place.country = placeInfo?.country
            place.eventDate = eventDate
            place.note = note.isEmpty ? nil : note
            place.updatedAt = Date()

            let entity = place.track ?? Track(context: context)
            entity.apply(track)
            entity.source = trackSource
            place.track = entity

            // Media are rebuilt entirely: that way the order always matches the screen.
            for existing in place.media ?? [] {
                context.delete(existing)
            }
            for (index, item) in media.enumerated() {
                let mediaItem = MediaItem(context: context)
                mediaItem.kind = item.kind
                mediaItem.localIdentifier = item.localIdentifier
                mediaItem.imageData = item.data
                mediaItem.takenAt = item.takenAt
                mediaItem.order = Int16(clamping: index)
                mediaItem.place = place
            }

            try environment.persistence.save()
            Haptics.success()
            await environment.refreshOnThisDaySchedule()
            return true
        } catch let error as AppError {
            context.rollback()
            errorMessage = error.errorDescription
            return false
        } catch {
            context.rollback()
            errorMessage = AppError.persistenceUnavailable(reason: error.localizedDescription).errorDescription
            return false
        }
    }

    // MARK: - Editing

    private func loadExisting(_ id: UUID) {
        guard let place = fetchPlace(id) else { return }

        suppressGeocode = true
        coordinate = place.coordinate
        suppressGeocode = false

        placeInfo = PlaceInfo(shortName: place.placeName, city: place.city, country: place.country)
        note = place.note ?? ""

        if let eventDate = place.eventDate {
            year = eventDate.year
            month = eventDate.month
            day = eventDate.day
        }

        if let stored = place.track, let title = stored.title {
            track = TrackMetadata(id: stored.id?.uuidString ?? title,
                                  title: title,
                                  artist: stored.artist ?? "",
                                  album: stored.album,
                                  artworkURL: stored.artworkLink,
                                  previewURL: stored.previewLink)
            trackSource = stored.source
        }

        media = place.orderedMedia.map { item in
            PickedMedia(kind: item.kind,
                        localIdentifier: item.localIdentifier,
                        data: item.imageData,
                        takenAt: item.takenAt)
        }
    }

    private func fetchPlace(_ id: UUID) -> Place? {
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? environment.persistence.viewContext.fetch(request).first
    }

    // MARK: - Place name

    private func scheduleReverseGeocode() {
        guard !suppressGeocode else { return }
        geocodeTask?.cancel()
        let target = coordinate
        geocodeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let info = await environment.location.placeInfo(for: target)
            guard !Task.isCancelled else { return }
            placeInfo = info
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

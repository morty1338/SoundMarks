import CoreLocation
import Foundation
import Observation

/// Candidate feed: confirming creates a place, skipping just removes the card.
@MainActor
@Observable
final class CandidateFeedViewModel {
    private(set) var confirmedCount = 0
    private(set) var skippedCount = 0
    var errorMessage: String?

    @ObservationIgnored let scanner: MemoryScanner
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var geocodedIDs: Set<UUID> = []

    init(scanner: MemoryScanner, environment: AppEnvironment) {
        self.scanner = scanner
        self.environment = environment
    }

    var candidates: [MemoryCandidate] { scanner.candidates }

    /// Fills in place names for the nearest cards.
    /// Reverse geocoding is rate-limited, so we go a little at a time.
    func geocodeUpcoming(limit: Int = 3) async {
        for candidate in candidates.prefix(limit) where !geocodedIDs.contains(candidate.id) {
            geocodedIDs.insert(candidate.id)
            let info = await environment.location.placeInfo(for: candidate.coordinate)
            scanner.updatePlaceInfo(candidateID: candidate.id, info: info)
        }
    }

    func selectTrack(at index: Int, for candidate: MemoryCandidate) {
        scanner.updateSelection(candidateID: candidate.id, trackIndex: index)
    }

    func skip(_ candidate: MemoryCandidate) {
        skippedCount += 1
        scanner.remove(candidateID: candidate.id)
    }

    /// Creates a place from a candidate: track, photos and capture date.
    func confirm(_ candidate: MemoryCandidate) async {
        guard let play = candidate.selectedTrack,
              let eventDate = candidate.eventDate()
        else {
            scanner.remove(candidateID: candidate.id)
            return
        }

        // Reverse geocoding in the feed is rate-limited by the system and may not have finished —
        // on confirmation we try again, now for a single place.
        var info = candidate.placeInfo
        if info == nil {
            info = await environment.location.placeInfo(for: candidate.coordinate)
        }

        let context = environment.persistence.viewContext
        do {
            let map = try environment.persistence.ensurePersonalMap()

            let place = Place(context: context)
            place.coordinate = candidate.coordinate
            place.placeName = info?.shortName
            place.city = info?.city
            place.country = info?.country
            place.eventDate = eventDate
            place.map = map

            let track = Track(context: context)
            track.title = play.title
            track.artist = play.artist
            track.album = play.album
            track.spotifyURI = play.spotifyURI
            track.source = play.source
            place.track = track

            for (index, photo) in candidate.photos.enumerated() {
                let media = MediaItem(context: context)
                media.kind = photo.kind
                media.localIdentifier = photo.id
                media.takenAt = photo.creationDate
                media.order = Int16(clamping: index)
                media.place = place
            }

            try environment.persistence.save()
            confirmedCount += 1
            scanner.remove(candidateID: candidate.id)

            // Artwork and preview are fetched from the catalog after saving.
            await enrich(track: track, with: play)
        } catch let error as AppError {
            context.rollback()
            errorMessage = error.errorDescription
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    /// Enriches the track with artwork and a 30-second preview.
    private func enrich(track: Track, with play: PlayRecord) async {
        guard let metadata = try? await environment.metadata.metadata(artist: play.artist,
                                                                     title: play.title)
        else { return }
        track.artworkURL = metadata.artworkURL?.absoluteString
        track.previewURL = metadata.previewURL?.absoluteString
        try? environment.persistence.save()
    }

    /// Rebuilds notifications after confirmations.
    func finish() async {
        guard confirmedCount > 0 else { return }
        await environment.refreshOnThisDaySchedule()
        await environment.geofences.refresh()
    }
}

    import CoreLocation
import Foundation

/// "Track ↔ photo" matching: pure logic without PhotoKit or network
/// so it can be covered by tests.
enum MemoryMatcher {
    struct Options: Sendable {
        /// Half-width of the window around a shoot. ±30 minutes by default, configurable.
        var window: Duration = .seconds(30 * 60)
        /// Time span within which shots count as one scene.
        var maxPhotoGap: Duration = .seconds(45 * 60)
        /// Radius within which shots count as one place.
        var maxPhotoDistance: CLLocationDistance = 250
        /// How many track options to show the user.
        var maximumTrackOptions = 5

        init(window: Duration = .seconds(30 * 60),
             maxPhotoGap: Duration = .seconds(45 * 60),
             maxPhotoDistance: CLLocationDistance = 250,
             maximumTrackOptions: Int = 5) {
            self.window = window
            self.maxPhotoGap = maxPhotoGap
            self.maxPhotoDistance = maxPhotoDistance
            self.maximumTrackOptions = maximumTrackOptions
        }
    }

    /// Groups shots by time and place.
    ///
    /// Shots without a geotag are skipped: there's nowhere to take the memory's place from.
    static func cluster(photos: [PhotoAssetSnapshot], options: Options = Options()) -> [PhotoCluster] {
        let located = photos
            .filter(\.hasLocation)
            .sorted { $0.creationDate < $1.creationDate }
        guard !located.isEmpty else { return [] }

        let maxGap = options.maxPhotoGap.seconds
        var clusters: [[PhotoAssetSnapshot]] = []
        var current: [PhotoAssetSnapshot] = [located[0]]

        for photo in located.dropFirst() {
            guard let last = current.last else { continue }
            let gap = photo.creationDate.timeIntervalSince(last.creationDate)
            let distance = self.distance(from: centroid(of: current), to: photo)

            if gap <= maxGap, distance <= options.maxPhotoDistance {
                current.append(photo)
            } else {
                clusters.append(current)
                current = [photo]
            }
        }
        clusters.append(current)

        return clusters.compactMap(makeCluster(from:))
    }

    /// Builds candidates: for each group of shots picks the tracks
    /// that played in the window around the shoot.
    ///
    /// - Plays shorter than 30 seconds are dropped.
    /// - The same track appears in a window once — the closest in time is taken.
    /// - Groups without matches don't make it into the result.
    static func candidates(photos: [PhotoAssetSnapshot],
                           plays: [PlayRecord],
                           options: Options = Options()) -> [MemoryCandidate] {
        let meaningful = plays
            .filter(\.isMeaningfulPlayback)
            .sorted { $0.playedAt < $1.playedAt }
        guard !meaningful.isEmpty else { return [] }

        return cluster(photos: photos, options: options).compactMap { cluster in
            let matches = tracks(for: cluster, in: meaningful, options: options)
            guard !matches.isEmpty else { return nil }
            return MemoryCandidate(id: UUID(), cluster: cluster, trackOptions: matches)
        }
    }

    /// Tracks that played in the window around a group of shots, from the closest to the farthest.
    static func tracks(for cluster: PhotoCluster,
                       in sortedPlays: [PlayRecord],
                       options: Options = Options()) -> [PlayRecord] {
        let window = options.window.seconds
        let from = cluster.interval.start.addingTimeInterval(-window)
        let to = cluster.interval.end.addingTimeInterval(window)
        let midpoint = cluster.midpoint

        var closestByTrack: [String: PlayRecord] = [:]
        for play in sortedPlays {
            if play.playedAt < from { continue }
            if play.playedAt > to { break }

            let key = play.trackKey
            if let existing = closestByTrack[key] {
                let existingDistance = abs(existing.playedAt.timeIntervalSince(midpoint))
                let candidateDistance = abs(play.playedAt.timeIntervalSince(midpoint))
                if candidateDistance < existingDistance { closestByTrack[key] = play }
            } else {
                closestByTrack[key] = play
            }
        }

        return closestByTrack.values
            .sorted { lhs, rhs in
                let left = abs(lhs.playedAt.timeIntervalSince(midpoint))
                let right = abs(rhs.playedAt.timeIntervalSince(midpoint))
                if left != right { return left < right }
                return lhs.trackKey < rhs.trackKey
            }
            .prefix(options.maximumTrackOptions)
            .map { $0 }
    }

    // MARK: - Geometry

    private static func makeCluster(from photos: [PhotoAssetSnapshot]) -> PhotoCluster? {
        guard let first = photos.first, let last = photos.last else { return nil }
        let center = centroid(of: photos)
        return PhotoCluster(
            id: UUID(),
            photos: photos,
            latitude: center.latitude,
            longitude: center.longitude,
            interval: DateInterval(start: first.creationDate, end: last.creationDate)
        )
    }

    private static func centroid(of photos: [PhotoAssetSnapshot]) -> CLLocationCoordinate2D {
        let located = photos.compactMap(\.coordinate)
        guard !located.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let latitude = located.reduce(0) { $0 + $1.latitude } / Double(located.count)
        let longitude = located.reduce(0) { $0 + $1.longitude } / Double(located.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func distance(from coordinate: CLLocationCoordinate2D,
                                 to photo: PhotoAssetSnapshot) -> CLLocationDistance {
        guard let target = photo.coordinate else { return .greatestFiniteMagnitude }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    }
}

extension Duration {
    /// Duration in seconds as `TimeInterval`.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

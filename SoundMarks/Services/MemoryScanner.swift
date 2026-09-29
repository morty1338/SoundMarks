import Foundation
import Observation

/// Scanning: takes plays and shot metadata for the chosen years
/// and assembles memory candidates.
///
/// The work runs off the main actor, the UI isn't blocked; scanning is cancellable.
@MainActor
@Observable
final class MemoryScanner {
    enum Phase: Equatable {
        case idle
        /// Top up history from a network source (Last.fm).
        case syncingHistory
        case readingPhotos
        case matching
        case finished
        case cancelled
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// 0…1 across the whole scan.
    private(set) var progress: Double = 0
    private(set) var candidates: [MemoryCandidate] = []
    /// How many geotagged shots were looked at.
    private(set) var inspectedPhotoCount = 0

    var isRunning: Bool {
        switch phase {
        case .syncingHistory, .readingPhotos, .matching: true
        default: false
        }
    }

    @ObservationIgnored private let photos: any PhotoService
    @ObservationIgnored private let history: PlayHistoryStore
    @ObservationIgnored private let syncingSources: [any HistorySyncing]
    @ObservationIgnored private var task: Task<Void, Never>?

    init(photos: any PhotoService,
         history: PlayHistoryStore = .shared,
         syncingSources: [any HistorySyncing] = []) {
        self.photos = photos
        self.history = history
        self.syncingSources = syncingSources
    }

    deinit { task?.cancel() }

    /// Starts scanning for the chosen years.
    /// - Parameter options: matching window and grouping parameters.
    func start(years: [Int], options: MemoryMatcher.Options, calendar: Calendar = .current) {
        guard !isRunning else { return }
        task?.cancel()

        candidates = []
        inspectedPhotoCount = 0
        progress = 0
        phase = .readingPhotos

        let sortedYears = Array(Set(years)).sorted()
        guard !sortedYears.isEmpty else {
            phase = .finished
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await run(years: sortedYears, options: options, calendar: calendar)
            } catch is CancellationError {
                phase = .cancelled
            } catch let error as AppError {
                phase = .failed(error.errorDescription ?? "")
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { phase = .cancelled }
    }

    func reset() {
        cancel()
        candidates = []
        progress = 0
        inspectedPhotoCount = 0
        phase = .idle
    }

    /// Removes a candidate from the feed (confirmed or skipped).
    func remove(candidateID: UUID) {
        candidates.removeAll { $0.id == candidateID }
    }

    func updateSelection(candidateID: UUID, trackIndex: Int) {
        guard let index = candidates.firstIndex(where: { $0.id == candidateID }) else { return }
        candidates[index].selectedTrackIndex = trackIndex
    }

    func updatePlaceInfo(candidateID: UUID, info: PlaceInfo?) {
        guard let index = candidates.firstIndex(where: { $0.id == candidateID }) else { return }
        candidates[index].placeInfo = info
    }

    // MARK: - Progress

    private func run(years: [Int], options: MemoryMatcher.Options, calendar: Calendar) async throws {
        let intervals = years.compactMap { Self.interval(for: $0, calendar: calendar) }
        guard let overall = Self.union(of: intervals) else {
            phase = .finished
            return
        }

        // 1. Top up history from network sources if they are connected.
        let connected = await connectedSyncingSources()
        if !connected.isEmpty {
            phase = .syncingHistory
            for source in connected {
                try Task.checkCancellation()
                _ = try? await source.syncHistory(in: overall) { _ in }
            }
        }

        // 2. Shot metadata — by year, to show progress.
        phase = .readingPhotos
        var snapshots: [PhotoAssetSnapshot] = []
        for (index, interval) in intervals.enumerated() {
            try Task.checkCancellation()
            let batch = try await photos.snapshots(in: interval, requiringLocation: true)
            snapshots.append(contentsOf: batch)
            inspectedPhotoCount = snapshots.count
            // Reading photos is the main part of the work, it gets 80% of the scale.
            progress = Double(index + 1) / Double(intervals.count) * 0.8
        }

        // 3. Matching.
        try Task.checkCancellation()
        phase = .matching
        progress = 0.85

        let plays = await history.plays(in: overall)
        let found = await Task.detached(priority: .userInitiated) {
            MemoryMatcher.candidates(photos: snapshots, plays: plays, options: options)
        }.value

        try Task.checkCancellation()
        candidates = found.sorted { $0.cluster.interval.start > $1.cluster.interval.start }
        progress = 1
        phase = .finished
    }

    private func connectedSyncingSources() async -> [any HistorySyncing] {
        var result: [any HistorySyncing] = []
        for source in syncingSources where await source.isConnected {
            result.append(source)
        }
        return result
    }

    // MARK: - Periods

    nonisolated static func interval(for year: Int, calendar: Calendar = .current) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    nonisolated static func union(of intervals: [DateInterval]) -> DateInterval? {
        guard let first = intervals.min(by: { $0.start < $1.start }),
              let last = intervals.max(by: { $0.end < $1.end })
        else { return nil }
        return DateInterval(start: first.start, end: last.end)
    }
}

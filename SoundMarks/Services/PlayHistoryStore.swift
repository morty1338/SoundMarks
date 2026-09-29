import Foundation

/// Local store of imported listening history.
///
/// Deliberately NOT in Core Data: history is large intermediate material
/// that shouldn't go to CloudKit. After confirmation only places remain
/// on the device; the history can be deleted with one button.
actor PlayHistoryStore {
    static let shared = PlayHistoryStore()

    /// What's in the store: period and volume.
    struct Summary: Hashable, Sendable, Codable {
        let playCount: Int
        let earliest: Date?
        let latest: Date?
        let sources: [MusicSourceKind]

        var coveredInterval: DateInterval? {
            guard let earliest, let latest, earliest <= latest else { return nil }
            return DateInterval(start: earliest, end: latest)
        }

        static let empty = Summary(playCount: 0, earliest: nil, latest: nil, sources: [])
    }

    private let fileURL: URL
    /// In-memory cache sorted by time: binary search runs over it.
    private var cached: [PlayRecord]?

    init(fileName: String = "play-history.json") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(fileName)
    }

    // MARK: - Reading

    func summary() -> Summary {
        let records = load()
        guard !records.isEmpty else { return .empty }
        var sources: [MusicSourceKind] = []
        for record in records where !sources.contains(record.source) {
            sources.append(record.source)
        }
        return Summary(playCount: records.count,
                       earliest: records.first?.playedAt,
                       latest: records.last?.playedAt,
                       sources: sources)
    }

    var isEmpty: Bool { load().isEmpty }

    /// Plays for an interval, in ascending time order.
    func plays(in interval: DateInterval) -> [PlayRecord] {
        let records = load()
        guard !records.isEmpty else { return [] }

        let lower = lowerBound(of: interval.start, in: records)
        guard lower < records.count else { return [] }

        var upper = lower
        while upper < records.count, records[upper].playedAt <= interval.end {
            upper += 1
        }
        return Array(records[lower..<upper])
    }

    /// Years that have plays — for the period chips.
    func yearsWithPlays(calendar: Calendar = .current) -> [Int] {
        var years: Set<Int> = []
        for record in load() {
            years.insert(calendar.component(.year, from: record.playedAt))
        }
        return years.sorted(by: >)
    }

    // MARK: - Writing

    /// Adds plays, removing duplicates by time and track.
    @discardableResult
    func merge(_ incoming: [PlayRecord]) throws -> Summary {
        guard !incoming.isEmpty else { return summary() }

        var byKey: [String: PlayRecord] = [:]
        for record in load() + incoming {
            // The same play may have come from different sources.
            byKey["\(Int(record.playedAt.timeIntervalSince1970))|\(record.trackKey)"] = record
        }

        let merged = byKey.values.sorted { $0.playedAt < $1.playedAt }
        try persist(merged)
        return summary()
    }

    func removeAll() {
        cached = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Disk

    private func load() -> [PlayRecord] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: fileURL) else {
            cached = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let records = (try? decoder.decode([PlayRecord].self, from: data)) ?? []
        cached = records
        return records
    }

    private func persist(_ records: [PlayRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
            cached = records
        } catch {
            Log.music.error("History not saved: \(error.localizedDescription, privacy: .public)")
            throw AppError.persistenceUnavailable(reason: error.localizedDescription)
        }
    }

    /// Index of the first entry not earlier than `date`.
    private func lowerBound(of date: Date, in records: [PlayRecord]) -> Int {
        var low = 0
        var high = records.count
        while low < high {
            let middle = (low + high) / 2
            if records[middle].playedAt < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

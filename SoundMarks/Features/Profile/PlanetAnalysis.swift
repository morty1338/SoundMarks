import Foundation

/// Result of a planet analysis for a period: where you were and what you listened to.
struct PlanetAnalysisReport: Equatable, Sendable {
    struct Ranked: Equatable, Sendable, Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    var places = 0
    var countries = 0
    var cities = 0
    var topCities: [Ranked] = []
    var topArtists: [Ranked] = []
    var topTracks: [Ranked] = []
    /// The month with the most places marked.
    var busiestMonth: DateComponents?
    /// Listening history for the same period.
    var plays = 0
    var listeningHours: Double = 0
    var historyTopArtists: [Ranked] = []

    var isEmpty: Bool { places == 0 && plays == 0 }
}

/// The analysis runs on the device — nothing is sent anywhere.
enum PlanetAnalysis {
    /// When the source doesn't report a duration, the track counts as three minutes.
    static let assumedPlay: TimeInterval = 180

    static func report(places: [PlaceSnapshot], plays: [PlayRecord], interval: DateInterval,
                       calendar: Calendar = .current, limit: Int = 5) -> PlanetAnalysisReport {
        let inPeriod = places.filter { place in
            guard let date = place.timelineDate(calendar: calendar) else { return false }
            return interval.contains(date)
        }
        let meaningful = plays.filter { $0.isMeaningfulPlayback && interval.contains($0.playedAt) }

        var report = PlanetAnalysisReport()
        report.places = inPeriod.count
        report.countries = distinct(inPeriod.map(\.country)).count
        report.cities = distinct(inPeriod.map(\.city)).count
        report.topCities = ranked(inPeriod.compactMap { $0.city ?? $0.placeName }, limit: limit)
        report.topArtists = ranked(inPeriod.compactMap(\.trackArtist), limit: limit)
        report.topTracks = ranked(inPeriod.compactMap { place in
            guard let title = place.trackTitle else { return nil }
            return [title, place.trackArtist].compactMap { $0 }.joined(separator: " — ")
        }, limit: limit)

        let months = inPeriod.compactMap { place -> DateComponents? in
            guard let event = place.eventDate, let month = event.month else { return nil }
            return DateComponents(year: event.year, month: month)
        }
        report.busiestMonth = Dictionary(grouping: months, by: { $0 })
            .max { lhs, rhs in
                lhs.value.count != rhs.value.count
                    ? lhs.value.count < rhs.value.count
                    : (lhs.key.year ?? 0, lhs.key.month ?? 0) < (rhs.key.year ?? 0, rhs.key.month ?? 0)
            }?.key

        report.plays = meaningful.count
        report.listeningHours = meaningful.reduce(0) { total, play in
            total + (play.playedDuration.map { Double($0.components.seconds) } ?? assumedPlay)
        } / 3600
        report.historyTopArtists = ranked(meaningful.map(\.artist), limit: limit)
        return report
    }

    private static func distinct(_ values: [String?]) -> Set<String> {
        Set(values.compactMap { $0?.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    /// The most frequent values; ties broken alphabetically.
    private static func ranked(_ values: [String], limit: Int) -> [PlanetAnalysisReport.Ranked] {
        var counts: [String: (name: String, count: Int)] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            counts[key, default: (trimmed, 0)].count += 1
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(limit)
            .map { PlanetAnalysisReport.Ranked(name: $0.name, count: $0.count) }
    }
}

import Foundation

/// Profile stats over my places.
struct ProfileStats: Equatable, Sendable {
    var places = 0
    var countries = 0
    var cities = 0
    /// Distinct artists.
    var artists = 0
    /// Years in which places are marked: the earliest.
    var firstYear: Int?

    var rank: Rank { RankLadder.rank(forPlaceCount: places) }

    static func make(from places: [PlaceSnapshot]) -> ProfileStats {
        make(count: places.count,
             countries: places.map(\.country),
             cities: places.map(\.city),
             artists: places.map(\.trackArtist),
             years: places.compactMap { $0.eventDate?.year })
    }

    /// From separate fields — for a dictionary query, without place snapshots.
    static func make(count: Int, countries: [String?], cities: [String?], artists: [String?],
                     years: [Int]) -> ProfileStats {
        func distinct(_ values: [String?]) -> Int {
            Set(values.compactMap { $0?.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }).count
        }
        return ProfileStats(places: count,
                            countries: distinct(countries),
                            cities: distinct(cities),
                            artists: distinct(artists),
                            firstYear: years.min())
    }
}

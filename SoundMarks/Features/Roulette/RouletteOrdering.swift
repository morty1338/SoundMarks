import Foundation

/// Roulette sorting and grouping.
enum RouletteSort: String, CaseIterable, Identifiable, Sendable {
    /// Newest memories first.
    case date
    /// By country, within it — newest to oldest.
    case country
    /// By year, newest to oldest.
    case year

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .date: String(localized: "roulette.sort.date", defaultValue: "By date")
        case .country: String(localized: "roulette.sort.country", defaultValue: "By country")
        case .year: String(localized: "roulette.sort.year", defaultValue: "By year")
        }
    }
}

/// Pure record ordering logic — covered by tests.
enum RouletteOrdering {
    static func ordered<Item: PlaceOrderable>(_ places: [Item], by sort: RouletteSort) -> [Item] {
        switch sort {
        case .date, .year:
            return places.sorted { newerFirst($0, $1) }
        case .country:
            return places.sorted { lhs, rhs in
                let left = lhs.country ?? ""
                let right = rhs.country ?? ""
                if left != right {
                    // Places without a country — at the end.
                    if left.isEmpty { return false }
                    if right.isEmpty { return true }
                    return left.localizedStandardCompare(right) == .orderedAscending
                }
                return newerFirst(lhs, rhs)
            }
        }
    }

    /// Caption of the group the record belongs to: country or year.
    static func group(of place: some PlaceOrderable, by sort: RouletteSort) -> String? {
        switch sort {
        case .date: nil
        case .country: place.country
        case .year: place.eventDate.map { String($0.year) }
        }
    }

    private static func newerFirst<Item: PlaceOrderable>(_ lhs: Item, _ rhs: Item) -> Bool {
        switch (lhs.eventDate, rhs.eventDate) {
        case let (left?, right?) where left != right: left > right
        case (nil, _?): false
        case (_?, nil): true
        default: lhs.createdAt > rhs.createdAt
        }
    }
}

import Foundation

/// Record skin: how the disc looks on the map, in the roulette and in the stack.
struct RecordSkin: Identifiable, Hashable, Sendable {
    let id: String
    /// Disc image in Assets; `nil` — a drawn record with the artwork on the label.
    let assetName: String?
    /// From which rank it unlocks.
    let requiredRank: Int

    /// Exclusive ones — only for a high rank.
    var isExclusive: Bool { requiredRank >= RankLadder.exclusiveFrom }

    var name: String {
        switch id {
        case "classic": String(localized: "skin.classic", defaultValue: "Black vinyl")
        case "orbits": String(localized: "skin.orbits", defaultValue: "Orbits")
        case "palms": String(localized: "skin.palms", defaultValue: "Palms")
        case "solar": String(localized: "skin.solar", defaultValue: "Solar system")
        case "waves": String(localized: "skin.waves", defaultValue: "Lava")
        case "nosmoking": String(localized: "skin.nosmoking", defaultValue: "No smoking")
        case "cosmos": String(localized: "skin.cosmos", defaultValue: "Cosmos")
        case "shrooms": String(localized: "skin.shrooms", defaultValue: "Shrooms")
        case "eyes": String(localized: "skin.eyes", defaultValue: "Eyes")
        case "street": String(localized: "skin.street", defaultValue: "Night street")
        case "alien": String(localized: "skin.alien", defaultValue: "Alien")
        case "truffula": String(localized: "skin.truffula", defaultValue: "Truffula forest")
        default: String(localized: "skin.standard", defaultValue: "Cover")
        }
    }
}

/// All skins. The order is as in the profile: from unlocked right away to exclusive.
enum SkinCatalog {
    static let standardID = "standard"

    static let all: [RecordSkin] = [
        RecordSkin(id: standardID, assetName: nil, requiredRank: 0),
        RecordSkin(id: "classic", assetName: "Skin_classic", requiredRank: 0),
        RecordSkin(id: "orbits", assetName: "Skin_orbits", requiredRank: 1),
        RecordSkin(id: "palms", assetName: "Skin_palms", requiredRank: 1),
        RecordSkin(id: "solar", assetName: "Skin_solar", requiredRank: 2),
        RecordSkin(id: "waves", assetName: "Skin_waves", requiredRank: 2),
        RecordSkin(id: "nosmoking", assetName: "Skin_nosmoking", requiredRank: 2),
        RecordSkin(id: "cosmos", assetName: "Skin_cosmos", requiredRank: 3),
        RecordSkin(id: "shrooms", assetName: "Skin_shrooms", requiredRank: 3),
        RecordSkin(id: "eyes", assetName: "Skin_eyes", requiredRank: 4),
        RecordSkin(id: "street", assetName: "Skin_street", requiredRank: 4),
        RecordSkin(id: "alien", assetName: "Skin_alien", requiredRank: 5),
        RecordSkin(id: "truffula", assetName: "Skin_truffula", requiredRank: 5),
    ]

    static func skin(id: String?) -> RecordSkin {
        all.first { $0.id == id } ?? all[0]
    }

    static func unlocked(at rank: Int) -> [RecordSkin] {
        all.filter { $0.requiredRank <= rank }
    }
}

/// Rank: grows with the number of marked places and unlocks skins.
struct Rank: Hashable, Sendable {
    let level: Int
    /// How many places are needed for this rank.
    let threshold: Int
    /// How many are needed for the next one; `nil` — the rank is the maximum.
    let nextThreshold: Int?

    var title: String {
        switch level {
        case 0: String(localized: "rank.0", defaultValue: "Rookie")
        case 1: String(localized: "rank.1", defaultValue: "Listener")
        case 2: String(localized: "rank.2", defaultValue: "Collector")
        case 3: String(localized: "rank.3", defaultValue: "DJ")
        case 4: String(localized: "rank.4", defaultValue: "Music lover")
        default: String(localized: "rank.5", defaultValue: "Legend")
        }
    }

    /// Fraction of the way to the next rank, 0…1.
    func progress(placeCount: Int) -> Double {
        guard let nextThreshold else { return 1 }
        let span = Double(nextThreshold - threshold)
        return min(max(Double(placeCount - threshold) / span, 0), 1)
    }
}

enum RankLadder {
    /// How many places are needed for each rank.
    static let thresholds = [0, 5, 15, 30, 60, 100]
    /// From which rank skins are exclusive.
    static let exclusiveFrom = 4

    static func rank(forPlaceCount count: Int) -> Rank {
        let level = thresholds.lastIndex { count >= $0 } ?? 0
        let next = thresholds.indices.contains(level + 1) ? thresholds[level + 1] : nil
        return Rank(level: level, threshold: thresholds[level], nextThreshold: next)
    }
}

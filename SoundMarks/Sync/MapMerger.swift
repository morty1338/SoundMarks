import Foundation

/// Merging maps between devices. Pure logic — covered by tests.
///
/// Rules:
/// - places are matched by UUID;
/// - on conflict the later edit wins (`updatedAt`, last-writer-wins);
/// - a deletion is an edit too: a marker with a later `updatedAt` deletes the place,
///   and an edit later than the deletion brings it back;
/// - with equal times the local version stays — the result is the same on both devices.
enum MapMerger {
    struct Plan: Equatable, Sendable {
        /// What to write locally: new places, fresher edits and deletions.
        var apply: [PlaceDTO]
        /// How many incoming places were ignored as outdated.
        var ignored: Int
    }

    static func plan(local: [PlaceDTO], incoming: [PlaceDTO]) -> Plan {
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var apply: [PlaceDTO] = []
        var ignored = 0

        for candidate in incoming {
            if let existing = byID[candidate.id] {
                if candidate.updatedAt > existing.updatedAt {
                    apply.append(candidate)
                } else {
                    ignored += 1
                }
            } else {
                // An unknown marker is stored too: otherwise an outdated copy
                // from another source would "resurrect" the deleted place.
                apply.append(candidate)
            }
        }
        return Plan(apply: apply, ignored: ignored)
    }

    /// The resulting set after merging — to check that both sides converge.
    static func merged(local: [PlaceDTO], incoming: [PlaceDTO]) -> [PlaceDTO] {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for place in plan(local: local, incoming: incoming).apply {
            byID[place.id] = place
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Changes since the last sync — only these are sent.
    static func changes(in places: [PlaceDTO], since date: Date?) -> [PlaceDTO] {
        guard let date else { return places }
        return places.filter { $0.updatedAt > date }
    }
}

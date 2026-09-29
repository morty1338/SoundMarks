import CoreData
import CoreLocation
import Foundation

/// A lightweight place entry: everything needed for ordering, counting and the timeline, without track and media.
/// A thousand such entries are read with one dictionary query in a couple of milliseconds.
struct PlaceIndexEntry: Hashable, Sendable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let eventDate: EventDate?
    let createdAt: Date
    let country: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The map area we keep places for: the visible part plus a margin around it.
struct GeoBox: Equatable, Sendable {
    let centerLatitude: Double
    let centerLongitude: Double
    let halfLatitude: Double
    let halfLongitude: Double

    /// How many visible areas to add on each side.
    static let margin = 1.0

    /// The visible map area expanded by `margin` on each side.
    init(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double, margin: Double = margin) {
        let scale = 0.5 + margin
        centerLatitude = center.latitude
        centerLongitude = SphereMapping.normalized(center.longitude)
        halfLatitude = latitudeDelta * scale
        halfLongitude = longitudeDelta * scale
    }

    /// Whole world: at this extent places aren't filtered — clusters collect all of them anyway.
    var isWholeWorld: Bool { halfLatitude >= 60 || halfLongitude >= 150 }

    /// The visible area is entirely inside — no need to re-read places.
    func contains(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) -> Bool {
        if isWholeWorld { return true }
        let latitudeFits = abs(center.latitude - centerLatitude) + latitudeDelta / 2 <= halfLatitude
        let longitudeShift = abs(SphereMapping.normalized(center.longitude - centerLongitude))
        return latitudeFits && longitudeShift + longitudeDelta / 2 <= halfLongitude
    }

    /// Coordinate predicate; `nil` — the whole world. Crossing 180° — with two ranges.
    var predicate: NSPredicate? {
        guard !isWholeWorld else { return nil }
        let latitude = NSPredicate(format: "latitude >= %lf AND latitude <= %lf",
                                   centerLatitude - halfLatitude, centerLatitude + halfLatitude)
        let west = centerLongitude - halfLongitude
        let east = centerLongitude + halfLongitude
        let longitude: NSPredicate
        if west < -180 {
            longitude = NSPredicate(format: "longitude >= %lf OR longitude <= %lf", west + 360, east)
        } else if east > 180 {
            longitude = NSPredicate(format: "longitude >= %lf OR longitude <= %lf", west, east - 360)
        } else {
            longitude = NSPredicate(format: "longitude >= %lf AND longitude <= %lf", west, east)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [latitude, longitude])
    }
}

/// Place queries without extras: dictionaries instead of objects where objects are not needed,
/// and media in one query per batch of places instead of lazy loading per place.
///
/// The functions are called on the given context's queue.
enum PlaceQueries {
    /// Map order: from old memories to new ones.
    static var chronological: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "eventYear", ascending: true),
            NSSortDescriptor(key: "eventMonth", ascending: true),
            NSSortDescriptor(key: "eventDay", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
    }

    // MARK: - Lightweight index

    /// All of a planet's places as lightweight entries — one dictionary query, no Core Data objects.
    static func index(scope: PlaceScope, in context: NSManagedObjectContext) throws -> [PlaceIndexEntry] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Place")
        request.resultType = .dictionaryResultType
        request.predicate = scope.predicate
        request.sortDescriptors = chronological
        request.propertiesToFetch = ["id", "latitude", "longitude", "eventYear", "eventMonth", "eventDay",
                                     "createdAt", "country"]
        return try context.fetch(request).compactMap { row in
            guard let id = row["id"] as? UUID else { return nil }
            return PlaceIndexEntry(
                id: id,
                latitude: (row["latitude"] as? Double) ?? 0,
                longitude: (row["longitude"] as? Double) ?? 0,
                eventDate: EventDate(storedYear: (row["eventYear"] as? Int16) ?? 0,
                                     storedMonth: (row["eventMonth"] as? Int16) ?? 0,
                                     storedDay: (row["eventDay"] as? Int16) ?? 0),
                createdAt: (row["createdAt"] as? Date) ?? .distantPast,
                country: row["country"] as? String
            )
        }
    }

    /// Coordinates of live places per map — for the dots on planets. Place objects aren't created.
    static func coordinatesByMap(in context: NSManagedObjectContext) throws
        -> [NSManagedObjectID: [SphereMapping.Coordinate]] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Place")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "isTombstoned == NO AND map != nil")
        request.propertiesToFetch = ["latitude", "longitude", "map"]
        var result: [NSManagedObjectID: [SphereMapping.Coordinate]] = [:]
        for row in try context.fetch(request) {
            guard let map = row["map"] as? NSManagedObjectID else { continue }
            result[map, default: []].append(SphereMapping.Coordinate(
                latitude: (row["latitude"] as? Double) ?? 0,
                longitude: (row["longitude"] as? Double) ?? 0
            ))
        }
        return result
    }

    /// Fields for profile stats — as dictionaries, without tracks and media in memory.
    static func stats(scope: PlaceScope, in context: NSManagedObjectContext) throws -> ProfileStats {
        let request = NSFetchRequest<NSDictionary>(entityName: "Place")
        request.resultType = .dictionaryResultType
        request.predicate = scope.predicate
        request.propertiesToFetch = ["country", "city", "eventYear", "track.artist"]
        let rows = try context.fetch(request)
        return ProfileStats.make(
            count: rows.count,
            countries: rows.map { $0["country"] as? String },
            cities: rows.map { $0["city"] as? String },
            artists: rows.map { $0["track.artist"] as? String },
            years: rows.compactMap { row in
                EventDate(storedYear: (row["eventYear"] as? Int16) ?? 0, storedMonth: 0, storedDay: 0)?.year
            }
        )
    }

    // MARK: - Snapshots

    /// Snapshots of a planet's places in a map area; `box == nil` or the whole world — all places.
    static func snapshots(scope: PlaceScope, box: GeoBox?,
                          in context: NSManagedObjectContext) throws -> [PlaceSnapshot] {
        let request = Place.fetchRequest(scope: scope)
        if let region = box?.predicate {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [scope.predicate, region])
        }
        request.sortDescriptors = chronological
        request.relationshipKeyPathsForPrefetching = ["track"]
        return snapshots(of: try context.fetch(request), in: context)
    }

    /// Snapshots by identifier — in the same order. For strips that load page by page.
    static func snapshots(ids: [UUID], in context: NSManagedObjectContext) throws -> [PlaceSnapshot] {
        guard !ids.isEmpty else { return [] }
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        request.relationshipKeyPathsForPrefetching = ["track"]
        let byID = Dictionary(snapshots(of: try context.fetch(request), in: context).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// Snapshots of a batch of places. Media are read with one dictionary query: neither the media objects
    /// nor their photos are loaded into memory — previously the `imageData != nil` check read
    /// every photo copy from disk.
    static func snapshots(of places: [Place], in context: NSManagedObjectContext) -> [PlaceSnapshot] {
        // The dictionary query can't see unsaved edits — such places are read the old way.
        let stored = places.filter { !$0.objectID.isTemporaryID && !$0.hasChanges }
        let media = (try? mediaByPlace(stored, in: context)) ?? [:]
        return places.compactMap { place in
            if place.objectID.isTemporaryID || place.hasChanges {
                return place.snapshot(media: place.inMemoryMedia)
            }
            return place.snapshot(media: media[place.objectID] ?? [])
        }
    }

    private static func mediaByPlace(_ places: [Place], in context: NSManagedObjectContext) throws
        -> [NSManagedObjectID: [PlaceSnapshot.Media]] {
        guard !places.isEmpty else { return [:] }

        let embedded = NSFetchRequest<NSDictionary>(entityName: "MediaItem")
        embedded.resultType = .dictionaryResultType
        embedded.predicate = NSPredicate(format: "place IN %@ AND imageData != nil", places)
        embedded.propertiesToFetch = ["id"]
        let embeddedIDs = Set(try context.fetch(embedded).compactMap { $0["id"] as? UUID })

        let request = NSFetchRequest<NSDictionary>(entityName: "MediaItem")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "place IN %@", places)
        request.propertiesToFetch = ["id", "typeRaw", "localIdentifier", "takenAt", "order", "place"]

        var rows: [NSManagedObjectID: [(order: Int16, media: PlaceSnapshot.Media)]] = [:]
        for row in try context.fetch(request) {
            guard let place = row["place"] as? NSManagedObjectID, let id = row["id"] as? UUID else { continue }
            let media = PlaceSnapshot.Media(
                id: id,
                kind: (row["typeRaw"] as? String).flatMap(MediaKind.init(rawValue:)) ?? .photo,
                localIdentifier: row["localIdentifier"] as? String,
                hasEmbeddedData: embeddedIDs.contains(id),
                takenAt: row["takenAt"] as? Date
            )
            rows[place, default: []].append(((row["order"] as? Int16) ?? 0, media))
        }
        // The same order as `Place.orderedMedia`.
        return rows.mapValues { items in
            items.sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return (lhs.media.takenAt ?? .distantPast) < (rhs.media.takenAt ?? .distantPast)
            }
            .map(\.media)
        }
    }
}

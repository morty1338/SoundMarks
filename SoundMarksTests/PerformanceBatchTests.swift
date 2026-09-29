import CoreData
import CoreLocation
import SceneKit
import Testing
import UIKit

@testable import SoundMarks

/// Batched planet markers: the halo shader compiles and draws, a tap hits the dot.
@Suite("Batched planet markers")
@MainActor
struct GlobeBatchTests {
    /// Frame brightness sum and the number of pink pixels (that's how SceneKit draws a shader that failed to compile).
    private func stats(of scene: GlobeScene, size: CGFloat = 200) -> (brightness: Double, magenta: Int)? {
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.scene = scene.scene
        view.pointOfView = scene.cameraNode
        view.backgroundColor = .clear
        guard let cgImage = view.snapshot().cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let order = cgImage.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let isBGRA = order == CGBitmapInfo.byteOrder32Little.rawValue
        var brightness = 0.0
        var magenta = 0
        let step = cgImage.bitsPerPixel / 8
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = y * cgImage.bytesPerRow + x * step
                let first = Double(bytes[offset]), second = Double(bytes[offset + 1]), third = Double(bytes[offset + 2])
                let (r, g, b) = isBGRA ? (third, second, first) : (first, second, third)
                brightness += r + g + b
                if r > 200, b > 200, g < 80 { magenta += 1 }
            }
        }
        return (brightness, magenta)
    }

    private var cluster: [SphereMapping.Coordinate] {
        (0..<30).map { SphereMapping.Coordinate(latitude: Double($0 % 6) * 5 - 12, longitude: Double($0 / 6) * 5 + 5) }
    }

    @Test("Batched halos render without a pink fill", arguments: [false, true])
    func glowBatchDraws(isDay: Bool) throws {
        let empty = GlobeScene(style: .mini)
        empty.setDaylight(isDay)
        empty.face(longitude: 15, animated: false)
        let withDots = GlobeScene(style: .mini)
        withDots.setDaylight(isDay)
        withDots.setPlaces(cluster)
        withDots.face(longitude: 15, animated: false)

        let base = try #require(stats(of: empty))
        let marked = try #require(stats(of: withDots))
        #expect(marked.magenta == 0)
        #expect(marked.brightness != base.brightness, "markers were not drawn")
    }

    @Test("Flags and pushpins are merged and render", arguments: [PlanetMarkerStyle.flag, .pushpin])
    func solidBatchDraws(style: PlanetMarkerStyle) throws {
        let globe = GlobeScene(style: .main)
        globe.setMarkerStyle(style)
        globe.setPlaces(cluster)
        globe.face(longitude: 15, animated: false)
        let result = try #require(stats(of: globe, size: 300))
        #expect(result.magenta == 0)
    }

    @Test("A tap on a dot finds the place, the far side does not")
    func hitTesting() throws {
        let globe = GlobeScene(style: .main)
        let place = SphereMapping.Coordinate(latitude: 10, longitude: 20)
        globe.setPlaces([place])
        globe.face(longitude: 20, animated: false)
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        view.scene = globe.scene
        view.pointOfView = globe.cameraNode

        let position = SphereMapping.position(latitude: 10, longitude: 20, radius: 1.006)
        let world = globe.spin.presentation.simdWorldTransform
            * simd_float4(Float(position.x), Float(position.y), Float(position.z), 1)
        let projected = view.projectPoint(SCNVector3(world.x, world.y, world.z))
        let hit = globe.dot(at: CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)), in: view, tolerance: 20)
        #expect(hit != nil)

        globe.face(longitude: -160, animated: false)
        let hidden = globe.dot(at: CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)), in: view, tolerance: 20)
        #expect(hidden == nil)
    }
}

/// Merging dots with the latitude cutoff gives exactly the same result as the full distance check.
@Suite("Planet dot merging")
struct PlanetDotsMergeTests {
    private func reference(_ coordinates: [SphereMapping.Coordinate], mergeDistance: Double) -> [PlanetDots.Dot] {
        var clusters: [(sum: SIMD3<Double>, count: Int, center: SphereMapping.Coordinate)] = []
        for coordinate in coordinates {
            if let index = clusters.firstIndex(where: {
                SphereMapping.angularDistance($0.center, coordinate) <= mergeDistance
            }) {
                clusters[index].sum += SphereMapping.position(latitude: coordinate.latitude, longitude: coordinate.longitude)
                clusters[index].count += 1
                clusters[index].center = SphereMapping.coordinate(of: clusters[index].sum)
            } else {
                clusters.append((SphereMapping.position(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                 1, coordinate))
            }
        }
        return clusters.map { PlanetDots.Dot(coordinate: $0.center, count: $0.count) }
    }

    @Test("Matches the previous algorithm", arguments: [1.5, 2.5, 12])
    func matchesReference(mergeDistance: Double) {
        var generator = SystemRandomNumberGenerator()
        var coordinates: [SphereMapping.Coordinate] = []
        for _ in 0..<800 {
            coordinates.append(SphereMapping.Coordinate(latitude: Double.random(in: -60...70, using: &generator),
                                                        longitude: Double.random(in: -180...180, using: &generator)))
        }
        #expect(PlanetDots.dots(for: coordinates, mergeDistance: mergeDistance)
            == reference(coordinates, mergeDistance: mergeDistance))
    }
}

/// Place queries: map region, pages by identifier, media without reading photos.
@Suite("Place queries")
@MainActor
struct PlaceQueriesTests {
    private func addPlace(_ persistence: PersistenceController, latitude: Double, longitude: Double,
                          title: String, photo: Data? = nil) throws -> Place {
        let context = persistence.viewContext
        let place = Place(context: context)
        place.map = try persistence.ensurePersonalMap()
        place.latitude = latitude
        place.longitude = longitude
        place.eventDate = EventDate(year: 2020)
        let track = Track(context: context)
        track.title = title
        place.track = track
        if let photo {
            let media = MediaItem(context: context)
            media.imageData = photo
            media.place = place
        }
        try persistence.save()
        return place
    }

    @Test("A region across 180° takes both sides")
    func antimeridian() throws {
        let persistence = PersistenceController(mode: .inMemory)
        _ = try addPlace(persistence, latitude: -17, longitude: 178, title: "Fiji")
        _ = try addPlace(persistence, latitude: -14, longitude: -175, title: "Samoa")
        _ = try addPlace(persistence, latitude: 52, longitude: 13, title: "Berlin")

        let box = GeoBox(center: CLLocationCoordinate2D(latitude: -15, longitude: 179), latitudeDelta: 6,
                         longitudeDelta: 6)
        let titles = try PlaceQueries.snapshots(scope: .mine, box: box, in: persistence.viewContext)
            .compactMap(\.trackTitle).sorted()
        #expect(titles == ["Fiji", "Samoa"])
        #expect(box.contains(center: CLLocationCoordinate2D(latitude: -15, longitude: -179),
                             latitudeDelta: 4, longitudeDelta: 4))
        #expect(!box.contains(center: CLLocationCoordinate2D(latitude: 52, longitude: 13),
                              latitudeDelta: 4, longitudeDelta: 4))
    }

    @Test("A page of snapshots keeps the identifier order, media know about the photo copy")
    func pageOrderAndMedia() throws {
        let persistence = PersistenceController(mode: .inMemory)
        let first = try addPlace(persistence, latitude: 1, longitude: 1, title: "A")
        let second = try addPlace(persistence, latitude: 2, longitude: 2, title: "B", photo: Data([1, 2, 3]))
        let ids = try [#require(second.id), #require(first.id)]

        persistence.viewContext.refreshAllObjects()
        let snapshots = try PlaceQueries.snapshots(ids: ids, in: persistence.viewContext)
        #expect(snapshots.map(\.trackTitle) == ["B", "A"])
        #expect(snapshots.first?.media.count == 1)
        #expect(snapshots.first?.media.first?.hasEmbeddedData == true)
        #expect(snapshots.last?.media.isEmpty == true)
    }

    @Test("Index and stats — without snapshots")
    func indexAndStats() throws {
        let persistence = PersistenceController(mode: .inMemory)
        _ = try addPlace(persistence, latitude: 1, longitude: 1, title: "A")
        _ = try addPlace(persistence, latitude: 2, longitude: 2, title: "B")
        let index = try PlaceQueries.index(scope: .mine, in: persistence.viewContext)
        #expect(index.count == 2)
        #expect(index.allSatisfy { $0.eventDate?.year == 2020 })
        let stats = try PlaceQueries.stats(scope: .mine, in: persistence.viewContext)
        #expect(stats.places == 2)
        #expect(stats.firstYear == 2020)
    }
}

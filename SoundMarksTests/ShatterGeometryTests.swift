import CoreGraphics
import Foundation
import Testing

@testable import SoundMarks

/// Splash shards cover the record without gaps and don't change between launches.
@Suite("ShatterGeometry")
struct ShatterGeometryTests {
    @Test("Shards cover the ring from the hole to the edge")
    func shardsCoverTheRecord() {
        let options = ShatterGeometry.Options(wedges: 9, holeRadius: 0.11, arcSteps: 24)
        let shards = ShatterGeometry.shards(options: options)
        let total = shards.reduce(0) { $0 + $1.area }
        // Arcs are approximated by polylines — the area is slightly less than the circle.
        let expected = ShatterGeometry.coveredArea(options: options)
        #expect(abs(total - expected) / expected < 0.01)
    }

    @Test("Two shards per wedge")
    func twoShardsPerWedge() {
        #expect(ShatterGeometry.shards(options: .init(wedges: 7)).count == 14)
    }

    @Test("All vertices are inside the disc")
    func pointsInsideDisc() {
        for shard in ShatterGeometry.shards() {
            for point in shard.points {
                #expect(hypot(point.x, point.y) <= 1.0001)
            }
        }
    }

    @Test("The same seed gives the same shards")
    func deterministic() {
        #expect(ShatterGeometry.shards(seed: 7) == ShatterGeometry.shards(seed: 7))
        #expect(ShatterGeometry.shards(seed: 7) != ShatterGeometry.shards(seed: 8))
    }

    @Test("A triangle's center of mass")
    func centroid() {
        let (area, centroid) = ShatterGeometry.areaAndCentroid(of: [
            CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0), CGPoint(x: 0, y: 3),
        ])
        #expect(abs(area - 4.5) < 1e-9)
        #expect(abs(centroid.x - 1) < 1e-9 && abs(centroid.y - 1) < 1e-9)
    }
}

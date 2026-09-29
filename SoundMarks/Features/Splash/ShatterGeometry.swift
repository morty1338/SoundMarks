import CoreGraphics
import Foundation

/// Breaking a record into shards.
///
/// Works in unit disc coordinates (center at zero, radius 1) so it
/// doesn't depend on screen or photo size. The shards cover the ring from the hole
/// to the edge without gaps or overlaps: neighboring shards share borders.
enum ShatterGeometry {
    struct Shard: Identifiable, Hashable, Sendable {
        let id: Int
        /// Polygon vertices in the unit disc.
        let points: [CGPoint]
        /// Center of mass — the shard rotates around it in flight.
        let centroid: CGPoint
        /// Area in unit disc units.
        let area: Double
        /// Random flight parameters shared by one seed.
        let speed: Double
        let spin: Double
    }

    /// Breakup parameters.
    struct Options: Sendable {
        /// How many wedges around the circle.
        var wedges = 9
        /// Radius of the center hole — it stays in place.
        var holeRadius: Double = 0.11
        /// How many points approximate the edge arc per wedge.
        var arcSteps = 6
    }

    /// Shards and cracks of one breakup.
    struct Pattern: Sendable {
        let shards: [Shard]
        /// Crack polylines: radial wedge borders and fracture lines.
        /// Drawn a moment before the shards fly apart.
        let cracks: [[CGPoint]]
    }

    /// A deterministic set of shards: the same `seed` gives the same picture.
    static func shards(seed: UInt64 = 0x5EED_CAFE, options: Options = Options()) -> [Shard] {
        pattern(seed: seed, options: options).shards
    }

    static func pattern(seed: UInt64 = 0x5EED_CAFE, options: Options = Options()) -> Pattern {
        var random = SplitMix64(seed: seed)
        let count = max(options.wedges, 3)

        // Wedge border angles: even with jitter so it doesn't look like a pie.
        let step = 2 * Double.pi / Double(count)
        let angles = (0..<count).map { index in
            Double(index) * step + random.next(in: -0.32...0.32) * step
        }

        var shards: [Shard] = []
        var cracks: [[CGPoint]] = angles.map { [polar(options.holeRadius, $0), polar(1, $0)] }

        for index in 0..<count {
            let start = angles[index]
            var end = angles[(index + 1) % count]
            if end <= start { end += 2 * Double.pi }

            // Fracture line inside a wedge: a polyline of three segments shared by two shards.
            let breakStart = random.next(in: 0.38...0.66)
            let breakEnd = random.next(in: 0.38...0.66)
            let middleAngle = start + (end - start) * random.next(in: 0.35...0.65)
            let middleRadius = (breakStart + breakEnd) / 2 + random.next(in: -0.09...0.09)

            let fault = [
                polar(breakStart, start),
                polar(middleRadius, middleAngle),
                polar(breakEnd, end),
            ]
            cracks.append(fault)

            // Inner shard: from the hole to the fracture line.
            var inner = fault
            inner.append(contentsOf: arc(radius: options.holeRadius, from: end, to: start, steps: 3))

            // Outer shard: from the fracture line to the edge.
            var outer = fault
            outer.append(contentsOf: arc(radius: 1, from: end, to: start, steps: options.arcSteps))

            for points in [inner, outer] {
                let (area, centroid) = areaAndCentroid(of: points)
                shards.append(Shard(
                    id: shards.count,
                    points: points,
                    centroid: centroid,
                    area: area,
                    speed: random.next(in: 0.75...1.25),
                    spin: random.next(in: -1...1)
                ))
            }
        }
        return Pattern(shards: shards, cracks: cracks)
    }

    /// Area of the ring covered by the shards (for checks in tests).
    static func coveredArea(options: Options = Options()) -> Double {
        Double.pi * (1 - options.holeRadius * options.holeRadius)
    }

    // MARK: - Geometry

    private static func polar(_ radius: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    /// Arc points including both ends — otherwise shard corners get cut and gaps appear.
    private static func arc(radius: Double, from start: Double, to end: Double, steps: Int) -> [CGPoint] {
        let count = max(steps, 1)
        return (0...count).map { step in
            let t = Double(step) / Double(count)
            return polar(radius, start + (end - start) * t)
        }
    }

    /// Gauss's area formula and the polygon centroid.
    static func areaAndCentroid(of points: [CGPoint]) -> (Double, CGPoint) {
        guard points.count >= 3 else { return (0, points.first ?? .zero) }

        var signedArea = 0.0
        var cx = 0.0
        var cy = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let cross = Double(a.x * b.y - b.x * a.y)
            signedArea += cross
            cx += Double(a.x + b.x) * cross
            cy += Double(a.y + b.y) * cross
        }
        signedArea /= 2
        guard abs(signedArea) > .ulpOfOne else { return (0, points[0]) }
        return (abs(signedArea), CGPoint(x: cx / (6 * signedArea), y: cy / (6 * signedArea)))
    }
}

/// A simple deterministic generator — so the shards don't change between launches.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

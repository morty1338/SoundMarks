import CoreGraphics
import Foundation
import simd

/// Coordinates on a sphere in the `SCNSphere` layout.
///
/// The layout was verified against the vertices of `SCNSphere` itself, not taken from memory:
/// `v = 0` is the north pole, `u` grows from `-Z` through `-X`, `+Z`, `+X`.
/// For an equirectangular texture (longitude −180…180 left to right) this means:
/// the prime meridian faces `+Z`, east faces `+X`, north faces `+Y`.
enum SphereMapping {
    struct Coordinate: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    /// Point on the sphere for a latitude and longitude, in degrees.
    static func position(latitude: Double, longitude: Double, radius: Double = 1) -> SIMD3<Double> {
        let lat = latitude * .pi / 180
        let lon = longitude * .pi / 180
        return SIMD3(radius * cos(lat) * sin(lon),
                     radius * sin(lat),
                     radius * cos(lat) * cos(lon))
    }

    /// Latitude and longitude of a point on the sphere (radius doesn't matter).
    static func coordinate(of position: SIMD3<Double>) -> Coordinate {
        let length = simd_length(position)
        guard length > 0 else { return Coordinate(latitude: 0, longitude: 0) }
        let unit = position / length
        let latitude = asin(max(-1, min(1, unit.y))) * 180 / .pi
        let longitude = atan2(unit.x, unit.z) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: normalized(longitude))
    }

    /// Latitude and longitude from the texture coordinates of a hit on `SCNSphere`.
    /// That's what a hit test gives — the result doesn't depend on the globe's rotation.
    static func coordinate(u: Double, v: Double) -> Coordinate {
        Coordinate(latitude: 90 - v * 180,
                   longitude: normalized(u * 360 - 180))
    }

    static func textureCoordinate(latitude: Double, longitude: Double) -> (u: Double, v: Double) {
        ((normalized(longitude) + 180) / 360, (90 - latitude) / 180)
    }

    /// Globe rotation around `Y` that brings the longitude in front of the camera (`+Z`).
    static func yawFacing(longitude: Double) -> Double {
        -longitude * .pi / 180
    }

    /// Angular distance between points, in degrees.
    static func angularDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let pa = position(latitude: a.latitude, longitude: a.longitude)
        let pb = position(latitude: b.latitude, longitude: b.longitude)
        return acos(max(-1, min(1, simd_dot(pa, pb)))) * 180 / .pi
    }

    /// Longitude in the range −180…180.
    static func normalized(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }
}

/// Glowing place dots on the planet: nearby places merge into one.
enum PlanetDots {
    struct Dot: Equatable, Sendable {
        let coordinate: SphereMapping.Coordinate
        let count: Int
    }

    /// - Parameter mergeDistance: angular distance in degrees below which dots merge.
    ///   1° ≈ 111 km.
    static func dots(for coordinates: [SphereMapping.Coordinate], mergeDistance: Double = 1.5) -> [Dot] {
        var clusters: [(sum: SIMD3<Double>, count: Int, center: SphereMapping.Coordinate, centerPoint: SIMD3<Double>)] = []

        for coordinate in coordinates {
            let point = SphereMapping.position(latitude: coordinate.latitude, longitude: coordinate.longitude)
            // The angular distance is at least the latitude difference — centers far away in latitude
            // are rejected without trigonometry; the result is the same as the full check.
            if let index = clusters.firstIndex(where: {
                abs($0.center.latitude - coordinate.latitude) <= mergeDistance
                    && acos(max(-1, min(1, simd_dot($0.centerPoint, point)))) * 180 / .pi <= mergeDistance
            }) {
                clusters[index].sum += point
                clusters[index].count += 1
                let center = SphereMapping.coordinate(of: clusters[index].sum)
                clusters[index].center = center
                clusters[index].centerPoint = SphereMapping.position(latitude: center.latitude,
                                                                     longitude: center.longitude)
            } else {
                clusters.append((point, 1, coordinate, point))
            }
        }
        return clusters.map { Dot(coordinate: $0.center, count: $0.count) }
    }
}

extension PlanetDots {
    /// Where the planet looks on the wide shot: the main region, without places — Europe.
    static func home(for coordinates: [SphereMapping.Coordinate]) -> SphereMapping.Coordinate {
        focus(for: coordinates) ?? SphereMapping.Coordinate(latitude: 48, longitude: 10)
    }

    /// The region with the most records — the planet looks there when opened.
    ///
    /// Places merge into regions larger than the dots on the planet (~1300 km)
    /// so that "many places in one country" outweighs a single far-away trip.
    static func focus(for coordinates: [SphereMapping.Coordinate],
                      regionSize: Double = 12) -> SphereMapping.Coordinate? {
        dots(for: coordinates, mergeDistance: regionSize)
            .max { $0.count < $1.count }?
            .coordinate
    }
}


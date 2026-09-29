import CoreGraphics
import Foundation
import simd
import Testing

@testable import SoundMarks

/// Latitude and longitude from a touch point on the sphere — the `SCNSphere` layout.
@Suite("SphereMapping")
struct SphereMappingTests {
    private func approx(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
        abs(a - b) < tolerance
    }

    @Test("The prime meridian at the equator faces +Z, east faces +X, north faces +Y")
    func axes() {
        let greenwich = SphereMapping.position(latitude: 0, longitude: 0)
        #expect(approx(greenwich.z, 1) && approx(greenwich.x, 0) && approx(greenwich.y, 0))

        let east = SphereMapping.position(latitude: 0, longitude: 90)
        #expect(approx(east.x, 1))

        let north = SphereMapping.position(latitude: 90, longitude: 0)
        #expect(approx(north.y, 1))
    }

    @Test("Touch texture coordinates convert to latitude and longitude")
    func textureToCoordinate() {
        // Texture center — Greenwich at the equator.
        let center = SphereMapping.coordinate(u: 0.5, v: 0.5)
        #expect(approx(center.latitude, 0) && approx(center.longitude, 0))

        // Top — north pole, bottom — south pole.
        #expect(approx(SphereMapping.coordinate(u: 0.3, v: 0).latitude, 90))
        #expect(approx(SphereMapping.coordinate(u: 0.3, v: 1).latitude, -90))

        // A quarter to the right — 90° east longitude.
        #expect(approx(SphereMapping.coordinate(u: 0.75, v: 0.5).longitude, 90))
    }

    @Test("Berlin survives the \"coordinate → texture → coordinate\" round trip")
    func berlinRoundTripThroughTexture() {
        let (u, v) = SphereMapping.textureCoordinate(latitude: 52.52, longitude: 13.405)
        let back = SphereMapping.coordinate(u: u, v: v)
        #expect(approx(back.latitude, 52.52))
        #expect(approx(back.longitude, 13.405))
    }

    @Test("A point on the sphere returns its coordinate at any radius")
    func positionRoundTrip() {
        let samples: [(Double, Double)] = [(41.39, 2.17), (-33.87, 151.21), (40.71, -74.0), (64.15, -21.94)]
        for (lat, lon) in samples {
            let point = SphereMapping.position(latitude: lat, longitude: lon, radius: 1.004)
            let back = SphereMapping.coordinate(of: point)
            #expect(approx(back.latitude, lat, 1e-9))
            #expect(approx(back.longitude, lon, 1e-9))
        }
    }

    @Test("Longitude is normalized to the range −180…180")
    func longitudeNormalization() {
        #expect(approx(SphereMapping.normalized(190), -170))
        #expect(approx(SphereMapping.normalized(-190), 170))
        #expect(approx(SphereMapping.normalized(540), 180))
    }

    @Test("Rotating the globe brings the longitude to the camera")
    func yawBringsLongitudeToFront() {
        let longitude = 13.405
        let yaw = SphereMapping.yawFacing(longitude: longitude)
        let point = SphereMapping.position(latitude: 0, longitude: longitude)
        // Rotation around Y by yaw.
        let rotated = SIMD3(point.x * cos(yaw) + point.z * sin(yaw),
                            point.y,
                            -point.x * sin(yaw) + point.z * cos(yaw))
        #expect(approx(rotated.z, 1))
        #expect(approx(rotated.x, 0))
    }

    @Test("The angular distance between Berlin and Potsdam is less than a degree")
    func angularDistance() {
        let berlin = SphereMapping.Coordinate(latitude: 52.52, longitude: 13.405)
        let potsdam = SphereMapping.Coordinate(latitude: 52.39, longitude: 13.06)
        let sydney = SphereMapping.Coordinate(latitude: -33.87, longitude: 151.21)
        #expect(SphereMapping.angularDistance(berlin, potsdam) < 1)
        #expect(SphereMapping.angularDistance(berlin, sydney) > 100)
    }
}

/// Nearby places on the planet merge into one glowing dot.
@Suite("PlanetDots")
struct PlanetDotsTests {
    @Test("Places of one city — one dot with their count")
    func nearbyPlacesMerge() {
        let berlin = [
            SphereMapping.Coordinate(latitude: 52.52, longitude: 13.40),
            SphereMapping.Coordinate(latitude: 52.50, longitude: 13.45),
            SphereMapping.Coordinate(latitude: 52.39, longitude: 13.06),
        ]
        let dots = PlanetDots.dots(for: berlin)
        #expect(dots.count == 1)
        #expect(dots.first?.count == 3)
    }

    @Test("Distant places stay separate dots")
    func distantPlacesStaySeparate() {
        let places = [
            SphereMapping.Coordinate(latitude: 52.52, longitude: 13.40),
            SphereMapping.Coordinate(latitude: 41.39, longitude: 2.17),
            SphereMapping.Coordinate(latitude: 48.86, longitude: 2.35),
        ]
        #expect(PlanetDots.dots(for: places).count == 3)
    }

    @Test("No places, no dots")
    func empty() {
        #expect(PlanetDots.dots(for: []).isEmpty)
    }
}

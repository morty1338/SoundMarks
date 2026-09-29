import CoreLocation
import Foundation
import Testing

@testable import SoundMarks

/// iOS monitors no more than 20 regions at a time — the selection must
/// fit the limit and take the nearest places.
@Suite("GeofenceSelector")
struct GeofenceSelectorTests {
    private let here = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)

    private func place(offsetKilometers: Double,
                       enabled: Bool = true,
                       id: UUID = UUID()) -> PlaceSnapshot {
        // About 111 km per degree of latitude.
        PlaceSnapshot(
            id: id,
            latitude: here.latitude + offsetKilometers / 111.0,
            longitude: here.longitude,
            placeName: nil, city: nil, country: nil, note: nil, createdAt: Date(),
            eventDate: EventDate(year: 2023, month: 5, day: 1),
            pinStyleOverride: nil, geofenceEnabled: enabled,
            trackTitle: "T", trackArtist: "A",
            artworkURL: nil, previewURL: nil, media: []
        )
    }

    @Test("No more than the system limit of 20 regions is taken")
    func respectsSystemLimit() {
        let places = (1...50).map { place(offsetKilometers: Double($0)) }
        let regions = GeofenceSelector.regions(for: places, near: here)
        #expect(regions.count == GeofenceRegion.maximumSimultaneouslyMonitored)
        #expect(regions.count == 20)
    }

    @Test("Exactly the nearest places are selected")
    func picksNearest() {
        let near = place(offsetKilometers: 1)
        let far = place(offsetKilometers: 100)
        let regions = GeofenceSelector.regions(for: [far, near], near: here, limit: 1)
        #expect(regions.map(\.id) == [near.id])
    }

    @Test("Order — by ascending distance")
    func ordersByDistance() {
        let places = [place(offsetKilometers: 30),
                      place(offsetKilometers: 5),
                      place(offsetKilometers: 12)]
        let regions = GeofenceSelector.regions(for: places, near: here)
        #expect(regions.map(\.id) == [places[1].id, places[2].id, places[0].id])
    }

    @Test("Places with the geofence turned off are not monitored")
    func skipsDisabledPlaces() {
        let enabled = place(offsetKilometers: 10)
        let disabled = place(offsetKilometers: 1, enabled: false)
        let regions = GeofenceSelector.regions(for: [disabled, enabled], near: here)
        #expect(regions.map(\.id) == [enabled.id])
    }

    @Test("Recently reminded places give up their slot to others")
    func cooldownYieldsSlots() {
        let recent = place(offsetKilometers: 1)
        let other = place(offsetKilometers: 50)
        let now = Date()

        let regions = GeofenceSelector.regions(
            for: [recent, other],
            near: here,
            limit: 1,
            now: now,
            cooldown: 7 * 24 * 3600,
            lastNotified: [recent.id: now.addingTimeInterval(-3600)]
        )
        #expect(regions.map(\.id) == [other.id])
    }

    @Test("After the cooldown a place returns to the selection")
    func cooldownExpires() {
        let recent = place(offsetKilometers: 1)
        let other = place(offsetKilometers: 50)
        let now = Date()

        let regions = GeofenceSelector.regions(
            for: [recent, other],
            near: here,
            limit: 1,
            now: now,
            cooldown: 24 * 3600,
            lastNotified: [recent.id: now.addingTimeInterval(-48 * 3600)]
        )
        #expect(regions.map(\.id) == [recent.id])
    }

    @Test("Without a known location the newest places are taken")
    func fallsBackToNewestWhenLocationUnknown() {
        let older = PlaceSnapshot(id: UUID(), latitude: 0, longitude: 0, placeName: nil, city: nil, country: nil, note: nil,
                                  createdAt: Date(timeIntervalSince1970: 0), eventDate: nil,
                                  pinStyleOverride: nil, geofenceEnabled: true,
                                  trackTitle: nil, trackArtist: nil,
                                  artworkURL: nil, previewURL: nil, media: [])
        let newer = PlaceSnapshot(id: UUID(), latitude: 0, longitude: 0, placeName: nil, city: nil, country: nil, note: nil,
                                  createdAt: Date(), eventDate: nil,
                                  pinStyleOverride: nil, geofenceEnabled: true,
                                  trackTitle: nil, trackArtist: nil,
                                  artworkURL: nil, previewURL: nil, media: [])
        let regions = GeofenceSelector.regions(for: [older, newer], near: nil, limit: 1)
        #expect(regions.map(\.id) == [newer.id])
    }

    @Test("The geofence radius ends up in the region")
    func radiusIsApplied() {
        let regions = GeofenceSelector.regions(for: [place(offsetKilometers: 1)],
                                               near: here, radius: 320)
        #expect(regions.first?.radius == 320)
    }

    @Test("A zero limit gives an empty set")
    func zeroLimit() {
        #expect(GeofenceSelector.regions(for: [place(offsetKilometers: 1)],
                                         near: here, limit: 0).isEmpty)
    }

    @Test("The cooldown forbids a repeated reminder")
    func mayNotifyRespectsCooldown() {
        let id = UUID()
        let now = Date()
        #expect(GeofenceSelector.mayNotify(placeID: id, now: now, cooldown: 3600,
                                           lastNotified: [id: now.addingTimeInterval(-600)]) == false)
        #expect(GeofenceSelector.mayNotify(placeID: id, now: now, cooldown: 3600,
                                           lastNotified: [id: now.addingTimeInterval(-7200)]))
        #expect(GeofenceSelector.mayNotify(placeID: id, now: now, cooldown: 0, lastNotified: [id: now]))
        #expect(GeofenceSelector.mayNotify(placeID: id, now: now, cooldown: 3600, lastNotified: [:]))
    }
}

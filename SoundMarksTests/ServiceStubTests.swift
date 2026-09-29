import Foundation
import Testing

@testable import SoundMarks

/// Stubs must honestly report what is not implemented instead of crashing.
@Suite("Service stubs")
struct ServiceStubTests {
    @Test("Phase 4 sources are not connected yet")
    func laterPhaseSourcesAreDisconnected() async {
        let sources: [any MusicSource] = [SpotifyWebAPISource(), AppleMusicSource()]
        for source in sources {
            #expect(await source.isConnected == false)
        }
    }

    @Test("Phase 4 sources return notImplemented")
    func laterPhaseSourcesThrow() async {
        let interval = DateInterval(start: .distantPast, end: .now)
        await #expect(throws: AppError.notImplemented(feature: MusicSourceKind.appleMusic.localizedName)) {
            _ = try await AppleMusicSource().plays(in: interval)
        }
    }

    @Test("Last.fm without an API key in the build honestly says so")
    func lastFmWithoutKey() async {
        guard !LastFmConfiguration.isConfigured else { return }
        let interval = DateInterval(start: .distantPast, end: .now)
        await #expect(throws: AppError.lastFmNotConfigured) {
            _ = try await LastFmSource().plays(in: interval)
        }
        #expect(await LastFmSource().isConnected == false)
    }

    @Test("The export file does not know what is playing now")
    func exportImporterHasNoNowPlaying() async throws {
        #expect(try await SpotifyExportImporter().nowPlaying() == nil)
    }

    @Test("Errors have a human-readable description")
    func errorsAreHumanReadable() {
        let errors: [AppError] = [
            .notImplemented(feature: "X"),
            .persistenceUnavailable(reason: "disk"),
            .networkUnavailable,
            .permissionDenied(.photoLibrary),
            .locationUnavailable,
            .musicSourceNotConnected(.lastFm),
            .lastFmNotConfigured,
            .nothingPlaying,
            .invalidEventDate,
            .importFileUnreadable(reason: "bad zip"),
            .other(message: "msg"),
        ]
        for error in errors {
            let description = error.errorDescription
            #expect(description?.isEmpty == false)
        }
    }

    @Test("The location stub returns no fix")
    func locationStubFails() async {
        await #expect(throws: AppError.locationUnavailable) {
            _ = try await UnavailableLocationService().currentFix()
        }
    }

    @Test("The library stub returns an empty result, not an error")
    func photoStubIsEmpty() async throws {
        let service = UnavailablePhotoService()
        #expect(try await service.yearsWithGeotaggedAssets().isEmpty)
        #expect(try await service.snapshots(in: DateInterval(start: .distantPast, end: .now),
                                            requiringLocation: true).isEmpty)
    }
}

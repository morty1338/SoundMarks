import CoreGraphics
import Foundation

/// Library access: asset metadata for scanning and loading media for the UI.
/// "Limited library" mode is supported on par with full access.
protocol PhotoService: Sendable {
    var authorization: PhotoAuthorization { get async }

    func requestAuthorization() async -> PhotoAuthorization

    /// Years in which the library has geotagged shots —
    /// the scan period chips are built from them.
    func yearsWithGeotaggedAssets() async throws -> [Int]

    /// Asset metadata for an interval. Images aren't loaded.
    func snapshots(in interval: DateInterval, requiringLocation: Bool) async throws -> [PhotoAssetSnapshot]

    /// Image data for display. `Data` rather than `UIImage`
    /// so the value can freely cross actor boundaries.
    func imageData(for localIdentifier: String, targetSize: CGSize) async throws -> Data?

    /// URL of a video file for playback in AVKit.
    func videoURL(for localIdentifier: String) async throws -> URL?
}

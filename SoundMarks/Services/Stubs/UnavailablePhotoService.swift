import CoreGraphics
import Foundation

/// Stub until PhotoKit is implemented.
final class UnavailablePhotoService: PhotoService {
    var authorization: PhotoAuthorization { get async { .notDetermined } }

    func requestAuthorization() async -> PhotoAuthorization { .notDetermined }

    func yearsWithGeotaggedAssets() async throws -> [Int] { [] }

    func snapshots(in interval: DateInterval, requiringLocation: Bool) async throws -> [PhotoAssetSnapshot] { [] }

    func imageData(for localIdentifier: String, targetSize: CGSize) async throws -> Data? { nil }

    func videoURL(for localIdentifier: String) async throws -> URL? { nil }
}

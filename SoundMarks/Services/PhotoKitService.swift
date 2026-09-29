import CoreGraphics
import Foundation
import Photos
import UIKit

/// PhotoKit: permissions and loading media by `PHAsset.localIdentifier`.
///
/// Scanning the library by period is Phase 2; everything it will need
/// is already here, except matching.
final class PhotoKitService: PhotoService {
    private let imageManager = PHImageManager.default()

    var authorization: PhotoAuthorization {
        get async { Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    }

    func requestAuthorization() async -> PhotoAuthorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.map(status)
    }

    func yearsWithGeotaggedAssets() async throws -> [Int] {
        guard await authorization.allowsReading else {
            throw AppError.permissionDenied(.photoLibrary)
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue,
                                        PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: options)
        let calendar = Calendar.current
        var years: Set<Int> = []

        assets.enumerateObjects { asset, _, _ in
            guard asset.location != nil, let date = asset.creationDate else { return }
            years.insert(calendar.component(.year, from: date))
        }
        return years.sorted(by: >)
    }

    func snapshots(in interval: DateInterval, requiringLocation: Bool) async throws -> [PhotoAssetSnapshot] {
        guard await authorization.allowsReading else {
            throw AppError.permissionDenied(.photoLibrary)
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        interval.start as NSDate, interval.end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: options)
        var result: [PhotoAssetSnapshot] = []
        result.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            guard let creationDate = asset.creationDate else { return }
            let coordinate = asset.location?.coordinate
            if requiringLocation, coordinate == nil { return }

            result.append(PhotoAssetSnapshot(
                id: asset.localIdentifier,
                kind: asset.mediaType == .video ? .video : .photo,
                creationDate: creationDate,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            ))
        }
        return result
    }

    func imageData(for localIdentifier: String, targetSize: CGSize) async throws -> Data? {
        guard let asset = Self.asset(for: localIdentifier) else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(for: asset,
                                      targetSize: targetSize,
                                      contentMode: .aspectFill,
                                      options: options) { image, info in
                // A low-quality preview arrives first — wait for the final frame.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        return image?.jpegData(compressionQuality: 0.9)
    }

    func videoURL(for localIdentifier: String) async throws -> URL? {
        guard let asset = Self.asset(for: localIdentifier), asset.mediaType == .video else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        return await withCheckedContinuation { continuation in
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    // MARK: - Helpers

    private static func asset(for localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .limited: .limited
        case .authorized: .authorized
        @unknown default: .notDetermined
        }
    }
}

import CoreData
import Foundation
import UIKit

/// Gets media for display: from the library by `localIdentifier`
/// or from a copy in the store (shared maps and the case when there's no library access).
///
/// Images are decoded off the main thread and kept ready in the shared cache
/// `ImagePipeline`; copies from the store are read with a background context.
@MainActor
final class MediaLoader {
    private let photos: PhotoService
    private let reader: BackgroundReader

    init(photos: PhotoService, persistence: PersistenceController) {
        self.photos = photos
        reader = BackgroundReader(context: persistence.newBackgroundContext())
    }

    /// - Parameter targetSize: size for PhotoKit in pixels. Store copies and the library response
    ///   are scaled down to at most twice that size — the full-size photo never gets into memory.
    func image(for media: PlaceSnapshot.Media, targetSize: CGSize) async -> UIImage? {
        let key = "media|\(media.id.uuidString)|\(Int(targetSize.width))x\(Int(targetSize.height))"
        let maxPixel = Int(max(targetSize.width, targetSize.height)) * 2
        if let cached = ImagePipeline.shared.cachedImage(forKey: key, maxPixel: maxPixel) { return cached }

        var data: Data?
        if let localIdentifier = media.localIdentifier {
            data = try? await photos.imageData(for: localIdentifier, targetSize: targetSize)
        }
        if data == nil, media.hasEmbeddedData {
            data = await embeddedData(for: media.id)
        }

        guard let data else { return nil }
        return await ImagePipeline.shared.image(from: data, key: key, maxPixel: maxPixel)
    }

    func videoURL(for media: PlaceSnapshot.Media) async -> URL? {
        guard media.kind == .video, let localIdentifier = media.localIdentifier else { return nil }
        return try? await photos.videoURL(for: localIdentifier)
    }

    /// Photo copy from the store — reading the large blob off the main thread.
    private func embeddedData(for mediaID: UUID) async -> Data? {
        try? await reader.read { context in
            let request = MediaItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", mediaID as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first?.imageData
        }
    }
}

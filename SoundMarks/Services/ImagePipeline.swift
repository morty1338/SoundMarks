import Foundation
import ImageIO
import UIKit

/// Images ready for display: decoded and scaled to the view size off the main thread.
///
/// Artwork bytes live in `ArtworkCache` (memory + disk), while here are already decoded
/// thumbnails in an `NSCache`. The main thread no longer decodes JPEGs for every pin,
/// strip cell or view reappearance.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    // NSCache is thread-safe.
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        // About 48 MB of decoded pixels.
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// A thumbnail that is already prepared — for drawing without a flashing placeholder.
    func cachedArtwork(for url: URL, maxPixel: Int) -> UIImage? {
        cache.object(forKey: Self.key(url.absoluteString, maxPixel))
    }

    /// Track artwork scaled down to `maxPixel` on its long side.
    func artwork(for url: URL, maxPixel: Int) async -> UIImage? {
        let key = Self.key(url.absoluteString, maxPixel)
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = await ArtworkCache.shared.data(for: url) else { return nil }
        return await decode(data, maxPixel: maxPixel, key: key)
    }

    /// A prepared image by an arbitrary key — for media from the library and the store.
    func cachedImage(forKey key: String, maxPixel: Int) -> UIImage? {
        cache.object(forKey: Self.key(key, maxPixel))
    }

    /// Decodes bytes off the main thread and puts the result into the cache.
    func image(from data: Data, key: String, maxPixel: Int) async -> UIImage? {
        await decode(data, maxPixel: maxPixel, key: Self.key(key, maxPixel))
    }

    private func decode(_ data: Data, maxPixel: Int, key: NSString) async -> UIImage? {
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsample(data, maxPixel: maxPixel)
        }.value
        guard let decoded else { return nil }
        cache.setObject(decoded, forKey: key, cost: Self.cost(of: decoded))
        return decoded
    }

    /// Thumbnail via ImageIO: the full-size image isn't decoded into memory.
    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode right away, here, rather than on first draw on the main thread.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Side in pixels for a view: points × screen scale, rounded up to a step
    /// so neighboring sizes share one thumbnail.
    static func pixelSide(for points: CGFloat, scale: CGFloat) -> Int {
        let pixels = max(points, 1) * max(scale, 1)
        return Int((pixels / 32).rounded(.up)) * 32
    }

    private static func key(_ base: String, _ maxPixel: Int) -> NSString {
        "\(base)|\(maxPixel)" as NSString
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

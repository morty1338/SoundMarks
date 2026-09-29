import SwiftUI

/// Track artwork from the cache. Until it loads — a neutral placeholder with a note.
///
/// The image is decoded off the main thread right at the view size; an already prepared one
/// is taken from the shared cache without a placeholder.
struct ArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    /// Long side of the view in points — the thumbnail is requested for it.
    @State private var side: CGFloat = 0

    private struct Request: Equatable {
        let url: URL?
        let pixel: Int
    }

    private var pixel: Int { ImagePipeline.pixelSide(for: side, scale: displayScale) }

    var body: some View {
        let shown = image ?? cached

        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.size.width, proxy.size.height)
        } action: { newSide in
            side = newSide
        }
        .task(id: Request(url: url, pixel: pixel)) {
            guard let url else {
                image = nil
                loadedURL = nil
                return
            }
            guard side > 0 else { return }
            if let ready = ImagePipeline.shared.cachedArtwork(for: url, maxPixel: pixel) {
                image = ready
                loadedURL = url
                return
            }
            // A different artwork — placeholder while loading; the same track larger — the old image until replaced.
            if loadedURL != url { image = nil }
            let loaded = await ImagePipeline.shared.artwork(for: url, maxPixel: pixel)
            guard !Task.isCancelled, let loaded else { return }
            image = loaded
            loadedURL = url
        }
        .accessibilityHidden(true)
    }

    /// Ready thumbnail from the cache — a cell reappearing doesn't need a placeholder.
    private var cached: UIImage? {
        guard let url, side > 0 else { return nil }
        return ImagePipeline.shared.cachedArtwork(for: url, maxPixel: pixel)
    }
}

/// Thumbnail of attached media.
struct MediaThumbnail: View {
    let media: PlaceSnapshot.Media
    let loader: MediaLoader
    var targetSize = CGSize(width: 600, height: 600)

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }

            if media.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
        }
        .task(id: media.id) {
            image = await loader.image(for: media, targetSize: targetSize)
        }
    }
}

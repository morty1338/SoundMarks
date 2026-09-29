import SwiftUI

/// A 9:16 card for sharing. All images are passed in ready-made:
/// `ImageRenderer` draws synchronously and doesn't wait for anything.
struct ShareCardContent: View {
    let place: PlaceSnapshot
    let artwork: UIImage?
    let photos: [UIImage]

    /// Logical size; `ImageRenderer.scale` brings it up to 1080×1920.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.09), Color(white: 0.16), Color(white: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 22) {
                Spacer(minLength: 28)

                vinyl

                VStack(spacing: 6) {
                    Text(place.displayTitle)
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let artist = place.trackArtist {
                        Text(artist)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)

                Label {
                    Text(metaLine)
                        .font(.system(size: 14, weight: .medium))
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)

                if !photos.isEmpty {
                    collage
                }

                Spacer(minLength: 20)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var vinyl: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.05))
                .frame(width: 176, height: 176)
                .shadow(color: .black.opacity(0.6), radius: 18, y: 8)

            // Grooves.
            ForEach(0..<7, id: \.self) { ring in
                Circle()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    .frame(width: 176 - CGFloat(ring) * 16, height: 176 - CGFloat(ring) * 16)
            }

            Group {
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.accentColor
                }
            }
            .frame(width: 74, height: 74)
            .clipShape(Circle())

            Circle()
                .fill(Color(white: 0.85))
                .frame(width: 11, height: 11)

            Circle()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.3), .clear],
                                   startPoint: .topLeading,
                                   endPoint: .center)
                )
                .frame(width: 176, height: 176)
        }
    }

    private var collage: some View {
        HStack(spacing: 8) {
            ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) { _, photo in
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photoWidth, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 24)
    }

    private var photoWidth: CGFloat {
        let count = CGFloat(min(photos.count, 3))
        return (Self.size.width - 48 - (count - 1) * 8) / count
    }

    private var metaLine: String {
        [place.placeName, place.eventDate?.formatted()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

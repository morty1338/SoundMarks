import SwiftUI

/// A record like on the map: a drawn disc with the artwork on the label
/// or a painted skin with a small artwork in the center.
struct VinylRecordView: View {
    let artworkURL: URL?
    var skin: RecordSkin = SkinCatalog.skin(id: nil)
    /// Fraction of the diameter for the artwork on a regular record.
    var labelRatio: CGFloat = 0.72

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                if let asset = skin.assetName {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(Circle())

                    ArtworkImage(url: artworkURL, cornerRadius: 0)
                        .frame(width: side * 0.3, height: side * 0.3)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
                        .opacity(artworkURL == nil ? 0 : 1)
                } else {
                    Circle().fill(DS.Colors.vinyl)

                    // Grooves are visible only on a narrow ring around the artwork.
                    ForEach(0..<4, id: \.self) { ring in
                        Circle()
                            .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                            .padding(side * (0.02 + CGFloat(ring) * 0.028))
                    }

                    ArtworkImage(url: artworkURL, cornerRadius: 0)
                        .frame(width: side * labelRatio, height: side * labelRatio)
                        .clipShape(Circle())
                }

                Circle()
                    .fill(DS.Colors.vinyl)
                    .frame(width: side * 0.06, height: side * 0.06)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))

                // Highlight — the record is three-dimensional, not a flat circle.
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .clear, .white.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .blendMode(.screen)
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.45), radius: side * 0.05, y: side * 0.03)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension PlaceSnapshot {
    /// The place's skin or the default skin from the profile.
    func skin(default defaultID: String) -> RecordSkin {
        SkinCatalog.skin(id: skinID ?? defaultID)
    }
}

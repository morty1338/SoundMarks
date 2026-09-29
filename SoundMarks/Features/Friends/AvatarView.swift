import SwiftUI
import UIKit

/// Avatar: a photo or initials on a colored circle.
struct AvatarView: View {
    let nickname: String?
    let colorHex: String?
    let imageData: Data?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let imageData, let image = AvatarImageCache.image(from: imageData, side: size * 3) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AvatarPalette.color(hex: colorHex)
                Text(AvatarPalette.initials(of: nickname))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

extension AvatarView {
    init(profile: Profile, size: CGFloat = 44) {
        self.init(nickname: profile.nickname, colorHex: profile.avatarColorHex,
                  imageData: profile.avatarData, size: size)
    }
}

/// Decoded avatars: previously every view update decoded the JPEG again.
/// Avatars are small (256 px), so the thumbnail is made right away — no flashing initials.
/// Size is for a 3x screen: few extra pixels on 2x, but the view does not depend on the environment.
@MainActor
enum AvatarImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        return cache
    }()

    static func image(from data: Data, side: CGFloat) -> UIImage? {
        var hasher = Hasher()
        hasher.combine(data)
        let pixel = ImagePipeline.pixelSide(for: side, scale: 1)
        let key = "\(data.count)|\(hasher.finalize())|\(pixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = ImagePipeline.downsample(data, maxPixel: pixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Colors of the initials circle — calm, so they do not compete with the accent.
enum AvatarPalette {
    static let hexes = ["#E4572E", "#F2A541", "#4CB944", "#2E86AB", "#7D5BA6", "#D6448B", "#3D9970", "#8C6E54"]

    static func random() -> String { hexes.randomElement() ?? hexes[0] }

    static func color(hex: String?) -> Color {
        guard let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        else { return Color(white: 0.35) }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    static func initials(of nickname: String?) -> String {
        let parts = (nickname ?? "").split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// The avatar photo is stored as a small square — the same one is sent to friends.
    static func avatarJPEG(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        return square.jpegData(compressionQuality: 0.8)
    }
}

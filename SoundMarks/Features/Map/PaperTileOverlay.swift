import MapKit
import UIKit

/// Tint over the MapKit base: a dark map in the planet's indigo-violet palette
/// with light grain — like a drawn illustration rather than Apple Maps.
///
/// MapKit doesn't allow a custom cartographic style, so the style is made
/// with an overlay: the tile is drawn on the device (no network needed) and blended
/// with the map in multiply mode. MapKit overlays are always below pins — records
/// stay clean.
final class PaperTileOverlay: MKTileOverlay {
    /// One tile for all positions: the paper grain is the same at any scale.
    private static let nightTile: Data? = PaperTexture.render(side: 256, isDay: false).pngData()
    /// By day — warm light paper.
    private static let dayTile: Data? = PaperTexture.render(side: 256, isDay: true).pngData()

    private let tileData: Data?

    init(isDay: Bool = false) {
        tileData = isDay ? Self.dayTile : Self.nightTile
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        minimumZ = 0
        maximumZ = 22
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        result(tileData, nil)
    }

    /// Renderer with multiply blending: the paper tints the map rather than covering it.
    static func renderer(for overlay: PaperTileOverlay) -> MKTileOverlayRenderer {
        let renderer = MKTileOverlayRenderer(tileOverlay: overlay)
        renderer.blendMode = .multiply
        renderer.alpha = 0.95
        return renderer
    }
}

/// Procedural tint: violet tone, grain and sparse strokes. Seamless at the edges.
enum PaperTexture {
    static func render(side: CGFloat, isDay: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var random = SplitMix64(seed: 0xB0_0C)

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let context = renderer.cgContext

            // At night — an indigo-violet tone matching the planet, by day — warm paper.
            (isDay ? UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
                   : UIColor(red: 0.62, green: 0.58, blue: 0.95, alpha: 1)).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))

            // Grain: small, slightly darker specks.
            for _ in 0..<2200 {
                let x = random.next(in: 0...Double(side))
                let y = random.next(in: 0...Double(side))
                let radius = random.next(in: 0.4...1.3)
                let shade = random.next(in: 0.48...0.58)
                let grain = isDay
                    ? UIColor(red: 0.86 + shade * 0.1, green: 0.8 + shade * 0.1, blue: 0.68 + shade * 0.1,
                              alpha: random.next(in: 0.2...0.45))
                    : UIColor(red: shade, green: shade * 0.94, blue: shade * 1.5, alpha: random.next(in: 0.25...0.6))
                grain.setFill()
                // Draw with wrap-around across the edge — tiles join without a seam.
                for dx in [-side, 0, side] {
                    for dy in [-side, 0, side] {
                        context.fillEllipse(in: CGRect(x: x + dx - radius, y: y + dy - radius,
                                                       width: radius * 2, height: radius * 2))
                    }
                }
            }

            // Fibers: short thin strokes.
            context.setLineCap(.round)
            for _ in 0..<26 {
                let x = random.next(in: 0...Double(side))
                let y = random.next(in: 0...Double(side))
                let angle = random.next(in: 0...(2 * Double.pi))
                let length = random.next(in: 6...18)
                context.setStrokeColor((isDay ? UIColor(red: 0.78, green: 0.7, blue: 0.56, alpha: 0.3)
                                              : UIColor(red: 0.45, green: 0.42, blue: 0.72, alpha: 0.35)).cgColor)
                context.setLineWidth(random.next(in: 0.4...0.9))
                for dx in [-side, 0, side] {
                    for dy in [-side, 0, side] {
                        context.move(to: CGPoint(x: x + dx, y: y + dy))
                        context.addLine(to: CGPoint(x: x + dx + cos(angle) * length, y: y + dy + sin(angle) * length))
                    }
                }
                context.strokePath()
            }
        }
    }
}

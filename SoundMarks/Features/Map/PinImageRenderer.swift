import UIKit

/// Draws pins: a three-dimensional vinyl record and a turntable.
///
/// Finished images are cached by style, artwork and size — with 1000+ places
/// identical tracks reuse one image.
///
/// Drawing is thread-safe (`UIGraphicsImageRenderer`, `NSCache`): pins with artwork
/// are drawn off the main thread, the main thread only sets the finished image.
enum PinImageRenderer {
    /// Record diameter on the map.
    static let pinDiameter: CGFloat = 44
    /// Padding for the shadow.
    static let shadowPadding: CGFloat = 4

    /// Side of the artwork thumbnail for the pin label: enough for a highlighted pin (×1.25) on a 3x screen.
    static let artworkPixel = 96

    // NSCache is thread-safe.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 1200
        return cache
    }()

    private static func key(style: PinStyle, skin: RecordSkin, artworkKey: String?, diameter: CGFloat) -> NSString {
        "\(style.rawValue)|\(skin.id)|\(artworkKey ?? "none")|\(Int(diameter))" as NSString
    }

    private static func clusterKey(style: PinStyle, skin: RecordSkin, artworkKey: String?, count: Int,
                                   diameter: CGFloat) -> NSString {
        "cluster|\(style.rawValue)|\(skin.id)|\(artworkKey ?? "none")|\(count)|\(Int(diameter))" as NSString
    }

    /// An already drawn pin — so a reused view shows the artwork right away.
    static func cachedImage(style: PinStyle, skin: RecordSkin, artworkKey: String,
                            diameter: CGFloat = pinDiameter) -> UIImage? {
        cache.object(forKey: key(style: style, skin: skin, artworkKey: artworkKey, diameter: diameter))
    }

    static func cachedClusterImage(style: PinStyle, skin: RecordSkin, artworkKey: String, count: Int,
                                   diameter: CGFloat = pinDiameter) -> UIImage? {
        cache.object(forKey: clusterKey(style: style, skin: skin, artworkKey: artworkKey, count: count,
                                        diameter: diameter))
    }

    static func image(style: PinStyle, skin: RecordSkin = SkinCatalog.skin(id: nil),
                      artwork: UIImage?, artworkKey: String?, diameter: CGFloat = pinDiameter) -> UIImage {
        let key = key(style: style, skin: skin, artworkKey: artworkKey, diameter: diameter)
        if let cached = cache.object(forKey: key) { return cached }

        let image: UIImage
        switch style {
        case .vinyl:
            if let asset = skin.assetName, let skinImage = skinImage(asset, diameter: diameter) {
                image = renderSkinned(skinImage, artwork: artwork, diameter: diameter)
            } else {
                image = renderVinyl(artwork: artwork, diameter: diameter)
            }
        case .turntable:
            image = renderTurntable(artwork: artwork, diameter: diameter)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// A stack of records for a cluster: the top one with the artwork of the newest place,
    /// the number of places in the corner.
    ///
    /// The counter is drawn right into the image, not as a separate subview: that way
    /// there's no need to touch the `MKAnnotationView` `bounds` that clustering relies on.
    static func clusterImage(style: PinStyle, skin: RecordSkin = SkinCatalog.skin(id: nil),
                             artwork: UIImage?, artworkKey: String?, count: Int,
                             diameter: CGFloat = pinDiameter) -> UIImage {
        let layers = min(max(count, 2), 3)
        let key = clusterKey(style: style, skin: skin, artworkKey: artworkKey, count: count, diameter: diameter)
        if let cached = cache.object(forKey: key) { return cached }

        let offset: CGFloat = 3
        let badgeSide = max(16, diameter * 0.42)
        // Symmetric padding so the top record stays centered in the image
        // and the pin doesn't drift from its coordinate.
        let pad = max(offset * CGFloat(layers - 1), badgeSide * 0.5)
        let side = diameter + (shadowPadding + pad) * 2
        let canvas = CGSize(width: side, height: side)
        let top = CGRect(x: shadowPadding + pad, y: shadowPadding + pad,
                         width: diameter, height: diameter)

        let stack = UIGraphicsImageRenderer(size: canvas).image { context in
            // Lower records shift up and to the left.
            for index in stride(from: layers - 1, through: 1, by: -1) {
                let shift = offset * CGFloat(index)
                let rect = top.offsetBy(dx: -shift, dy: -shift)
                drawShadow(in: context.cgContext)
                UIColor(white: 0.07, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: rect)
                context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor(white: 1, alpha: 0.12).setStroke()
                context.cgContext.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            }

            Self.image(style: style, skin: skin, artwork: artwork, artworkKey: artworkKey, diameter: diameter)
                .draw(at: CGPoint(x: top.minX - shadowPadding, y: top.minY - shadowPadding))

            drawBadge(count: count,
                      centeredAt: CGPoint(x: top.maxX - badgeSide * 0.2, y: top.maxY - badgeSide * 0.2),
                      side: badgeSide,
                      in: context.cgContext)
        }

        cache.setObject(stack, forKey: key)
        return stack
    }

    private static func drawBadge(count: Int, centeredAt center: CGPoint, side: CGFloat, in context: CGContext) {
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)

        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                          color: UIColor.black.withAlphaComponent(0.35).cgColor)
        UIColor.tintColor.setFill()
        context.fillEllipse(in: rect)
        context.setShadow(offset: .zero, blur: 0, color: nil)

        UIColor.white.setStroke()
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))

        let text = count > 99 ? "99+" : String(count)
        let fontSize = side * (text.count > 2 ? 0.42 : 0.56)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2,
                                            y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }

    /// The dart that "flies" into the chosen point on a long press.
    /// The tip at the bottom of the image is what points to the coordinate.
    static func dartImage(height: CGFloat = 52) -> UIImage {
        let key = "dart|\(Int(height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let width = height * 0.52
        let canvas = CGSize(width: width + shadowPadding * 2, height: height + shadowPadding * 2)

        let image = UIGraphicsImageRenderer(size: canvas).image { rendererContext in
            let context = rendererContext.cgContext
            let centerX = canvas.width / 2
            let tipY = canvas.height - shadowPadding
            let bodyTop = shadowPadding + height * 0.34

            drawShadow(in: context)

            // Needle: from the tip up to the body.
            let needle = UIBezierPath()
            needle.move(to: CGPoint(x: centerX, y: tipY))
            needle.addLine(to: CGPoint(x: centerX - width * 0.13, y: bodyTop + height * 0.16))
            needle.addLine(to: CGPoint(x: centerX + width * 0.13, y: bodyTop + height * 0.16))
            needle.close()
            UIColor(white: 0.82, alpha: 1).setFill()
            needle.fill()
            context.setShadow(offset: .zero, blur: 0, color: nil)

            // Body.
            let body = CGRect(x: centerX - width * 0.17, y: bodyTop,
                              width: width * 0.34, height: height * 0.22)
            UIColor.tintColor.setFill()
            UIBezierPath(roundedRect: body, cornerRadius: width * 0.1).fill()

            // Flights.
            let flight = UIBezierPath()
            flight.move(to: CGPoint(x: centerX, y: shadowPadding + height * 0.02))
            flight.addLine(to: CGPoint(x: centerX - width * 0.5, y: shadowPadding + height * 0.2))
            flight.addLine(to: CGPoint(x: centerX, y: bodyTop + height * 0.02))
            flight.addLine(to: CGPoint(x: centerX + width * 0.5, y: shadowPadding + height * 0.2))
            flight.close()
            UIColor.tintColor.withAlphaComponent(0.92).setFill()
            flight.fill()

            // Highlight — so the dart looks three-dimensional, not flat.
            UIColor(white: 1, alpha: 0.45).setFill()
            let highlight = UIBezierPath()
            highlight.move(to: CGPoint(x: centerX, y: shadowPadding + height * 0.03))
            highlight.addLine(to: CGPoint(x: centerX - width * 0.42, y: shadowPadding + height * 0.2))
            highlight.addLine(to: CGPoint(x: centerX, y: shadowPadding + height * 0.2))
            highlight.close()
            highlight.fill()
        }

        cache.setObject(image, forKey: key)
        return image
    }

    static func clearCache() { cache.removeAllObjects() }

    /// Skin image scaled down to pin size once: the source is 512 px, but it is drawn at 44 pt.
    private static func skinImage(_ asset: String, diameter: CGFloat) -> UIImage? {
        let key = "skin|\(asset)|\(Int(diameter))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let full = UIImage(named: asset) else { return nil }
        let side = diameter * 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            full.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        cache.setObject(small, forKey: key)
        return small
    }

    // MARK: - Record

    private static func renderVinyl(artwork: UIImage?, diameter: CGFloat) -> UIImage {
        let canvas = CGSize(width: diameter + shadowPadding * 2, height: diameter + shadowPadding * 2)
        let disc = CGRect(x: shadowPadding, y: shadowPadding, width: diameter, height: diameter)
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let radius = diameter / 2

        return UIGraphicsImageRenderer(size: canvas).image { rendererContext in
            let context = rendererContext.cgContext

            drawShadow(in: context)
            UIColor(white: 0.06, alpha: 1).setFill()
            context.fillEllipse(in: disc)
            context.setShadow(offset: .zero, blur: 0, color: nil)

            // Grooves.
            context.setLineWidth(max(0.5, radius * 0.018))
            UIColor(white: 1, alpha: 0.07).setStroke()
            var grooveRadius = radius * 0.6
            while grooveRadius < radius * 0.97 {
                context.strokeEllipse(in: CGRect(x: center.x - grooveRadius, y: center.y - grooveRadius,
                                                 width: grooveRadius * 2, height: grooveRadius * 2))
                grooveRadius += radius * 0.075
            }

            // Label with the artwork.
            let labelRadius = radius * 0.56
            let label = CGRect(x: center.x - labelRadius, y: center.y - labelRadius,
                               width: labelRadius * 2, height: labelRadius * 2)
            context.saveGState()
            context.addEllipse(in: label)
            context.clip()
            if let artwork {
                draw(artwork, filling: label, in: context)
            } else {
                UIColor.tintColor.setFill()
                context.fill(label)
            }
            context.restoreGState()

            UIColor(white: 0, alpha: 0.35).setStroke()
            context.setLineWidth(max(0.5, radius * 0.02))
            context.strokeEllipse(in: label)

            drawGloss(in: context, disc: disc)

            // Center hole.
            let holeRadius = radius * 0.06
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fillEllipse(in: CGRect(x: center.x - holeRadius, y: center.y - holeRadius,
                                           width: holeRadius * 2, height: holeRadius * 2))

            UIColor(white: 1, alpha: 0.18).setStroke()
            context.setLineWidth(1)
            context.strokeEllipse(in: disc.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    // MARK: - Skinned record

    /// The whole painted disc, the artwork as a small label in the center,
    /// so the skin artwork stays visible and the track is still recognizable.
    private static func renderSkinned(_ skin: UIImage, artwork: UIImage?, diameter: CGFloat) -> UIImage {
        let canvas = CGSize(width: diameter + shadowPadding * 2, height: diameter + shadowPadding * 2)
        let disc = CGRect(x: shadowPadding, y: shadowPadding, width: diameter, height: diameter)
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let radius = diameter / 2

        return UIGraphicsImageRenderer(size: canvas).image { rendererContext in
            let context = rendererContext.cgContext

            drawShadow(in: context)
            UIColor(white: 0.06, alpha: 1).setFill()
            context.fillEllipse(in: disc)
            context.setShadow(offset: .zero, blur: 0, color: nil)

            context.saveGState()
            context.addEllipse(in: disc)
            context.clip()
            skin.draw(in: disc)
            context.restoreGState()

            if let artwork {
                let labelRadius = radius * 0.3
                let label = CGRect(x: center.x - labelRadius, y: center.y - labelRadius,
                                   width: labelRadius * 2, height: labelRadius * 2)
                context.saveGState()
                context.addEllipse(in: label)
                context.clip()
                draw(artwork, filling: label, in: context)
                context.restoreGState()
                UIColor(white: 0, alpha: 0.4).setStroke()
                context.setLineWidth(max(0.5, radius * 0.025))
                context.strokeEllipse(in: label)
            }

            drawGloss(in: context, disc: disc)

            let holeRadius = radius * 0.06
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fillEllipse(in: CGRect(x: center.x - holeRadius, y: center.y - holeRadius,
                                           width: holeRadius * 2, height: holeRadius * 2))

            UIColor(white: 1, alpha: 0.18).setStroke()
            context.setLineWidth(1)
            context.strokeEllipse(in: disc.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    // MARK: - Turntable

    private static func renderTurntable(artwork: UIImage?, diameter: CGFloat) -> UIImage {
        let canvas = CGSize(width: diameter + shadowPadding * 2, height: diameter + shadowPadding * 2)
        let body = CGRect(x: shadowPadding, y: shadowPadding, width: diameter, height: diameter)

        return UIGraphicsImageRenderer(size: canvas).image { rendererContext in
            let context = rendererContext.cgContext

            drawShadow(in: context)
            let corner = diameter * 0.22
            let bodyPath = UIBezierPath(roundedRect: body, cornerRadius: corner)
            UIColor(white: 0.16, alpha: 1).setFill()
            bodyPath.fill()
            context.setShadow(offset: .zero, blur: 0, color: nil)

            // Record on the platter.
            let discDiameter = diameter * 0.68
            let disc = CGRect(x: body.midX - discDiameter / 2,
                              y: body.midY - discDiameter / 2,
                              width: discDiameter, height: discDiameter)
            UIColor(white: 0.05, alpha: 1).setFill()
            context.fillEllipse(in: disc)

            let labelRadius = discDiameter * 0.2
            let label = CGRect(x: disc.midX - labelRadius, y: disc.midY - labelRadius,
                               width: labelRadius * 2, height: labelRadius * 2)
            context.saveGState()
            context.addEllipse(in: label)
            context.clip()
            if let artwork {
                draw(artwork, filling: label, in: context)
            } else {
                UIColor.tintColor.setFill()
                context.fill(label)
            }
            context.restoreGState()

            // Tonearm.
            UIColor(white: 0.75, alpha: 1).setStroke()
            context.setLineWidth(max(1, diameter * 0.045))
            context.setLineCap(.round)
            context.move(to: CGPoint(x: body.maxX - diameter * 0.18, y: body.minY + diameter * 0.18))
            context.addLine(to: CGPoint(x: body.midX + discDiameter * 0.18, y: body.midY + discDiameter * 0.1))
            context.strokePath()

            UIColor(white: 1, alpha: 0.18).setStroke()
            context.setLineWidth(1)
            UIBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner).stroke()
        }
    }

    // MARK: - Shared

    private static func drawShadow(in context: CGContext) {
        context.setShadow(offset: CGSize(width: 0, height: 1.5),
                          blur: 3,
                          color: UIColor.black.withAlphaComponent(0.45).cgColor)
    }

    /// Highlight: a diagonal gradient over the disc.
    private static func drawGloss(in context: CGContext, disc: CGRect) {
        context.saveGState()
        context.addEllipse(in: disc)
        context.clip()

        let colors = [UIColor(white: 1, alpha: 0.30).cgColor,
                      UIColor(white: 1, alpha: 0.06).cgColor,
                      UIColor(white: 1, alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors,
                                     locations: [0, 0.35, 0.62]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: disc.minX, y: disc.minY),
                                       end: CGPoint(x: disc.maxX, y: disc.maxY),
                                       options: [])
        }
        context.restoreGState()
    }

    /// Draws an image aspect-fill inside a rectangle.
    private static func draw(_ image: UIImage, filling rect: CGRect, in context: CGContext) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        image.draw(in: CGRect(origin: origin, size: size))
    }
}

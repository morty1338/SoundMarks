import MapKit
import UIKit

/// Shared pin look: style (record or turntable) and the default skin.
struct PinAppearance: Equatable {
    let style: PinStyle
    let defaultSkinID: String

    func skin(for place: PlaceSnapshot) -> RecordSkin {
        place.skin(default: defaultSkinID)
    }
}

/// Record pin. Above it — city and date. The artwork loads asynchronously and replaces the placeholder.
///
/// The disc is a separate layer: while the preview plays only it spins, the caption stays in place.
final class PlaceAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PlaceAnnotationView"
    /// Shared clustering identifier — MapKit builds stacks by it.
    static let clusteringIdentifier = "place"
    /// Pin image including the shadow padding.
    static let side = PinImageRenderer.pinDiameter + PinImageRenderer.shadowPadding * 2

    private var artworkTask: Task<Void, Never>?
    private let disc = UIImageView()
    private let caption = PinCaptionView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = Self.clusteringIdentifier
        collisionMode = .circle
        canShowCallout = false
        centerOffset = .zero
        // .required would make MapKit always show the pin and never put it in a stack.
        displayPriority = .defaultLow
        // We set the size ourselves — the image is held by the separate disc layer.
        frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        disc.frame = bounds
        addSubview(disc)
        // The caption lives above the pin and doesn't change its `bounds` — clustering relies on them.
        addSubview(caption)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        disc.image = nil
        transform = .identity
        setSpinning(false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        disc.frame = bounds
        let size = caption.sizeThatFits(CGSize(width: 160, height: 24))
        caption.frame = CGRect(x: (bounds.width - size.width) / 2, y: -size.height - 1,
                               width: size.width, height: size.height)
    }

    /// Only the disc spins.
    func setSpinning(_ isSpinning: Bool) {
        let layer = disc.layer
        guard isSpinning != (layer.animation(forKey: "spin") != nil) else { return }
        if isSpinning {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 1.8
            spin.repeatCount = .infinity
            layer.add(spin, forKey: "spin")
        } else {
            layer.removeAnimation(forKey: "spin")
        }
    }

    /// - Parameter isHighlighted: a highlighted record is larger and doesn't go into a stack.
    func configure(with place: PlaceSnapshot, appearance: PinAppearance, isHighlighted: Bool = false) {
        artworkTask?.cancel()
        let style = place.pinStyle(fallback: appearance.style)
        let skin = appearance.skin(for: place)

        // MapKit resets these properties when reusing a view, so
        // we set them on every configure, not only in init: otherwise after
        // the first annotation rebuild pins stop being grouped into stacks.
        clusteringIdentifier = isHighlighted ? nil : Self.clusteringIdentifier
        displayPriority = isHighlighted ? .required : .defaultLow
        zPriority = isHighlighted ? .max : .defaultUnselected
        transform = isHighlighted ? CGAffineTransform(scaleX: 1.25, y: 1.25) : .identity

        caption.text = [place.city ?? place.placeName, place.compactDate]
            .compactMap { $0 }
            .joined(separator: " · ")
        setNeedsLayout()

        // A pin with this artwork was already drawn — set it right away: views are reused
        // constantly while panning, and previously the placeholder flashed and the JPEG was decoded again every time.
        if let artworkURL = place.artworkURL,
           let ready = PinImageRenderer.cachedImage(style: style, skin: skin, artworkKey: artworkURL.absoluteString) {
            disc.image = ready
            return
        }

        // Set the pin without artwork right away so the map doesn't wait for the network.
        disc.image = PinImageRenderer.image(style: style, skin: skin, artwork: nil, artworkKey: nil)

        guard let artworkURL = place.artworkURL else { return }
        artworkTask = Task { [weak self] in
            // The artwork thumbnail and the pin itself are prepared off the main thread.
            guard let artwork = await ImagePipeline.shared.artwork(for: artworkURL,
                                                                   maxPixel: PinImageRenderer.artworkPixel),
                  !Task.isCancelled
            else { return }
            let pin = await Task.detached(priority: .userInitiated) {
                PinImageRenderer.image(style: style, skin: skin, artwork: artwork,
                                       artworkKey: artworkURL.absoluteString)
            }.value
            guard !Task.isCancelled, let self, (annotation as? PlaceAnnotation)?.place.id == place.id else { return }
            disc.image = pin
        }
    }
}

/// Caption above the pin: "City · date" on a translucent capsule.
/// No blur: each pin had its own blur layer — that noticeably slowed down panning.
final class PinCaptionView: UIView {
    private let label = UILabel()

    var text: String? {
        get { label.text }
        set {
            label.text = newValue
            isHidden = (newValue ?? "").isEmpty
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.1, alpha: 0.78)
                : UIColor(white: 1, alpha: 0.85)
        }
        layer.masksToBounds = true
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingHead
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(CGSize(width: size.width - 12, height: size.height))
        return CGSize(width: min(text.width + 12, size.width), height: 17)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        label.frame = bounds.insetBy(dx: 6, dy: 0)
    }
}

/// A vinyl stack with the number of places.
final class PlaceClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PlaceClusterAnnotationView"

    private var artworkTask: Task<Void, Never>?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        canShowCallout = false
        displayPriority = .defaultHigh
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        image = nil
    }

    func configure(with cluster: MKClusterAnnotation, appearance: PinAppearance) {
        artworkTask?.cancel()
        displayPriority = .defaultHigh

        let places = cluster.places
        let newest = places.first
        let pinStyle = newest?.pinStyle(fallback: appearance.style) ?? appearance.style
        let skin = newest.map(appearance.skin(for:)) ?? SkinCatalog.skin(id: appearance.defaultSkinID)

        let count = places.count
        if let artworkURL = newest?.artworkURL,
           let ready = PinImageRenderer.cachedClusterImage(style: pinStyle, skin: skin,
                                                           artworkKey: artworkURL.absoluteString, count: count) {
            image = ready
            return
        }

        image = PinImageRenderer.clusterImage(style: pinStyle, skin: skin, artwork: nil, artworkKey: nil,
                                              count: count)

        guard let artworkURL = newest?.artworkURL, let newestID = newest?.id else { return }
        artworkTask = Task { [weak self] in
            guard let artwork = await ImagePipeline.shared.artwork(for: artworkURL,
                                                                   maxPixel: PinImageRenderer.artworkPixel),
                  !Task.isCancelled
            else { return }
            let stack = await Task.detached(priority: .userInitiated) {
                PinImageRenderer.clusterImage(style: pinStyle, skin: skin, artwork: artwork,
                                              artworkKey: artworkURL.absoluteString, count: count)
            }.value
            guard !Task.isCancelled, let self,
                  (annotation as? MKClusterAnnotation)?.places.first?.id == newestID else { return }
            image = stack
        }
    }
}

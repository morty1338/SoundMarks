import MapKit
import UIKit

/// Temporary marker of a point chosen with a long press.
final class DartAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

/// A dart flying into the chosen point.
///
/// The animation lives here, not in SwiftUI: the view appears at the moment
/// MapKit adds the annotation and must start moving right away.
final class DartAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "DartAnnotationView"

    private let ripple = CAShapeLayer()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        isUserInteractionEnabled = false
        // The dart does not take part in clustering and is always above the pins.
        displayPriority = .required
        zPriority = .max

        let image = PinImageRenderer.dartImage()
        self.image = image
        // The tip at the bottom of the image must hit the coordinate exactly.
        centerOffset = CGPoint(x: 0, y: -image.size.height / 2 + PinImageRenderer.shadowPadding)

        layer.addSublayer(ripple)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else { return }
        playThrow()
    }

    /// Throw: the dart falls from above with a slight tilt and settles with a spring.
    private func playThrow() {
        let settled = transform

        transform = settled
            .translatedBy(x: 26, y: -140)
            .rotated(by: 0.55)
            .scaledBy(x: 0.75, y: 0.75)
        alpha = 0

        UIView.animate(withDuration: 0.42,
                       delay: 0,
                       usingSpringWithDamping: 0.62,
                       initialSpringVelocity: 1.4,
                       options: [.curveEaseOut]) {
            self.transform = settled
            self.alpha = 1
        } completion: { _ in
            self.playRipple()
        }
    }

    /// A circle spreading from the tip — confirms the hit.
    private func playRipple() {
        let radius: CGFloat = 13
        let center = CGPoint(x: bounds.midX,
                             y: bounds.maxY - PinImageRenderer.shadowPadding)

        ripple.path = UIBezierPath(
            arcCenter: center, radius: radius,
            startAngle: 0, endAngle: .pi * 2, clockwise: true
        ).cgPath
        ripple.fillColor = UIColor.clear.cgColor
        ripple.strokeColor = UIColor.tintColor.withAlphaComponent(0.85).cgColor
        ripple.lineWidth = 2
        ripple.opacity = 1

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.2
        scale.toValue = 2.4

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        ripple.frame = bounds
        ripple.add(group, forKey: "ripple")
    }
}

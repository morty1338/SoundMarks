import SceneKit
import SwiftUI
import UIKit

/// Command to the globe. Runs once and is reset to `nil`.
enum GlobeCommand: Equatable {
    /// Returning from the map: the camera pulls back, the planet settles on the home region —
    /// always the same, wherever the map was.
    case returnHome
    /// A friend's planet was opened: a few quick turns and a stop at the main region.
    case spinToHome
}

/// Continuous link to the map: while the map zooms out, the globe looks at its center
/// and the camera pulls back with the gesture.
struct GlobeTracking: Equatable {
    let latitude: Double
    let longitude: Double
    /// 0 — camera at the surface, 1 — the wide shot.
    let progress: Double
}

/// SceneKit planet in SwiftUI.
struct GlobeView: UIViewRepresentable {
    let places: [SphereMapping.Coordinate]
    /// Which planet is shown. On change — look at its main region right away.
    var page: PlanetPage?
    /// Day — light planet, night — dark.
    var isDay = false
    /// Lights, flags or pushpins.
    var markerStyle: PlanetMarkerStyle = .default
    var tracking: GlobeTracking?
    /// Fingers on the planet: turned off while the planet is moved in edit mode.
    var isInteractive = true
    /// Long press — the planet "lifts", it can be moved and deleted.
    var onLongPress: (() -> Void)?
    @Binding var command: GlobeCommand?
    /// Tap on the planet: the coordinate of the touch point.
    let onSelect: (SphereMapping.Coordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.globe.scene
        view.pointOfView = context.coordinator.globe.cameraNode
        // Transparent view: when the scene stars are hidden, the shared background shows through.
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        // Screen maximum: on ProMotion rotation and zoom run at 120 frames.
        view.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        view.allowsCameraControl = false

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleLongPress(_:)))
        press.minimumPressDuration = 0.45
        // Long press only while the finger stays still: a slight move is already rotation.
        press.allowableMovement = 6
        press.delegate = context.coordinator
        // A touch immediately stops a spinning planet — right where the finger is.
        let touchDown = TouchDownRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handleTouchDown(_:)))
        touchDown.delegate = context.coordinator
        view.addGestureRecognizer(touchDown)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(press)
        context.coordinator.pan = pan

        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.globe.setDaylight(isDay)
        coordinator.globe.setMarkerStyle(markerStyle)
        coordinator.onLongPress = onLongPress
        view.isUserInteractionEnabled = isInteractive
        coordinator.updatePlaces(places, page: page)
        coordinator.updateTracking(tracking)

        if let command {
            coordinator.apply(command)
            DispatchQueue.main.async { self.command = nil }
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stopInertia()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let globe = GlobeScene()
        weak var view: SCNView?
        var onSelect: (SphereMapping.Coordinate) -> Void
        var onLongPress: (() -> Void)?

        private var appliedPlaces: [SphereMapping.Coordinate] = [] {
            didSet { cachedHome = nil }
        }
        /// The main region is computed once per set of dots, not on every return home.
        private var cachedHome: SphereMapping.Coordinate?
        /// Double optional: "nothing shown yet" differs from "no planet".
        private var appliedPage: PlanetPage??
        private var appliedTracking: GlobeTracking?
        weak var pan: UIPanGestureRecognizer?
        private var velocity: Float = 0
        /// The touch landed on a spinning planet: it only stops it —
        /// no dot tap and no edit mode.
        private var touchStoppedSpin = false
        /// The finger already rotated the planet during this touch — a long press doesn't count.
        private var didPanDuringTouch = false
        private var touchDownTime: CFTimeInterval = 0
        private var lastFrameTime: CFTimeInterval = 0
        /// Rotation speed at the moment of touch — a new flick adds to it.
        private var carriedVelocity: Float = 0
        /// A limit so the planet doesn't turn into a blurry smudge.
        private let maximumSpin: Float = .pi * 4
        private var displayLink: CADisplayLink?
        private var isTransitioning = false
        /// Until the user rotates the planet themselves, it looks at the main region.
        private var hasUserRotated = false

        /// Rotation angle per screen width of finger travel.
        private let radiansPerScreen: Float = .pi * 0.9

        init(onSelect: @escaping (SphereMapping.Coordinate) -> Void) {
            self.onSelect = onSelect
            super.init()
        }

        func updatePlaces(_ places: [SphereMapping.Coordinate], page: PlanetPage?) {
            let pageChanged = page != appliedPage
            guard places != appliedPlaces || pageChanged else { return }
            if pageChanged {
                appliedPage = page
                hasUserRotated = false
                stopInertia()
            }
            let isFirstLoad = appliedPlaces.isEmpty || pageChanged
            appliedPlaces = places
            globe.setPlaces(places)

            // Show the region with the most records right away.
            if isFirstLoad, !hasUserRotated {
                globe.face(longitude: homeFocus.longitude, animated: false)
            }
        }

        /// The map zooms out — the globe follows its center and scale without animations.
        func updateTracking(_ tracking: GlobeTracking?) {
            guard tracking != appliedTracking else { return }
            appliedTracking = tracking
            guard let tracking else { return }

            stopInertia()
            isTransitioning = false
            globe.face(longitude: tracking.longitude, animated: false)
            globe.setZoom(tracking.progress, latitude: tracking.latitude, animated: false)
        }

        func apply(_ command: GlobeCommand) {
            stopInertia()
            isTransitioning = false
            switch command {
            case .returnHome:
                hasUserRotated = false
                globe.face(longitude: homeFocus.longitude, animated: true, duration: 0.9)
                globe.setZoom(1, animated: true, duration: 0.9)
            case .spinToHome:
                hasUserRotated = false
                globe.setZoom(1, animated: false)
                globe.spinAndSettle(longitude: homeFocus.longitude)
            }
        }

        // MARK: Gestures

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard !isTransitioning, let view else { return }
            let width = max(Float(view.bounds.width), 1)

            switch recognizer.state {
            case .began:
                hasUserRotated = true
                didPanDuringTouch = true
                stopInertia()
                view.rendersContinuously = true
            case .changed:
                let dx = Float(recognizer.translation(in: view).x)
                recognizer.setTranslation(.zero, in: view)
                globe.setYaw(globe.yaw + dx / width * radiansPerScreen)
            case .ended, .cancelled:
                // Finger speed turns into angular velocity. A flick in the same direction
                // adds to the current rotation — the planet can be spun up bit by bit.
                // The finger stopped before lifting — the planet stays in place.
                // A quick flick on a spinning planet adds to its speed;
                // if the finger lingered — the planet simply stopped under it.
                let flick = Float(recognizer.velocity(in: view).x) / width * radiansPerScreen
                let isQuickFlick = CACurrentMediaTime() - touchDownTime < 0.3
                if abs(flick) < 0.3 {
                    velocity = 0
                } else {
                    let carry = isQuickFlick && carriedVelocity.sign == flick.sign ? carriedVelocity : 0
                    velocity = min(max(carry + flick * 0.7, -maximumSpin), maximumSpin)
                }
                carriedVelocity = 0
                startInertia()
            default:
                break
            }
        }

        /// First touch: rotation freezes immediately, the planet stays under the finger.
        @objc func handleTouchDown(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began:
                touchDownTime = CACurrentMediaTime()
                touchStoppedSpin = displayLink != nil
                didPanDuringTouch = false
                carriedVelocity = velocity
                stopInertia()
            default:
                break
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            // While the planet is being spun or was just stopped by a touch — no editing.
            guard recognizer.state == .began, !isTransitioning, !touchStoppedSpin, !didPanDuringTouch,
                  pan?.state != .began, pan?.state != .changed else { return }
            stopInertia()
            onLongPress?()
        }

        nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // The "stop" touch works together with all other gestures.
            gestureRecognizer is TouchDownRecognizer || other is TouchDownRecognizer
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            // A tap on a spinning planet only stops it.
            guard !isTransitioning, !touchStoppedSpin, let view else { return }
            let point = recognizer.location(in: view)

            // Only place dots are tappable. An empty planet is the exception:
            // otherwise a new user couldn't get to the map and add the first place.
            let coordinate: SphereMapping.Coordinate
            if let dot = globe.dot(at: point, in: view, tolerance: 30) {
                coordinate = dot
            } else if appliedPlaces.isEmpty, let touched = surfaceCoordinate(at: point, in: view) {
                coordinate = touched
            } else {
                return
            }

            stopInertia()
            isTransitioning = true
            Haptics.select()
            globe.dive(toLatitude: coordinate.latitude, longitude: coordinate.longitude, duration: 0.85)

            // The map starts fading in while the camera is still flying.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.onSelect(coordinate)
            }
        }

        /// Surface point under the finger — by texture coordinate, independent of rotation.
        private func surfaceCoordinate(at point: CGPoint, in view: SCNView) -> SphereMapping.Coordinate? {
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .rootNode: globe.globe,
            ])
            guard let hit = hits.first else { return nil }
            let uv = hit.textureCoordinates(withMappingChannel: 0)
            return SphereMapping.coordinate(u: Double(uv.x), v: Double(uv.y))
        }

        /// Home view: the region with the most records; without places — Europe.
        private var homeFocus: SphereMapping.Coordinate {
            if let cachedHome { return cachedHome }
            let home = PlanetDots.home(for: appliedPlaces)
            cachedHome = home
            return home
        }

        // MARK: Inertia

        private func startInertia() {
            guard abs(velocity) > 0.05 else {
                view?.rendersContinuously = false
                return
            }
            let link = CADisplayLink(target: self, selector: #selector(stepInertia(_:)))
            // Same rate as the screen and the scene: otherwise on ProMotion the timer ran
            // at 60 Hz while frames ran at 120, and the planet moved in jerks every other frame.
            let maximum = Float(UIScreen.main.maximumFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            lastFrameTime = 0
            displayLink = link
            view?.rendersContinuously = true
        }

        @objc private func stepInertia(_ link: CADisplayLink) {
            // Step by real time between frames — a skipped frame doesn't cause a speed jump.
            let now = link.targetTimestamp
            let dt = Float(lastFrameTime == 0 ? link.targetTimestamp - link.timestamp : now - lastFrameTime)
            lastFrameTime = now
            globe.setYaw(globe.yaw + velocity * dt)
            // Light friction: a spun-up planet keeps turning for a few more seconds.
            velocity *= pow(0.3, dt)
            if abs(velocity) < 0.02 { stopInertia() }
        }

        func stopInertia() {
            displayLink?.invalidate()
            displayLink = nil
            velocity = 0
            view?.rendersContinuously = false
        }
    }
}

/// Fires at the moment of touch, before any other gesture: it stops
/// the rotation right away, not when the finger moves.
final class TouchDownRecognizer: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
}

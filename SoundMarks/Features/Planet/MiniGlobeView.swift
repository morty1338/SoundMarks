import SceneKit
import SwiftUI

/// A friend's small planet: slowly spins on its own, place dots are visible.
/// No gestures — the tap is handled by whoever shows it.
struct MiniGlobeView: UIViewRepresentable {
    let dots: [SphereMapping.Coordinate]
    var isDay = false
    var markerStyle: PlanetMarkerStyle = .default
    /// In the carousel neighboring planets stand still — that way they match
    /// the big planet when they slide into the center.
    var rotates = true

    func makeCoordinator() -> GlobeScene { GlobeScene(style: .mini) }

    /// Size in whole points only: with a fractional size SceneKit's antialiasing buffer
    /// doesn't match the frame, and on iPhone a colored rectangle shows instead of the planet.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SCNView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return Self.alignedSize(width: width, height: height)
    }

    static func alignedSize(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: max(1, width.rounded(.down)), height: max(1, height.rounded(.down)))
    }

    func makeUIView(context: Context) -> SCNView {
        let globe = context.coordinator
        let view = SCNView(frame: .zero)
        view.scene = globe.scene
        view.pointOfView = globe.cameraNode
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.isOpaque = false
        // 4x only: not all iPhones support 2x, and SceneKit then fills the view with pink.
        view.antialiasingMode = .multisampling4X
        // Several mini planets on screen — 30 frames are enough.
        view.preferredFramesPerSecond = 30
        view.isUserInteractionEnabled = false
        view.rendersContinuously = false
        view.isPlaying = true

        globe.setDaylight(isDay)
        globe.setMarkerStyle(markerStyle)
        globe.setPlaces(dots)
        globe.face(longitude: PlanetDots.home(for: dots).longitude, animated: false)
        if rotates { globe.startAutoRotation() }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let globe = context.coordinator
        globe.setDaylight(isDay)
        globe.setMarkerStyle(markerStyle)
        globe.setPlaces(dots)
    }
}

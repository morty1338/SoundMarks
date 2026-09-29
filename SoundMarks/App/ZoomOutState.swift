import CoreLocation
import Observation
import SwiftUI

/// The "map → planet" transition during a pinch.
///
/// Lives separately from the root screen: progress changes every frame, and if
/// `RootView` read it, the map with all its pins would rebuild every frame too —
/// that caused the lag at the transition boundary. Progress is read only by
/// layer opacity and the globe.
@MainActor
@Observable
final class ZoomOutState {
    private(set) var progress: Double = 0
    private(set) var center = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    func update(progress: Double, center: CLLocationCoordinate2D, animated: Bool) {
        self.center = center
        if animated {
            withAnimation(.smooth(duration: 0.35)) { self.progress = progress }
        } else {
            self.progress = progress
        }
    }

    func reset() {
        progress = 0
    }

    /// While the map zooms out, the globe looks at its center and pulls back with the gesture.
    func tracking(isMapStage: Bool) -> GlobeTracking? {
        guard isMapStage, progress > 0 else { return nil }
        return GlobeTracking(latitude: center.latitude, longitude: center.longitude, progress: progress)
    }
}

/// The planet layer fades in while the map zooms out.
struct PlanetLayerFade: ViewModifier {
    let zoom: ZoomOutState
    let isPlanetStage: Bool

    func body(content: Content) -> some View {
        content.opacity(isPlanetStage ? 1 : zoom.progress)
    }
}

/// The map layer fades and shrinks slightly while it zooms out into the planet.
struct MapLayerFade: ViewModifier {
    let zoom: ZoomOutState
    let isMapStage: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isMapStage ? 1 - zoom.progress : 0)
            .scaleEffect(isMapStage ? 1 - 0.06 * zoom.progress : 1.08)
    }
}

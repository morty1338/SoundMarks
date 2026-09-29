import MapKit
import SwiftUI

/// Command to the map camera. Runs once and is reset to `nil`.
enum MapCommand: Equatable {
    case fitAll
    case center(latitude: Double, longitude: Double, meters: CLLocationDistance)
    /// Landing after moving in from the planet.
    case land(latitude: Double, longitude: Double)
    /// Center on my location.
    case followUser
}

/// `MKMapView` in SwiftUI.
///
/// SwiftUI's `Map` has no native clustering via `clusteringIdentifier`,
/// so the map lives in a `UIViewRepresentable`.
struct PlaceMapView: UIViewRepresentable {
    /// Token of the place set: grows when pins really need reconciling.
    struct PlacesToken: Equatable {
        let regionRevision: Int
        let yearIndex: Int
    }

    let places: [PlaceSnapshot]
    let placesToken: PlacesToken
    let pinStyle: PinStyle
    /// Default record skin; a place can have its own.
    var defaultSkinID: String = SkinCatalog.standardID
    /// Day — light map, night — dark.
    var isDay = false
    /// Finger tap on a pin (not programmatic selection).
    var onTapPlace: ((UUID) -> Void)?
    /// Map center after every gesture.
    var onCenterChange: ((CLLocationCoordinate2D) -> Void)?
    /// Visible area while moving: center and span in latitude and longitude.
    var onVisibleRegionChange: ((CLLocationCoordinate2D, Double, Double) -> Void)?
    @Binding var selectedPlaceID: UUID?
    @Binding var command: MapCommand?
    /// Point chosen with a long press: the dart flies into it.
    let dartCoordinate: CLLocationCoordinate2D?
    /// A stack of places at one point — expands as a list.
    let onOpenCluster: ([PlaceSnapshot]) -> Void
    /// Long press on the map — start of adding a place.
    let onLongPress: (CLLocationCoordinate2D) -> Void
    /// The place whose preview is playing: its pin spins.
    var playingPlaceID: UUID?
    /// The map was zoomed out to continent scale — time to return to the planet.
    var onZoomedOutToPlanet: (() -> Void)?
    /// How far the map has already "turned" into the planet: 0…1, continuously during the gesture.
    /// The third parameter — whether to animate (reset after an unfinished gesture).
    var onZoomOutProgress: ((Double, CLLocationCoordinate2D, Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false

        // A drawn look within MapKit: a muted dark scheme without POIs,
        // tinted in the planet's palette.
        // Flat map: on iPhone MapKit never folds it into a globe anyway, and 3D terrain
        // only slows panning down.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration
        mapView.overrideUserInterfaceStyle = isDay ? .light : .dark
        mapView.addOverlay(PaperTileOverlay(isDay: isDay), level: .aboveLabels)
        context.coordinator.appliedDay = isDay
        mapView.register(PlaceAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: PlaceAnnotationView.reuseIdentifier)
        mapView.register(PlaceClusterAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: PlaceClusterAnnotationView.reuseIdentifier)
        mapView.register(DartAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: DartAnnotationView.reuseIdentifier)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        mapView.addGestureRecognizer(longPress)

        // A pinch beyond the MapKit limit drives the transition into the planet.
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        mapView.addGestureRecognizer(pinch)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncDaylight(in: mapView, isDay: isDay)
        context.coordinator.sync(annotationsIn: mapView, with: places, token: placesToken,
                                 appearance: PinAppearance(style: pinStyle, defaultSkinID: defaultSkinID))
        context.coordinator.syncHighlight(in: mapView, to: selectedPlaceID)
        context.coordinator.syncDart(in: mapView, to: dartCoordinate)
        context.coordinator.syncSpinning(in: mapView, placeID: playingPlaceID)

        if let command {
            context.coordinator.apply(command, to: mapView)
            // The command is one-shot: reset it outside the current update cycle.
            DispatchQueue.main.async { self.command = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: PlaceMapView
        private var annotationsByID: [UUID: PlaceAnnotation] = [:]
        private var appliedAppearance: PinAppearance?
        private var appliedToken: PlacesToken?
        var appliedDay = false
        /// The highlighted record (selected, or current in the "All" strip).
        private var highlightedID: UUID?
        private var dart: DartAnnotation?
        private var spinningPlaceID: UUID?
        /// While the map is "landing" after the planet, zooming out must not return back.
        private var planetReturnArmedAt = Date().addingTimeInterval(1.5)

        init(parent: PlaceMapView) {
            self.parent = parent
        }

        // MARK: Annotations

        func sync(annotationsIn mapView: MKMapView, with places: [PlaceSnapshot], token: PlacesToken,
                  appearance: PinAppearance) {
            // The map updates on every screen change (selection, player, strip), while places
            // change rarely: without a new token or pin look there is no reason to reconcile a thousand annotations.
            guard token != appliedToken || appearance != appliedAppearance else { return }
            appliedToken = token

            // Changing the style or skin requires redrawing all pins, including stacks:
            // simpler to remove the annotations and let the diff below add them again.
            if appliedAppearance != appearance {
                appliedAppearance = appearance
                if !annotationsByID.isEmpty {
                    mapView.removeAnnotations(Array(annotationsByID.values))
                    annotationsByID.removeAll()
                }
            }

            let incoming = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            let removedIDs = annotationsByID.keys.filter { incoming[$0] == nil }
            let changedIDs = annotationsByID.filter { id, annotation in
                guard let place = incoming[id] else { return false }
                return place != annotation.place
            }.keys

            let toRemove = (Array(removedIDs) + Array(changedIDs)).compactMap { annotationsByID[$0] }
            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
                for annotation in toRemove { annotationsByID.removeValue(forKey: annotation.place.id) }
            }

            let toAdd = incoming.values
                .filter { annotationsByID[$0.id] == nil }
                .map(PlaceAnnotation.init(place:))
            if !toAdd.isEmpty {
                for annotation in toAdd { annotationsByID[annotation.place.id] = annotation }
                mapView.addAnnotations(toAdd)
            }

        }

        /// The highlighted record: larger and never hidden in a stack.
        ///
        /// Our own highlight, not MapKit selection: MapKit doesn't report a repeated tap
        /// on a selected pin, and our pins must always be tappable. To pull the record out of the stack
        /// its annotation is re-added — MapKit asks for the view again and sees that clustering
        /// is disabled for it.
        func syncHighlight(in mapView: MKMapView, to id: UUID?) {
            guard id != highlightedID else { return }
            let previous = highlightedID
            highlightedID = id
            for changed in [previous, id].compactMap({ $0 }) {
                guard let annotation = annotationsByID[changed] else { continue }
                mapView.removeAnnotation(annotation)
                mapView.addAnnotation(annotation)
            }
        }

        /// Day and night: a light scheme with a paper tint or a dark violet one.
        func syncDaylight(in mapView: MKMapView, isDay: Bool) {
            guard isDay != appliedDay else { return }
            appliedDay = isDay
            mapView.overrideUserInterfaceStyle = isDay ? .light : .dark
            mapView.removeOverlays(mapView.overlays.filter { $0 is PaperTileOverlay })
            mapView.addOverlay(PaperTileOverlay(isDay: isDay), level: .aboveLabels)
        }

        /// Places or removes the dart of the chosen point.
        func syncDart(in mapView: MKMapView, to coordinate: CLLocationCoordinate2D?) {
            guard let coordinate else {
                if let dart {
                    mapView.removeAnnotation(dart)
                    self.dart = nil
                }
                return
            }

            if let dart {
                // Same point — don't recreate the view, otherwise the animation plays again.
                guard dart.coordinate.latitude != coordinate.latitude
                    || dart.coordinate.longitude != coordinate.longitude
                else { return }
                mapView.removeAnnotation(dart)
            }

            let annotation = DartAnnotation(coordinate: coordinate)
            dart = annotation
            mapView.addAnnotation(annotation)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let mapView = recognizer.view as? MKMapView
            else { return }

            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(coordinate)
        }

        /// The pin of the place whose preview is playing spins like a record on a turntable.
        func syncSpinning(in mapView: MKMapView, placeID: UUID?) {
            guard placeID != spinningPlaceID else { return }

            if let previous = spinningPlaceID, let annotation = annotationsByID[previous],
               let view = mapView.view(for: annotation) {
                (view as? PlaceAnnotationView)?.setSpinning(false)
            }
            spinningPlaceID = placeID

            guard let placeID, let annotation = annotationsByID[placeID],
                  let view = mapView.view(for: annotation)
            else { return }

            (view as? PlaceAnnotationView)?.setSpinning(true)
        }

        func apply(_ command: MapCommand, to mapView: MKMapView) {
            switch command {
            case .fitAll:
                let annotations = Array(annotationsByID.values)
                guard !annotations.isEmpty else { return }
                mapView.showAnnotations(annotations, animated: true)

            case .followUser:
                mapView.setUserTrackingMode(.follow, animated: true)

            case let .center(latitude, longitude, meters):
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                )
                mapView.setRegion(region, animated: true)

            case let .land(latitude, longitude):
                // Continuation of the move in from the planet: from the wide shot down to country level, not city.
                let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                planetReturnArmedAt = Date().addingTimeInterval(1.4)
                mapView.setRegion(MKCoordinateRegion(center: center,
                                                     span: MKCoordinateSpan(latitudeDelta: Self.landingStartSpan,
                                                                            longitudeDelta: Self.landingStartSpan)),
                                  animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    mapView.setRegion(MKCoordinateRegion(center: center,
                                                         span: MKCoordinateSpan(latitudeDelta: Self.countrySpan,
                                                                                longitudeDelta: Self.countrySpan)),
                                      animated: true)
                }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let appearance = appliedAppearance
                ?? PinAppearance(style: parent.pinStyle, defaultSkinID: parent.defaultSkinID)

            if annotation is DartAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: DartAnnotationView.reuseIdentifier,
                    for: annotation
                )
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PlaceClusterAnnotationView.reuseIdentifier,
                    for: cluster
                ) as? PlaceClusterAnnotationView
                view?.configure(with: cluster, appearance: appearance)
                return view
            }

            guard let place = annotation as? PlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: PlaceAnnotationView.reuseIdentifier,
                for: place
            ) as? PlaceAnnotationView
            view?.configure(with: place.place, appearance: appearance,
                            isHighlighted: place.place.id == highlightedID)
            view?.setSpinning(place.place.id == spinningPlaceID)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(annotation, animated: false)

                if cluster.isTightlyPacked {
                    // Nothing left to zoom into — expand as a list.
                    parent.onOpenCluster(cluster.places)
                } else {
                    mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                }
                return
            }

            guard let place = (annotation as? PlaceAnnotation)?.place else { return }
            // Clear the MapKit selection right away: that way the pin is tappable again, even when highlighted.
            mapView.deselectAnnotation(annotation, animated: false)
            parent.onTapPlace?(place.id)
        }

        // MARK: Zooming out into the planet

        /// Country level — the map lands here from the planet.
        static let countrySpan: Double = 12
        static let landingStartSpan: Double = 22

        /// Pinch scale at the moment the map hit the MapKit zoom-out limit.
        private var overscrollAnchor: CGFloat?
        private var overscrollProgress: Double = 0
        private var lastPinchScale: CGFloat = 1
        private var lastAltitude: CLLocationDistance = 0

        /// The map zooms out on its own up to the MapKit limit (whole world on screen). Beyond that the pinch
        /// no longer changes anything in MapKit — our planet picks it up: the map fades,
        /// and the planet shrinks after the fingers down to its own size.
        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            switch recognizer.state {
            case .began:
                overscrollAnchor = nil
                overscrollProgress = 0
                lastPinchScale = recognizer.scale
                lastAltitude = mapView.camera.centerCoordinateDistance

            case .changed:
                guard Date() > planetReturnArmedAt else { return }
                let altitude = mapView.camera.centerCoordinateDistance
                if overscrollAnchor == nil {
                    // Fingers pinch in but the camera barely rises — MapKit hit its limit.
                    let pinchingOut = recognizer.scale < lastPinchScale * 0.99
                    let clamped = altitude <= lastAltitude * 1.002
                    if pinchingOut, clamped, mapView.region.span.latitudeDelta > 80 {
                        overscrollAnchor = recognizer.scale
                    }
                    lastPinchScale = recognizer.scale
                    lastAltitude = altitude
                }
                guard let anchor = overscrollAnchor else { return }
                let progress = min(max(Double(1 - recognizer.scale / anchor) / 0.55, 0), 1)
                guard abs(progress - overscrollProgress) > 0.004 else { return }
                overscrollProgress = progress
                parent.onZoomOutProgress?(progress, mapView.region.center, false)

            case .ended, .cancelled, .failed:
                defer {
                    overscrollAnchor = nil
                    overscrollProgress = 0
                }
                guard overscrollAnchor != nil else { return }
                if overscrollProgress >= 0.35 {
                    // Far enough — complete the transition to the planet.
                    planetReturnArmedAt = Date().addingTimeInterval(2)
                    parent.onZoomedOutToPlanet?()
                } else {
                    // Not far enough: the planet fades out smoothly, the map stays.
                    parent.onZoomOutProgress?(0, mapView.region.center, true)
                }

            default:
                break
            }
        }

        nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // MapKit's pinch keeps working — ours only listens in.
            true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onCenterChange?(mapView.region.center)
            reportVisibleRegion(of: mapView)
        }

        /// While moving: the model reads more places only when the map leaves the loaded area.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            reportVisibleRegion(of: mapView)
        }

        private func reportVisibleRegion(of mapView: MKMapView) {
            let region = mapView.region
            parent.onVisibleRegionChange?(region.center, region.span.latitudeDelta, region.span.longitudeDelta)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let paper = overlay as? PaperTileOverlay {
                return PaperTileOverlay.renderer(for: paper)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

    }
}

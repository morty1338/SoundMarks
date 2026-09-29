import SceneKit
import UIKit

/// Planet scene: a slightly cartoonish Earth (night or day), atmosphere and place dots.
///
/// The planet stands like a globe: vertical axis, equator in the center, it only spins
/// around its axis (`spin` — finger and inertia; the globe and place dots rotate together).
/// The camera always looks along `-Z`; zooming into a point is a camera move.
@MainActor
final class GlobeScene {
    /// The main planet or a small one — in the "Friends Marks" grid and the "Add Planet" window.
    enum Style {
        case main
        case mini
    }

    /// Wide shot: the planet is ~72% of the width — neighboring planets clearly peek in at the edges.
    nonisolated static let defaultCameraDistance: Float = 3.6
    /// Horizontal camera field of view, degrees.
    nonisolated static let fieldOfView: Double = 44
    /// On the wide shot the camera is raised — the planet sits below center with the "My Marks" title above it.
    nonisolated static let verticalShift: Float = 0.45
    /// The mini planet fills almost its entire square.
    nonisolated static let miniCameraDistance: Float = 2.92

    /// Planet disc diameter on the wide shot as a fraction of the screen width.
    nonisolated static var discWidthFraction: Double {
        let silhouette = asin(1 / Double(defaultCameraDistance))
        return tan(silhouette) / tan(fieldOfView / 2 * .pi / 180)
    }

    /// Mini planet disc diameter as a fraction of its square.
    nonisolated static var miniDiscFraction: Double {
        let silhouette = asin(1 / Double(miniCameraDistance))
        return tan(silhouette) / tan(fieldOfView / 2 * .pi / 180)
    }

    /// How many points the disc center sits below the center of a screen of width `width`.
    nonisolated static func discCenterOffset(forWidth width: Double) -> Double {
        let focal = width / 2 / tan(fieldOfView / 2 * .pi / 180)
        return focal * Double(verticalShift) / Double(defaultCameraDistance)
    }

    /// Camera right at the surface — the map starts here.
    static let closeCameraDistance: Float = 1.3

    let style: Style
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let spin = SCNNode()
    let globe: SCNNode
    private let dotsNode = SCNNode()
    private let atmosphere: SCNNode

    /// Current rotation of the globe around its axis, radians.
    private(set) var yaw: Float = 0
    private(set) var isDay = false

    /// A place marker. It no longer has its own node — markers are drawn in a batch,
    /// and two points in the `dotsNode` space are enough for taps.
    private struct Dot {
        let coordinate: SphereMapping.Coordinate
        /// Base of the marker: tells whether it is on our side of the planet.
        let base: simd_float3
        /// Middle of the marker — the finger aims at it.
        let target: simd_float3
    }

    private(set) var markerStyle: PlanetMarkerStyle = .default

    private var dots: [Dot] = []
    private var dotCoordinates: [SphereMapping.Coordinate] = []

    init(style: Style = .main) {
        self.style = style

        let camera = SCNCamera()
        // Horizontal angle: otherwise the planet doesn't fit the width on a tall screen.
        camera.projectionDirection = .horizontal
        camera.fieldOfView = Self.fieldOfView
        camera.zNear = 0.01
        camera.zFar = 200
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // The scene background is empty: the stars are a shared screen layer behind, so planets can
        // move while paging. A clear color isn't set as background — on the device
        // SceneKit draws it as a pink fill.
        scene.background.contents = nil
        switch style {
        case .main:
            cameraNode.simdPosition = simd_float3(0, Self.verticalShift, Self.defaultCameraDistance)
        case .mini:
            // Same viewing angle as the big planet (slightly from above), but the disc centered in the square:
            // in the carousel the mini planet replaces the big one without a jump.
            let angle = atan(Self.verticalShift / Self.defaultCameraDistance)
            cameraNode.simdPosition = simd_float3(0, Self.miniCameraDistance * tan(angle), Self.miniCameraDistance)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }

        globe = Self.makeGlobe(style: style)
        atmosphere = Self.makeAtmosphere()

        scene.rootNode.addChildNode(spin)
        spin.addChildNode(globe)
        spin.addChildNode(dotsNode)
        scene.rootNode.addChildNode(atmosphere)

        addMarkerLights()
        face(longitude: 15, animated: false)
    }

    // MARK: - Time of day

    /// Day — a light cartoonish Earth, night — a dark one with city lights.
    func setDaylight(_ day: Bool) {
        guard day != isDay else { return }
        isDay = day
        globe.geometry?.firstMaterial?.setValue(NSNumber(value: day ? 1.0 : 0.0), forKey: "dayMix")
        atmosphere.geometry?.firstMaterial?.setValue(NSNumber(value: day ? 1.0 : 0.0), forKey: "dayMix")
        rebuildDots()
    }

    // MARK: - Rotation and focus

    func setYaw(_ value: Float) {
        yaw = value
        spin.eulerAngles.y = value
    }

    /// Turns the globe to a longitude. No tilt: the planet always stands like a globe —
    /// equator in the center, vertical axis.
    func face(longitude: Double, animated: Bool, duration: TimeInterval = 0.8) {
        let targetYaw = Float(SphereMapping.yawFacing(longitude: longitude))
        // Shortest path — so the globe doesn't make an extra turn.
        var delta = (targetYaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        setYaw(yaw + delta)
        SCNTransaction.commit()
    }

    /// A friend's planet: quickly spins a few turns and stops at the longitude.
    func spinAndSettle(longitude: Double, turns: Int = 3, duration: TimeInterval = 1.6) {
        let targetYaw = Float(SphereMapping.yawFacing(longitude: longitude))
        var delta = (targetYaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if delta < 0 { delta += 2 * .pi }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.6, 0.2, 1)
        setYaw(yaw + delta + Float(turns) * 2 * .pi)
        SCNTransaction.commit()
    }

    /// A mini planet slowly spins on its own.
    func startAutoRotation(secondsPerTurn: TimeInterval = 40) {
        guard spin.action(forKey: "auto") == nil else { return }
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: secondsPerTurn)), forKey: "auto")
    }

    // MARK: - Camera

    /// Camera: 0 — at the surface above latitude `latitude`, 1 — the wide shot.
    ///
    /// The planet doesn't tilt, so for a northern or southern point the camera
    /// moves there itself — shifting up or down, always looking along `-Z`.
    func setZoom(_ progress: Double, latitude: Double = 0, animated: Bool, duration: TimeInterval = 0.8) {
        guard style == .main else { return }
        let t = Float(min(max(progress, 0), 1))
        let radians = Float(min(max(latitude, -80), 80) * .pi / 180)
        let surfaceGap = Self.closeCameraDistance - 1
        let close = simd_float3(0, sin(radians), cos(radians) + surfaceGap)
        let far = simd_float3(0, Self.verticalShift, Self.defaultCameraDistance)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        cameraNode.simdPosition = close + (far - close) * t
        SCNTransaction.commit()
    }

    /// Zooming into a point: the planet turns to its longitude, the camera flies to it.
    func dive(toLatitude latitude: Double, longitude: Double, duration: TimeInterval) {
        face(longitude: longitude, animated: true, duration: duration)
        setZoom(0, latitude: latitude, animated: true, duration: duration)
    }

    // MARK: - Place dots

    func setPlaces(_ coordinates: [SphereMapping.Coordinate]) {
        guard coordinates != dotCoordinates else { return }
        dotCoordinates = coordinates
        rebuildDots()
    }

    /// Lights, flags or pushpins — as chosen in settings.
    func setMarkerStyle(_ style: PlanetMarkerStyle) {
        guard style != markerStyle else { return }
        markerStyle = style
        rebuildDots()
    }

    /// Markers are built in a batch: for hundreds of places — a handful of nodes and draw calls instead of
    /// two to five nodes and a billboard constraint per place.
    private func rebuildDots() {
        dotsNode.childNodes.forEach { $0.removeFromParentNode() }
        dots = []
        let isMini = style == .mini
        let merged = PlanetDots.dots(for: dotCoordinates, mergeDistance: 2.5)
        guard !merged.isEmpty else { return }

        var placements: [(normal: simd_float3, count: Int)] = []
        placements.reserveCapacity(merged.count)
        for dot in merged {
            let local = SphereMapping.position(latitude: dot.coordinate.latitude,
                                               longitude: dot.coordinate.longitude,
                                               radius: 1.0)
            placements.append((simd_normalize(simd_float3(Float(local.x), Float(local.y), Float(local.z))), dot.count))
        }

        switch markerStyle {
        case .glow:
            dotsNode.addChildNode(Self.makeGlowBatch(placements, isDay: isDay, isMini: isMini))
            dotsNode.addChildNode(Self.makeCoreBatch(placements.map(\.normal), isMini: isMini))
            for (dot, placement) in zip(merged, placements) {
                let base = placement.normal * 1.006
                dots.append(Dot(coordinate: dot.coordinate, base: base, target: base))
            }

        case .flag, .pushpin:
            let solid = SCNNode()
            for (index, (dot, placement)) in zip(merged, placements).enumerated() {
                let (node, height) = markerStyle == .flag
                    ? MarkerModels.flag(colorIndex: index, isMini: isMini)
                    : MarkerModels.pushpin(colorIndex: index, isMini: isMini)
                node.simdPosition = placement.normal
                node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: placement.normal)

                // The flag turns toward the viewer around the pole — this part stays
                // a separate node with the constraint, while the base and pole are merged with everything else.
                let turning = node.childNodes.filter { !($0.constraints ?? []).isEmpty }
                if !turning.isEmpty {
                    let anchor = SCNNode()
                    anchor.simdTransform = node.simdTransform
                    for child in turning {
                        child.removeFromParentNode()
                        anchor.addChildNode(child)
                    }
                    dotsNode.addChildNode(anchor)
                }
                solid.addChildNode(node)
                dots.append(Dot(coordinate: dot.coordinate, base: placement.normal,
                                target: placement.normal * (1 + height / 2)))
            }
            // One node: SceneKit merges geometry with shared materials into a few draw calls.
            dotsNode.addChildNode(solid.flattenedClone())
        }
    }

    /// Light only for 3D markers: the planet is drawn in "flat" colors and ignores it.
    private func addMarkerLights() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 450
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Light from over the camera's shoulder — a highlight on flags and pushpin heads.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.5, 0.4, 0)
        cameraNode.addChildNode(keyNode)
    }

    /// The dot under the finger — by on-screen distance. Dots on the far side don't count.
    func dot(at point: CGPoint, in view: SCNView, tolerance: CGFloat) -> SphereMapping.Coordinate? {
        let camera = cameraNode.presentation.simdWorldPosition
        let transform = dotsNode.presentation.simdWorldTransform
        var best: (coordinate: SphereMapping.Coordinate, distance: CGFloat)?

        for dot in dots {
            let world = transform * simd_float4(dot.base, 1)
            let position = simd_float3(world.x, world.y, world.z)
            guard simd_dot(simd_normalize(position), simd_normalize(camera - position)) > 0.05 else { continue }
            // For a flag or pushpin the finger aims at the middle, not the base.
            let aim = transform * simd_float4(dot.target, 1)
            let projected = view.projectPoint(SCNVector3(aim.x, aim.y, aim.z))
            let distance = hypot(point.x - CGFloat(projected.x), point.y - CGFloat(projected.y))
            if distance <= tolerance, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (dot.coordinate, distance)
            }
        }
        return best?.coordinate
    }

    // MARK: - Building

    /// Reduced texture for mini planets: there are many on screen, the full 3600×1800
    /// for each is wasted memory and load time.
    private static let miniTexture: UIImage? = {
        guard let full = UIImage(named: "EarthNight") else { return nil }
        let size = CGSize(width: 1024, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Plain 8 bits: the texture doesn't need the display's wide color range.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            full.draw(in: CGRect(origin: .zero, size: size))
        }
    }()

    private static func makeGlobe(style: Style) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = style == .main ? 96 : 48

        let material = SCNMaterial()
        material.lightingModel = .constant
        if let texture = style == .main ? UIImage(named: "EarthNight") : miniTexture {
            material.diffuse.contents = texture
        } else {
            material.diffuse.contents = UIColor(red: 0.08, green: 0.12, blue: 0.34, alpha: 1)
        }
        material.diffuse.mipFilter = .linear
        material.diffuse.wrapS = .repeat

        // A slightly cartoonish Earth: flat colors instead of a photo.
        // The ocean in the NASA texture is one flat color, so land is separated by distance
        // to it rather than by brightness: that way the dark Amazon isn't lost.
        // By day — a light palette without lights, at night — a dark one with city lights.
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float dayMix;
            #pragma body
            // SceneKit works in linear space: convert the texture back to sRGB,
            // in which the thresholds were measured, and the final palette back to linear.
            // The sRGB curve is exact, with the linear segment: otherwise the almost black ocean
            // slips past the threshold and becomes land.
            float3 linearTexel = max(_output.color.rgb, float3(0.0));
            float3 texel = select(1.055 * pow(linearTexel, float3(1.0 / 2.4)) - 0.055,
                                  linearTexel * 12.92,
                                  linearTexel <= float3(0.0031308));
            float lum = dot(texel, float3(0.299, 0.587, 0.114));
            float landMask = smoothstep(0.012, 0.035, length(texel - float3(0.016, 0.020, 0.059)));
            // Land relief — in two steps, not smoothly.
            float relief = step(0.10, lum);

            float3 nightBase = mix(float3(0.025, 0.035, 0.11),
                                 mix(float3(0.11, 0.10, 0.23), float3(0.15, 0.13, 0.29), relief), landMask);
            float3 dayBase = mix(float3(0.36, 0.62, 0.86),
                               mix(float3(0.53, 0.75, 0.45), float3(0.70, 0.79, 0.50), relief), landMask);
            float3 base = mix(nightBase, dayBase, dayMix);

            // City lights — three steps of a warm color, only at night.
            float lights = smoothstep(0.17, 0.5, lum);
            lights = floor(lights * 3.0 + 0.35) / 3.0;
            float3 color = mix(base, float3(0.95, 0.74, 0.40), lights * 0.85 * (1.0 - dayMix));

            // A dark rim at the edge of the disc — like an outline in an illustration.
            float facing = max(dot(normalize(_surface.normal), normalize(_surface.view)), 0.0);
            color *= mix(mix(0.7, 0.82, dayMix), 1.0, smoothstep(0.05, 0.3, facing));

            float3 linearColor = select(pow((color + 0.055) / 1.055, float3(2.4)),
                                        color / 12.92,
                                        color <= float3(0.04045));
            _output.color = float4(linearColor, 1.0);
            """,
        ]
        material.setValue(NSNumber(value: 0.0), forKey: "dayMix")
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.name = "globe"
        return node
    }

    /// A soft glow around the planet: blue at night, light blue by day.
    private static func makeAtmosphere() -> SCNNode {
        let sphere = SCNSphere(radius: 1.045)
        sphere.segmentCount = 96

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.diffuse.contents = UIColor.black
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float dayMix;
            #pragma body
            float facing = max(dot(normalize(_surface.normal), normalize(_surface.view)), 0.0);
            float rim = pow(1.0 - facing, 4.0);
            // Color in linear space: a soft halo, not a bright ring.
            float3 tint = mix(float3(0.06, 0.12, 0.45), float3(0.25, 0.55, 1.0), dayMix);
            _output.color = float4(tint, 1.0) * rim * 0.8;
            """,
        ]
        material.setValue(NSNumber(value: 0.0), forKey: "dayMix")
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.renderingOrder = 10
        return node
    }

    /// Geometry of a dot core: one per size, copied into the merged node.
    private static var coreGeometry: [String: SCNGeometry] = [:]

    /// Halos of all places as one geometry. Each halo is a quad of four vertices at the center
    /// of the dot; the shader turns it toward the camera, like `SCNBillboardConstraint` on each node did before.
    /// At night the halo is warm and glowing; by day it is an accent so the dot is visible on light land.
    private static func makeGlowBatch(_ placements: [(normal: simd_float3, count: Int)],
                                      isDay: Bool, isMini: Bool) -> SCNNode {
        let scale: Double = isMini ? 1.5 : 1
        var positions: [SCNVector3] = []
        var corners: [CGPoint] = []
        var uvs: [CGPoint] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(placements.count * 4)
        corners.reserveCapacity(placements.count * 4)
        uvs.reserveCapacity(placements.count * 4)
        indices.reserveCapacity(placements.count * 6)

        for placement in placements {
            let bucket = min(Int(log2(Double(max(placement.count, 1))).rounded()), 4)
            let half = (0.075 + Double(bucket) * 0.008) * scale / 2
            let center = placement.normal * 1.006
            let first = UInt32(positions.count)
            // Top left, bottom left, bottom right, top right.
            for (x, y, u, v) in [(-1.0, 1.0, 0.0, 0.0), (-1, -1, 0, 1), (1, -1, 1, 1), (1, 1, 1, 0)] {
                positions.append(SCNVector3(center.x, center.y, center.z))
                corners.append(CGPoint(x: x * half, y: y * half))
                uvs.append(CGPoint(x: u, y: v))
            }
            indices += [first, first + 1, first + 2, first, first + 2, first + 3]
        }

        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                             SCNGeometrySource(textureCoordinates: uvs),
                                             SCNGeometrySource(textureCoordinates: corners)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = isDay ? DotTexture.day : DotTexture.night
        material.blendMode = isDay ? .alpha : .add
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        material.shaderModifiers = [.geometry: glowBillboard]
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.renderingOrder = 5
        return node
    }

    /// Turning the halo quad toward the camera: the corner offset is added in camera space.
    private static let glowBillboard = """
    float4 center = scn_node.modelViewTransform * _geometry.position;
    center.xy += _geometry.texcoords[1];
    _geometry.position = scn_node.inverseModelViewTransform * center;
    """

    /// Light cores of all dots — one merged node.
    private static func makeCoreBatch(_ normals: [simd_float3], isMini: Bool) -> SCNNode {
        let key = "\(isMini)"
        let core = coreGeometry[key] ?? {
            let sphere = SCNSphere(radius: 0.011 * (isMini ? 1.5 : 1))
            sphere.segmentCount = 12
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 1)
            sphere.materials = [material]
            coreGeometry[key] = sphere
            return sphere
        }()

        let container = SCNNode()
        for normal in normals {
            let node = SCNNode(geometry: core)
            node.simdPosition = normal * 1.006
            container.addChildNode(node)
        }
        let flat = container.flattenedClone()
        flat.renderingOrder = 6
        return flat
    }
}

/// Halo of a place dot.
@MainActor
enum DotTexture {
    /// Night: a warm glow, blended additively with the dark Earth.
    static let night = render(inner: UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 1),
                              middle: UIColor(red: 1, green: 0.72, blue: 0.38, alpha: 0.75),
                              outer: UIColor(red: 1, green: 0.5, blue: 0.25, alpha: 0))
    /// Day: a saturated accent over the light Earth.
    static let day = render(inner: UIColor(red: 1, green: 0.35, blue: 0.5, alpha: 1),
                            middle: UIColor(red: 0.95, green: 0.2, blue: 0.45, alpha: 0.7),
                            outer: UIColor(red: 0.95, green: 0.2, blue: 0.45, alpha: 0))

    private static func render(inner: UIColor, middle: UIColor, outer: UIColor) -> UIImage {
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let colors = [inner.cgColor, middle.cgColor, outer.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 0.4, 1]) else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            renderer.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                                  endCenter: center, endRadius: side / 2, options: [])
        }
    }
}

/// 3D place markers: a flag like in a board game and a long school pushpin.
/// Geometry and materials are shared by all markers — only positions are new.
@MainActor
enum MarkerModels {
    /// Bright plastic colors, like board game pieces.
    private static let colors: [UIColor] = [
        UIColor(red: 0.93, green: 0.22, blue: 0.3, alpha: 1),
        UIColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1),
        UIColor(red: 0.25, green: 0.55, blue: 0.98, alpha: 1),
        UIColor(red: 0.45, green: 0.85, blue: 0.38, alpha: 1),
        UIColor(red: 0.72, green: 0.42, blue: 0.95, alpha: 1),
    ]

    private static var materials: [String: SCNMaterial] = [:]
    private static var geometries: [String: SCNGeometry] = [:]

    private static func plastic(_ color: UIColor, key: String) -> SCNMaterial {
        if let cached = materials[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color
        material.specular.contents = UIColor(white: 1, alpha: 0.7)
        material.shininess = 0.6
        materials[key] = material
        return material
    }

    private static func geometry(_ key: String, make: () -> SCNGeometry) -> SCNGeometry {
        if let cached = geometries[key] { return cached }
        let made = make()
        geometries[key] = made
        return made
    }

    /// A flag on a stand: a white pole and a triangular flag turned toward the camera.
    static func flag(colorIndex: Int, isMini: Bool) -> (SCNNode, Float) {
        let scale: CGFloat = isMini ? 1.6 : 1
        let height = 0.11 * scale
        let color = colors[colorIndex % colors.count]
        let sizeKey = isMini ? "mini" : "main"

        let root = SCNNode()

        let base = SCNNode(geometry: geometry("flagBase|\(sizeKey)") {
            let cylinder = SCNCylinder(radius: 0.013 * scale, height: 0.005 * scale)
            cylinder.materials = [plastic(UIColor(white: 0.25, alpha: 1), key: "base")]
            return cylinder
        })
        base.position = SCNVector3(0, Float(0.0025 * scale), 0)
        root.addChildNode(base)

        let pole = SCNNode(geometry: geometry("pole|\(sizeKey)") {
            let cylinder = SCNCylinder(radius: 0.0032 * scale, height: height)
            cylinder.radialSegmentCount = 8
            cylinder.materials = [plastic(UIColor(white: 0.95, alpha: 1), key: "pole")]
            return cylinder
        })
        pole.position = SCNVector3(0, Float(height / 2), 0)
        root.addChildNode(pole)

        // The flag turns around the pole toward the viewer — it is visible from any side.
        let holder = SCNNode()
        holder.position = SCNVector3(0, Float(height), 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        holder.constraints = [billboard]
        let cloth = SCNNode(geometry: geometry("flagCloth|\(sizeKey)|\(colorIndex % colors.count)") {
            let path = UIBezierPath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0.055 * scale, y: -0.018 * scale))
            path.addLine(to: CGPoint(x: 0, y: -0.036 * scale))
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.003 * scale)
            shape.materials = [plastic(color, key: "color\(colorIndex % colors.count)")]
            return shape
        })
        holder.addChildNode(cloth)
        root.addChildNode(holder)

        return (root, Float(height))
    }

    /// A long school pushpin: a steel needle and a colored head with a wide rim.
    static func pushpin(colorIndex: Int, isMini: Bool) -> (SCNNode, Float) {
        let scale: CGFloat = isMini ? 1.6 : 1
        let needle = 0.06 * scale
        let body = 0.034 * scale
        let color = colors[colorIndex % colors.count]
        let sizeKey = isMini ? "mini" : "main"
        let colorKey = "color\(colorIndex % colors.count)"

        let root = SCNNode()

        let needleNode = SCNNode(geometry: geometry("needle|\(sizeKey)") {
            let cone = SCNCone(topRadius: 0.0022 * scale, bottomRadius: 0.0006 * scale, height: needle)
            cone.radialSegmentCount = 8
            let steel = SCNMaterial()
            steel.lightingModel = .blinn
            steel.diffuse.contents = UIColor(white: 0.7, alpha: 1)
            steel.specular.contents = UIColor.white
            steel.shininess = 1
            cone.materials = [steel]
            return cone
        })
        needleNode.position = SCNVector3(0, Float(needle / 2), 0)
        root.addChildNode(needleNode)

        let bodyNode = SCNNode(geometry: geometry("pinBody|\(sizeKey)|\(colorKey)") {
            let cone = SCNCone(topRadius: 0.009 * scale, bottomRadius: 0.006 * scale, height: body)
            cone.radialSegmentCount = 16
            cone.materials = [plastic(color, key: colorKey)]
            return cone
        })
        bodyNode.position = SCNVector3(0, Float(needle + body / 2), 0)
        root.addChildNode(bodyNode)

        let capNode = SCNNode(geometry: geometry("pinCap|\(sizeKey)|\(colorKey)") {
            let cylinder = SCNCylinder(radius: 0.015 * scale, height: 0.007 * scale)
            cylinder.radialSegmentCount = 20
            cylinder.materials = [plastic(color, key: colorKey)]
            return cylinder
        })
        capNode.position = SCNVector3(0, Float(needle + body + 0.0035 * scale), 0)
        root.addChildNode(capNode)

        return (root, Float(needle + body + 0.007 * scale))
    }
}

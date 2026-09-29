import SwiftUI

/// Record geometry in the `SplashRecord` photo, in source pixels.
///
/// Measured on the shot: the disc is slightly squashed vertically because of the angle.
/// If the photo is replaced — update these numbers, otherwise the shards won't match the disc.
enum SplashArtwork {
    static let imageName = "SplashRecord"
    static let pixelSize = CGSize(width: 736, height: 981)
    static let recordCenter = CGPoint(x: 361.5, y: 527)
    static let recordRadii = CGSize(width: 280.5, height: 276)
    static let holeRadius = 0.11
    /// Wall color — it covers the spot the disc flew out of.
    static let wall = Color(red: 222 / 255, green: 218 / 255, blue: 209 / 255)
}

/// Photo layout on screen: aspect fill, as in the sketch.
struct SplashLayout {
    let imageRect: CGRect
    let center: CGPoint
    let radii: CGSize

    init(size: CGSize) {
        let source = SplashArtwork.pixelSize
        let scale = max(size.width / source.width, size.height / source.height)
        let drawn = CGSize(width: source.width * scale, height: source.height * scale)
        imageRect = CGRect(x: (size.width - drawn.width) / 2,
                           y: (size.height - drawn.height) / 2,
                           width: drawn.width, height: drawn.height)
        center = CGPoint(x: imageRect.minX + SplashArtwork.recordCenter.x * scale,
                         y: imageRect.minY + SplashArtwork.recordCenter.y * scale)
        radii = CGSize(width: SplashArtwork.recordRadii.width * scale,
                       height: SplashArtwork.recordRadii.height * scale)
    }

    /// Unit disc point → screen point.
    func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: center.x + unit.x * radii.width, y: center.y + unit.y * radii.height)
    }

    func path(_ points: [CGPoint], closed: Bool = true) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: point(first))
        for next in points.dropFirst() { path.addLine(to: point(next)) }
        if closed { path.closeSubpath() }
        return path
    }

    var discRect: CGRect {
        CGRect(x: center.x - radii.width, y: center.y - radii.height,
               width: radii.width * 2, height: radii.height * 2)
    }
}

/// Splash: the record crackles, bursts and flies apart, the background darkens to space.
///
/// Drawn with a single `Canvas` over time: shard physics is computed analytically
/// from the moment of impact, so the animation is deterministic and independent of the frame rate.
struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var effects = SplashEffects()
    @State private var didFinish = false

    private let pattern = ShatterGeometry.pattern(
        options: .init(wedges: 9, holeRadius: SplashArtwork.holeRadius, arcSteps: 6)
    )

    // Timing, seconds from the start.
    private enum Timing {
        static let crack = 0.85
        static let explode = 1.0
        static let darken = 0.9
        static let end = 2.05
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)

            Canvas { context, size in
                draw(in: &context, size: size, elapsed: reduceMotion ? min(elapsed, 0) : elapsed)
            }
            .overlay {
                if reduceMotion {
                    // Without motion: just the fade to dark.
                    Color.black.opacity(min(1, elapsed / Timing.end))
                }
            }
            .onChange(of: elapsed >= Timing.end) { _, isOver in
                if isOver { finish() }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel(Text("splash.accessibility", comment: "Splash, tap to skip"))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            startDate = Date()
            effects.play(crackDelay: Timing.crack)
        }
        .onDisappear { effects.stop() }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        effects.stop()
        onFinish()
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let layout = SplashLayout(size: size)
        let image = context.resolve(Image(SplashArtwork.imageName))
        let screen = CGRect(origin: .zero, size: size)

        context.fill(Path(screen), with: .color(SplashArtwork.wall))

        let exploded = elapsed >= Timing.explode

        // Photo. After the impact the disc is cut out, and the photo itself dissolves within a fraction of a second
        // into the flat wall color: otherwise the wall texture around the hole gives away the disc outline.
        if exploded {
            let fade = min(1, (elapsed - Timing.explode) / 0.22)
            if fade < 1 {
                var background = context
                background.opacity = 1 - fade
                var hole = Path(screen)
                hole.addEllipse(in: layout.discRect)
                background.clip(to: hole, style: FillStyle(eoFill: true))
                background.draw(image, in: layout.imageRect)
            }
        } else {
            // Before the impact the disc trembles slightly — like a needle on a scratch.
            let tremble = elapsed > Timing.crack - 0.25 ? sin(elapsed * 90) * 0.6 : 0
            var intact = context
            intact.translateBy(x: tremble, y: 0)
            intact.draw(image, in: layout.imageRect)
        }

        // Cracks spread a moment before the shards fly apart.
        if elapsed >= Timing.crack, !exploded {
            let progress = (elapsed - Timing.crack) / (Timing.explode - Timing.crack)
            for crack in pattern.cracks {
                let path = layout.path(crack, closed: false).trimmedPath(from: 0, to: progress)
                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 2)
                context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 0.7)
            }
        }

        if exploded {
            drawShards(in: context, layout: layout, image: image, time: elapsed - Timing.explode)
        }

        // Fading to the black of space.
        let darkness = min(1, max(0, (elapsed - Timing.explode) / Timing.darken))
        if darkness > 0 {
            context.fill(Path(screen), with: .color(DS.Colors.space.opacity(darkness)))
        }
    }

    private func drawShards(in context: GraphicsContext,
                            layout: SplashLayout,
                            image: GraphicsContext.ResolvedImage,
                            time: TimeInterval) {
        let gravity = 1400.0
        let baseSpeed = max(layout.radii.width, layout.radii.height) * 2.6

        for shard in pattern.shards {
            let origin = layout.point(shard.centroid)
            let length = max(hypot(shard.centroid.x, shard.centroid.y), 0.001)
            let direction = CGVector(dx: shard.centroid.x / length, dy: shard.centroid.y / length)

            let speed = baseSpeed * shard.speed
            let dx = direction.dx * speed * time
            // A slight toss upward, then gravity.
            let dy = (direction.dy * speed - 260) * time + 0.5 * gravity * time * time

            var piece = context
            piece.opacity = max(0, 1 - pow(time / 0.95, 1.6))
            piece.translateBy(x: origin.x + dx, y: origin.y + dy)
            piece.rotate(by: .radians(shard.spin * 6 * time))
            piece.translateBy(x: -origin.x, y: -origin.y)
            piece.clip(to: layout.path(shard.points))
            piece.draw(image, in: layout.imageRect)
        }
    }
}

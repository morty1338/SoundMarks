import SwiftUI

/// Title above the planet: "My Marks", "Friends Marks". Light green, no shadow:
/// depth comes from a vertical sheen and a light edge on top of the letters.
struct MarksTitle: View {
    let text: String
    var size: CGFloat = 46

    var body: some View {
        label
            .foregroundStyle(LinearGradient(colors: [DS.Colors.marks, DS.Colors.marksShade],
                                            startPoint: .top, endPoint: .bottom))
            .overlay {
                label
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                    startPoint: .top, endPoint: .center))
                    .blendMode(.screen)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityAddTraits(.isHeader)
    }

    private var label: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .black, design: .rounded).italic())
    }
}

/// Record drawing for the "5 ◉" counter.
struct VinylGlyph: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().fill(DS.Colors.vinyl)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                .padding(size * 0.12)
            Circle().fill(DS.Colors.accent).frame(width: size * 0.38, height: size * 0.38)
            Circle().fill(.white).frame(width: size * 0.08, height: size * 0.08)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Rectangular "number / record drawing" button — opens all records.
struct RecordCountButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Spacing.s) {
                Text(verbatim: "\(count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.onDarkText)
                VinylGlyph(size: 24)
            }
            .padding(.horizontal, DS.Spacing.l)
            .frame(minWidth: 96, minHeight: DS.Size.tapTarget + 4)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small))
        }
        .buttonStyle(.plain)
        .liquidGlass(in: RoundedRectangle(cornerRadius: DS.Radius.small))
        .disabled(count == 0)
        .accessibilityLabel(Text(String(localized: "planet.recordCount", defaultValue: "\(count) records")))
        .accessibilityHint(Text("planet.records.hint", comment: "Opens the record roulette"))
    }
}

/// Text button on glass — "Add Planet".
struct GlassTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(verbatim: title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DS.Colors.marks)
                .padding(.horizontal, DS.Spacing.m)
                .frame(minHeight: DS.Size.tapTarget)
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small))
        }
        .buttonStyle(.plain)
        .liquidGlass(in: RoundedRectangle(cornerRadius: DS.Radius.small))
    }
}

/// The "F" button — friends screen.
struct FriendsButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(verbatim: "F")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.onDarkText)
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text("planet.friends", comment: "Friends"))
    }
}

/// Screen rectangle with a cutout for the planet disc (even-odd fill).
struct DiscCutout: Shape {
    let diameter: CGFloat
    /// Downward offset of the disc center from the rectangle center.
    var centerOffset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.midX - diameter / 2, y: rect.midY + centerOffset - diameter / 2,
                                   width: diameter, height: diameter))
        return path
    }
}

/// Edge of a neighboring planet: the same Earth, dimmed.
struct PlanetPeek: View {
    let diameter: CGFloat
    var isDay = false

    var body: some View {
        Image("EarthNight")
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .colorMultiply(isDay ? Color(red: 0.7, green: 0.85, blue: 1.0) : .white)
            .overlay {
                Circle().fill(
                    RadialGradient(colors: [.clear, .black.opacity(isDay ? 0.35 : 0.6)],
                                   center: .center, startRadius: diameter * 0.25, endRadius: diameter * 0.5)
                )
            }
            .background {
                Circle()
                    .fill(Color(red: 0.2, green: 0.35, blue: 0.9).opacity(0.55))
                    .blur(radius: 14)
                    .padding(-8)
            }
            .contentShape(Circle())
    }
}

/// Starry sky — an image drawn once: it isn't redrawn on every
/// screen change and doesn't slow down paging.
struct StarryBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: StarryBackground.image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @MainActor static let image: UIImage = {
        let size = CGSize(width: 430, height: 932)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var random = SplitMix64(seed: 0x57A25)
            for _ in 0..<320 {
                let x = random.next(in: 0...Double(size.width))
                let y = random.next(in: 0...Double(size.height))
                let bright = random.next(in: 0...1) > 0.95
                let radius = bright ? random.next(in: 0.9...1.5) : random.next(in: 0.3...0.8)
                let alpha = bright ? 0.95 : random.next(in: 0.25...0.7)
                UIColor(white: 1, alpha: alpha).setFill()
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
    }()
}

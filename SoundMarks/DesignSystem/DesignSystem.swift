import SwiftUI
import UIKit

/// Design tokens: colors, spacing, radii, animations.
/// All in one place so screens do not drift apart in style.
enum DS {
    // MARK: - Colors

    enum Colors {
        /// The app's single accent.
        static let accent = Color.accentColor
        /// Home screen space.
        static let space = Color(red: 0.02, green: 0.02, blue: 0.05)
        /// Light splash background.
        static let splash = Color(red: 0.96, green: 0.96, blue: 0.95)
        /// Vinyl record body.
        static let vinyl = Color(white: 0.06)
        /// The "My Marks" and "Friends Marks" titles and related buttons are light green.
        static let marks = Color(red: 0.66, green: 0.93, blue: 0.56)
        static let marksShade = Color(red: 0.42, green: 0.80, blue: 0.40)
        /// Glow of a place dot on the planet.
        static let placeGlow = Color(red: 1.0, green: 0.82, blue: 0.55)

        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let onDarkText = Color.white
        static let onDarkSecondary = Color.white.opacity(0.65)
    }

    // MARK: - Metrics

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 20
        static let large: CGFloat = 28
        static let sheet: CGFloat = 32
    }

    enum Size {
        /// Minimum tap area per HIG.
        static let tapTarget: CGFloat = 44
        /// Pin diameter on the map.
        static let pin: CGFloat = 44
        /// Center record in the roulette.
        static let rouletteRecord: CGFloat = 220
    }

    // MARK: - Animations

    enum Motion {
        static let quick = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let standard = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.82)
        static let lazy = SwiftUI.Animation.easeInOut(duration: 0.55)
        /// Planet ↔ map transition.
        static let worldZoom = SwiftUI.Animation.timingCurve(0.22, 0.85, 0.28, 1, duration: 0.85)
    }
}

// MARK: - Liquid Glass

/// Glass backing: `glassEffect` on iOS 26+, a material with a soft shadow below that.
/// No outlines — per the design system.
struct LiquidGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
    }
}

extension View {
    /// Floating glass panel or button.
    func liquidGlass<S: Shape>(in shape: S = Capsule()) -> some View {
        modifier(LiquidGlassBackground(shape: shape))
    }
}

/// Round glass icon button — the main control on the map and the planet.
struct GlassIconButton: View {
    let systemImage: String
    var accessibilityKey: LocalizedStringKey
    var size: CGFloat = DS.Size.tapTarget
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text(accessibilityKey))
    }
}

// MARK: - Haptics

/// Haptic feedback in one place so feedback strength stays consistent.
@MainActor
enum Haptics {
    /// Regular button press.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Tap on a pin, planet change.
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Year step on the timeline.
    static func step() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
    }

    /// Place added.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Glass hit in the splash.
    static func crack() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

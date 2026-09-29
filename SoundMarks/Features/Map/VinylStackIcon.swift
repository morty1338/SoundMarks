import SwiftUI

/// "Record stack" icon for the roulette button.
/// Temporary — will be replaced by an illustration from Assets.
struct VinylStackIcon: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { layer in
                disc
                    .offset(x: CGFloat(2 - layer) * size * 0.09, y: CGFloat(2 - layer) * -size * 0.09)
                    .opacity(layer == 2 ? 1 : 0.8)
            }
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .accessibilityHidden(true)
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(DS.Colors.vinyl)
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
            Circle()
                .fill(DS.Colors.accent)
                .frame(width: size * 0.34, height: size * 0.34)
            Circle()
                .fill(.white)
                .frame(width: size * 0.08, height: size * 0.08)
        }
        .frame(width: size * 0.9, height: size * 0.9)
    }
}

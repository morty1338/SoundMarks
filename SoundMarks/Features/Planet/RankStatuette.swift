import SwiftUI

/// Rank statuette — an instrument figure on a stand:
/// note, headphones, guitars, keys, microphone and the legend's golden notes.
/// The first ranks are bronze, the middle ones silver, the top ones gold.
struct RankStatuette: View {
    let level: Int
    var size: CGFloat = 28

    static let symbols = ["music.note", "headphones", "guitars.fill", "pianokeys", "music.mic", "music.quarternote.3"]

    /// Metal by rank: bronze, silver, gold.
    static func metal(for level: Int) -> LinearGradient {
        let colors: [Color] = switch level {
        case ..<2: [Color(red: 0.95, green: 0.7, blue: 0.45), Color(red: 0.62, green: 0.38, blue: 0.2)]
        case 2...3: [Color(red: 0.95, green: 0.96, blue: 1.0), Color(red: 0.6, green: 0.63, blue: 0.7)]
        default: [Color(red: 1.0, green: 0.9, blue: 0.5), Color(red: 0.85, green: 0.6, blue: 0.1)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let symbol = Self.symbols[min(max(level, 0), Self.symbols.count - 1)]
        VStack(spacing: size * 0.02) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.58, weight: .bold))
                .foregroundStyle(Self.metal(for: level))
                .overlay {
                    // Highlight on the figure.
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.58, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.white.opacity(0.7), .clear],
                                                        startPoint: .topLeading, endPoint: .center))
                        .blendMode(.screen)
                }
                .frame(height: size * 0.66)
                .shadow(color: level >= 5 ? Color(red: 1, green: 0.85, blue: 0.4).opacity(0.8) : .clear,
                        radius: size * 0.2)

            // Stand.
            Pedestal()
                .fill(Self.metal(for: level))
                .overlay(Pedestal().stroke(.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: size * 0.78, height: size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The statuette stand: a trapezoid with a step.
private struct Pedestal: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.18
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

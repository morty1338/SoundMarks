import Foundation

/// How places are marked on the planet.
enum PlanetMarkerStyle: String, CaseIterable, Identifiable, Sendable {
    /// A bright glowing dot.
    case glow
    /// A flag, like in a board game.
    case flag
    /// A long school pushpin.
    case pushpin

    static let `default`: PlanetMarkerStyle = .glow

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .glow: String(localized: "marker.glow", defaultValue: "Lights")
        case .flag: String(localized: "marker.flag", defaultValue: "Flags")
        case .pushpin: String(localized: "marker.pushpin", defaultValue: "Pushpins")
        }
    }
}

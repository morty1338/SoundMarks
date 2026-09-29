import Foundation

/// Pin look on the map. New styles are added as a case here
/// plus drawing in the map layer — the rest of the code works through this type.
enum PinStyle: String, CaseIterable, Identifiable, Sendable {
    /// A three-dimensional vinyl record with the track artwork in the center. The default.
    case vinyl
    /// Turntable.
    case turntable

    var id: String { rawValue }

    static let `default`: PinStyle = .vinyl

    var localizedName: String {
        switch self {
        case .vinyl: String(localized: "pinStyle.vinyl", defaultValue: "Vinyl record")
        case .turntable: String(localized: "pinStyle.turntable", defaultValue: "Turntable")
        }
    }
}

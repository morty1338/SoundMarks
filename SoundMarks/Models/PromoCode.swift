import Foundation

/// Promo codes. Checked on the device, without a server.
enum PromoCode {
    enum Reward: Equatable, Sendable {
        /// All record skins at once, regardless of rank.
        case allSkins
    }

    private static let rewards: [String: Reward] = [
        "PENIS": .allSkins,
    ]

    /// Case and spaces don't matter.
    static func reward(for code: String) -> Reward? {
        rewards[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }
}

import Foundation
import Observation

/// User settings. Values live in plain stored properties
/// so `@Observable` tracks them, and are mirrored to `UserDefaults` on write.
///
/// Computed properties on top of `UserDefaults` do not work for this:
/// `@Observable` cannot see them and subscribed screens do not redraw.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let pinStyle = "settings.pinStyle"
        static let timelineEnabled = "settings.timelineEnabled"
        static let photoMatchWindowMinutes = "settings.photoMatchWindowMinutes"
        static let geofencesEnabled = "settings.geofencesEnabled"
        static let geofenceCooldownDays = "settings.geofenceCooldownDays"
        static let onThisDayEnabled = "settings.onThisDayEnabled"
        static let onThisDayHour = "settings.onThisDayHour"
        static let spotifyWebAPIEnabled = "settings.spotifyWebAPIEnabled"
        static let activeMusicSource = "settings.activeMusicSource"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let defaultSkinID = "settings.defaultSkinID"
        static let planetMarker = "settings.planetMarker"
        static let allSkinsUnlocked = "settings.allSkinsUnlocked"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Default pin style for all places.
    var pinStyle: PinStyle {
        didSet { defaults.set(pinStyle.rawValue, forKey: Key.pinStyle) }
    }

    /// Vertical timeline on the map. Part of the layout per the sketch; can be hidden in settings.
    var timelineEnabled: Bool {
        didSet { defaults.set(timelineEnabled, forKey: Key.timelineEnabled) }
    }

    /// Half-width of the "track ↔ photo" matching window. ±30 minutes by default.
    /// The UI limits the range — assigning to itself is not allowed here.
    var photoMatchWindowMinutes: Int {
        didSet { defaults.set(photoMatchWindowMinutes, forKey: Key.photoMatchWindowMinutes) }
    }

    /// Reminders when returning to a place. Require "always" location access.
    var geofencesEnabled: Bool {
        didSet { defaults.set(geofencesEnabled, forKey: Key.geofencesEnabled) }
    }

    /// How often the same place may remind you.
    var geofenceCooldownDays: Int {
        didSet { defaults.set(geofenceCooldownDays, forKey: Key.geofenceCooldownDays) }
    }

    var onThisDayEnabled: Bool {
        didSet { defaults.set(onThisDayEnabled, forKey: Key.onThisDayEnabled) }
    }

    /// Local hour at which the "on this day" notification arrives.
    var onThisDayHour: Int {
        didSet { defaults.set(onThisDayHour, forKey: Key.onThisDayHour) }
    }

    /// Feature flag: the Spotify Web API is only available to the developer and testers
    /// because of the Development Mode limit (5 users).
    var spotifyWebAPIEnabled: Bool {
        didSet { defaults.set(spotifyWebAPIEnabled, forKey: Key.spotifyWebAPIEnabled) }
    }

    /// Source used for "what is playing now".
    var activeMusicSource: MusicSourceKind? {
        didSet { defaults.set(activeMusicSource?.rawValue, forKey: Key.activeMusicSource) }
    }

    /// Onboarding is shown once; scanning can be reopened from settings.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Default record skin — chosen in the profile, on the "Records" tab.
    var defaultSkinID: String {
        didSet { defaults.set(defaultSkinID, forKey: Key.defaultSkinID) }
    }

    /// How places are marked on planets: lights, flags or pushpins.
    var planetMarker: PlanetMarkerStyle {
        didSet { defaults.set(planetMarker.rawValue, forKey: Key.planetMarker) }
    }

    /// A promo code unlocked all record skins.
    var allSkinsUnlocked: Bool {
        didSet { defaults.set(allSkinsUnlocked, forKey: Key.allSkinsUnlocked) }
    }

    /// Up to which rank skins are unlocked: by rank, or all at once via promo code.
    func skinUnlockLevel(for rank: Rank) -> Int {
        allSkinsUnlocked ? Int.max : rank.level
    }

    /// Redeems a promo code. `nil` — no such code.
    func redeem(_ code: String) -> PromoCode.Reward? {
        guard let reward = PromoCode.reward(for: code) else { return nil }
        switch reward {
        case .allSkins: allSkinsUnlocked = true
        }
        return reward
    }

    var photoMatchWindow: Duration { .seconds(photoMatchWindowMinutes * 60) }

    /// Matching options assembled from settings.
    var matcherOptions: MemoryMatcher.Options {
        MemoryMatcher.Options(window: photoMatchWindow)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pinStyle: PinStyle.default.rawValue,
            Key.timelineEnabled: true,
            Key.photoMatchWindowMinutes: 30,
            Key.geofencesEnabled: false,
            Key.geofenceCooldownDays: 7,
            Key.onThisDayEnabled: true,
            Key.onThisDayHour: 10,
            Key.spotifyWebAPIEnabled: false,
            Key.hasCompletedOnboarding: false,
            Key.defaultSkinID: SkinCatalog.standardID,
            Key.planetMarker: PlanetMarkerStyle.default.rawValue,
        ])

        pinStyle = PinStyle(rawValue: defaults.string(forKey: Key.pinStyle) ?? "") ?? .default
        timelineEnabled = defaults.bool(forKey: Key.timelineEnabled)
        photoMatchWindowMinutes = min(max(defaults.integer(forKey: Key.photoMatchWindowMinutes), 1), 24 * 60)
        geofencesEnabled = defaults.bool(forKey: Key.geofencesEnabled)
        geofenceCooldownDays = max(0, defaults.integer(forKey: Key.geofenceCooldownDays))
        onThisDayEnabled = defaults.bool(forKey: Key.onThisDayEnabled)
        onThisDayHour = min(23, max(0, defaults.integer(forKey: Key.onThisDayHour)))
        spotifyWebAPIEnabled = defaults.bool(forKey: Key.spotifyWebAPIEnabled)
        activeMusicSource = defaults.string(forKey: Key.activeMusicSource)
            .flatMap(MusicSourceKind.init(rawValue:))
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        defaultSkinID = defaults.string(forKey: Key.defaultSkinID) ?? SkinCatalog.standardID
        planetMarker = PlanetMarkerStyle(rawValue: defaults.string(forKey: Key.planetMarker) ?? "") ?? .default
        allSkinsUnlocked = defaults.bool(forKey: Key.allSkinsUnlocked)
    }
}

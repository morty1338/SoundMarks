import AVFoundation
import CoreHaptics
import Foundation

/// Splash sound and haptics, synchronized with the animation.
///
/// The `.ambient` audio session respects the silent switch:
/// in silence no sound plays, but the animation and haptics remain.
@MainActor
final class SplashEffects {
    /// Sound names in the bundle. Replace the files — no code changes needed.
    enum Sound: String {
        case crackle = "vinyl_crackle"
        case crack = "record_crack"
    }

    private var players: [AVAudioPlayer] = []
    private var engine: CHHapticEngine?
    private var hapticPlayer: (any CHHapticPatternPlayer)?

    /// Starts the crackle right away and the crunch after `crackDelay` seconds.
    func play(crackDelay: TimeInterval) {
        configureSession()

        if let crackle = player(for: .crackle) {
            crackle.play()
            players.append(crackle)
        }
        if let crack = player(for: .crack) {
            crack.play(atTime: crack.deviceCurrentTime + crackDelay)
            players.append(crack)
        }

        playHaptics(crackDelay: crackDelay)
    }

    func stop() {
        players.forEach { $0.stop() }
        players.removeAll()
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop()
        engine = nil
    }

    // MARK: - Sound

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.ui.debug("Splash audio session not activated: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func player(for sound: Sound) -> AVAudioPlayer? {
        let url = ["wav", "m4a", "mp3", "caf", "aiff"]
            .lazy
            .compactMap { Bundle.main.url(forResource: sound.rawValue, withExtension: $0) }
            .first
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            Log.ui.debug("Sound \(sound.rawValue, privacy: .public) not found — splash plays without it")
            return nil
        }
        player.prepareToPlay()
        return player
    }

    // MARK: - Haptics

    /// Light needle clicks, then a hit and a short tremor of the shards.
    private func playHaptics(crackDelay: TimeInterval) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        var events: [CHHapticEvent] = []
        var random = SplitMix64(seed: 42)

        var time = 0.05
        while time < crackDelay - 0.08 {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(random.next(in: 0.18...0.34))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
                ],
                relativeTime: time
            ))
            time += random.next(in: 0.08...0.17)
        }

        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
            ],
            relativeTime: crackDelay
        ))
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
            ],
            relativeTime: crackDelay + 0.02,
            duration: 0.3
        ))

        let fade = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 1),
                .init(relativeTime: 0.3, value: 0),
            ],
            relativeTime: crackDelay + 0.02
        )

        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameterCurves: [fade])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            self.engine = engine
            hapticPlayer = player
        } catch {
            Log.ui.debug("Splash haptics unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}

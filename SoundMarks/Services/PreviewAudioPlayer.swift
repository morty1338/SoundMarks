import AVFoundation
import Foundation
import Observation

/// Playback of a 30-second track preview.
///
/// Exactly one preview plays at a time; `stop()` is called when the card closes.
@MainActor
@Observable
final class PreviewAudioPlayer {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false

    @ObservationIgnored private var player: AVPlayer?
    // deinit of a @MainActor class isn't isolated, so the token is stored nonisolated.
    @ObservationIgnored nonisolated(unsafe) private var endObserver: (any NSObjectProtocol)?

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    /// Starts the preview from the beginning. Calling again for the same URL toggles play/pause.
    func play(_ url: URL) {
        if currentURL == url, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }

        stop()
        activateSession()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }

        self.player = player
        currentURL = url
        isPlaying = true
        player.play()
    }

    /// Stops the preview and releases the audio session so other music resumes.
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentURL = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        deactivateSession()
    }

    func toggle(_ url: URL) { play(url) }

    private func finish() {
        isPlaying = false
        player?.seek(to: .zero)
        deactivateSession()
    }

    // MARK: - Audio session

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            Log.ui.error("Could not activate the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Normal if the session is already inactive — the user doesn't need to know.
            Log.ui.debug("Audio session already released: \(error.localizedDescription, privacy: .public)")
        }
    }
}

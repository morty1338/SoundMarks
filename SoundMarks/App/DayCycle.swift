import Foundation
import Observation

/// Time of day for styling: planet and map are light by day and dark by night.
@MainActor
@Observable
final class DayCycle {
    /// Daytime is 7:00 to 19:59 local time.
    nonisolated static let dayHours = 7..<20

    private(set) var isDay: Bool

    @ObservationIgnored private var timer: Timer?

    init(now: Date = Date()) {
        isDay = Self.isDay(at: now)
    }

    nonisolated static func isDay(at date: Date, calendar: Calendar = .current) -> Bool {
        dayHours.contains(calendar.component(.hour, from: date))
    }

    /// Re-evaluates once a minute while the app is open.
    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(now: Date = Date()) {
        let day = Self.isDay(at: now)
        if day != isDay { isDay = day }
    }
}

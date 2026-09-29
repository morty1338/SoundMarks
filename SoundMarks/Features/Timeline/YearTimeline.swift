import Foundation
import Observation

/// Vertical timeline by year.
///
/// Top position — the current year: all places are visible. Drag down — an earlier year.
/// The map shows places up to and including the selected year.
@MainActor
@Observable
final class YearTimeline {
    /// Years top to bottom: from the current one to the earliest memory.
    private(set) var years: [Int]
    private(set) var selectedIndex = 0

    @ObservationIgnored private let currentYear: Int

    init(currentYear: Int = Calendar.current.component(.year, from: Date())) {
        self.currentYear = currentYear
        years = [currentYear]
    }

    var selectedYear: Int { years.indices.contains(selectedIndex) ? years[selectedIndex] : currentYear }

    /// Whether all places are visible — the slider is in the top position.
    var showsEverything: Bool { selectedIndex == 0 }

    func rebuild(from places: [some PlaceOrderable]) {
        rebuild(earliestYear: places.compactMap { $0.eventDate?.year }.min())
    }

    func rebuild(earliestYear: Int?) {
        let earliest = earliestYear ?? currentYear
        // Future dates don't stretch the scale upward: the top is always the current year.
        let bottom = min(earliest, currentYear)
        let wasAtTop = showsEverything
        let previous = selectedYear

        years = Array((bottom...currentYear).reversed())

        if wasAtTop {
            selectedIndex = 0
        } else {
            selectedIndex = years.firstIndex(of: previous) ?? 0
        }
    }

    /// Returns `true` if the year changed — for haptics on every step.
    @discardableResult
    func select(index: Int) -> Bool {
        let clamped = min(max(index, 0), max(years.count - 1, 0))
        guard clamped != selectedIndex else { return false }
        selectedIndex = clamped
        return true
    }

    func filter(_ places: [PlaceSnapshot]) -> [PlaceSnapshot] {
        showsEverything ? places : Self.visible(places, upTo: selectedYear)
    }

    /// Places up to and including the year. Places without a date are always visible.
    nonisolated static func visible(_ places: [PlaceSnapshot], upTo year: Int) -> [PlaceSnapshot] {
        places.filter { place in
            guard let eventYear = place.eventDate?.year else { return true }
            return eventYear <= year
        }
    }
}

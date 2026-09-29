import SwiftUI

/// The memory date on one line: day · month · year.
/// The year is required; day and month are optional and can be cleared.
struct EventDateEditor: View {
    @Binding var year: Int
    @Binding var month: Int?
    @Binding var day: Int?

    /// Capture date of the chosen photos — offered with a single button.
    let suggestion: EventDate?
    let onApplySuggestion: () -> Void

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 80)...current).reversed()
    }

    private var daysInMonth: Int {
        guard let month else { return 31 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start)
        else { return 31 }
        return range.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.s) {
                dayMenu
                separator
                monthMenu
                separator
                yearMenu
            }

            if let suggestion {
                Button(action: onApplySuggestion) {
                    Label {
                        Text(String(localized: "addPlace.usePhotoDate",
                                    defaultValue: "Use the photo date: \(suggestion.formatted())"))
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .font(.footnote)
                }
            }
        }
        .onChange(of: month) { _, newValue in
            if newValue == nil { day = nil }
            clampDay()
        }
        .onChange(of: year) { _, _ in clampDay() }
    }

    // MARK: - Date parts

    private var dayMenu: some View {
        Menu {
            Button {
                day = nil
            } label: {
                Text("addPlace.notSpecified", comment: "Not specified")
            }
            ForEach(1...daysInMonth, id: \.self) { value in
                Button(String(value)) { day = value }
            }
        } label: {
            chip(day.map { String(format: "%02d", $0) }, placeholder: "addPlace.day")
        }
        .disabled(month == nil)
        .opacity(month == nil ? 0.45 : 1)
        .accessibilityLabel(Text("addPlace.day", comment: "Day"))
    }

    private var monthMenu: some View {
        Menu {
            Button {
                month = nil
            } label: {
                Text("addPlace.notSpecified", comment: "Not specified")
            }
            ForEach(1...12, id: \.self) { value in
                Button(Self.monthName(value)) { month = value }
            }
        } label: {
            chip(month.map(Self.monthName), placeholder: "addPlace.month")
        }
        .accessibilityLabel(Text("addPlace.month", comment: "Month"))
    }

    private var yearMenu: some View {
        Menu {
            ForEach(years, id: \.self) { value in
                Button(String(value)) { year = value }
            }
        } label: {
            chip(String(year), placeholder: "addPlace.year")
        }
        .accessibilityLabel(Text("addPlace.year", comment: "Year"))
    }

    private var separator: some View {
        Text("·")
            .font(.headline)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func chip(_ value: String?, placeholder: LocalizedStringKey) -> some View {
        Group {
            if let value {
                Text(value).foregroundStyle(.primary)
            } else {
                Text(placeholder).foregroundStyle(.secondary)
            }
        }
        .font(.body.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, DS.Spacing.m)
        .frame(minHeight: DS.Size.tapTarget)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private func clampDay() {
        if let current = day, current > daysInMonth { day = daysInMonth }
    }

    private static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.shortStandaloneMonthSymbols
        guard symbols.indices.contains(month - 1) else { return String(month) }
        return symbols[month - 1].localizedCapitalized
    }
}

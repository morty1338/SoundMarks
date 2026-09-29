import SwiftUI

/// Banner of an ongoing trip: how many points are recorded and "Finish".
struct TripBanner: View {
    let trip: TripTracker.ActiveTrip
    let onFinish: () -> Void

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Circle()
                .fill(DS.Colors.accent)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)

            VStack(alignment: .leading, spacing: 0) {
                Text("trip.banner.title", comment: "Trip in progress")
                    .font(.footnote.weight(.semibold))
                Text("trip.banner.points \(trip.pointCount)", comment: "Route points recorded")
                    .font(.caption2)
                    .foregroundStyle(DS.Colors.onDarkSecondary)
            }
            .foregroundStyle(DS.Colors.onDarkText)

            Button {
                Haptics.tap()
                onFinish()
            } label: {
                Text("trip.finish", comment: "Finish trip")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(DS.Colors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(minHeight: DS.Size.tapTarget)
        }
        .padding(.leading, DS.Spacing.m)
        .padding(.trailing, 6)
        .liquidGlass(in: Capsule())
        .onAppear { isPulsing = true }
        .accessibilityElement(children: .contain)
    }
}

/// Trips in settings: start a new one and open past ones as history.
struct TripsSection: View {
    @Environment(AppEnvironment.self) private var environment

    let onOpenTrip: (UUID) -> Void

    @State private var trips: [TripRow] = []
    @State private var errorMessage: String?
    @State private var isStarting = false

    private struct TripRow: Identifiable {
        let id: UUID
        let name: String
        let interval: DateInterval?
        let placeCount: Int
    }

    var body: some View {
        SettingsCard(Text("settings.section.trips", comment: "Section: trips"),
                     footer: Text("trip.footer", comment: "How travel mode works")) {
            if environment.trips.active == nil {
                Button(action: start) {
                    SettingsRow(icon: "point.topleft.down.to.point.bottomright.curvepath",
                                color: Color(red: 0.25, green: 0.55, blue: 0.98),
                                title: Text("trip.start", comment: "Start trip"),
                                showsDivider: !trips.isEmpty || errorMessage != nil) {
                        if isStarting { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
            } else {
                Button {
                    Task {
                        if let id = await environment.trips.finish() {
                            reload()
                            onOpenTrip(id)
                        }
                    }
                } label: {
                    SettingsRow(icon: "flag.checkered", color: DS.Colors.accent,
                                title: Text("trip.finish", comment: "Finish trip"),
                                showsDivider: !trips.isEmpty)
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.accent)
                    .padding(DS.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                Button {
                    onOpenTrip(trip.id)
                } label: {
                    SettingsRow(icon: "map", color: Color(red: 0.45, green: 0.5, blue: 0.62),
                                title: Text(verbatim: trip.name),
                                subtitle: Text(verbatim: [trip.interval?.displayText,
                                                          trip.placeCount > 0
                                                            ? String(localized: "trip.row.places \(trip.placeCount)")
                                                            : nil]
                                    .compactMap { $0 }.joined(separator: " · ")),
                                showsDivider: index < trips.count - 1) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Colors.onDarkSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        trips = environment.trips.finishedTrips().compactMap { trip in
            guard let id = trip.id else { return nil }
            return TripRow(id: id, name: trip.name ?? "", interval: trip.dateInterval,
                           placeCount: (trip.places ?? []).filter { !$0.isTombstoned }.count)
        }
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                try await environment.trips.start()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

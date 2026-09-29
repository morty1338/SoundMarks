import SwiftUI

/// Analysis of one of my planets: pick a period — get where you were and what you listened to.
/// While it computes, a record spins.
struct PlanetAnalysisView: View {
    @Environment(AppEnvironment.self) private var environment

    let planet: PlanetInfo

    private enum Period: Hashable {
        case all
        case year(Int)
        case custom
    }

    private enum Phase: Equatable {
        case choosing
        case loading
        case done(PlanetAnalysisReport)
    }

    @State private var period: Period = .all
    @State private var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var phase: Phase = .choosing
    @State private var places: [PlaceSnapshot] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    MiniGlobeView(dots: planet.dots, isDay: environment.dayCycle.isDay, markerStyle: environment.settings.planetMarker)
                        .frame(width: 120, height: 120)
                    PlanetNameLabel(text: planet.title)

                    switch phase {
                    case .choosing: periodPicker
                    case .loading: loading
                    case .done(let report): result(report)
                    }
                }
                .padding(DS.Spacing.l)
                .animation(DS.Motion.standard, value: phase)
            }
            .scrollIndicators(.hidden)
            .background(SettingsStyle.background.ignoresSafeArea())
            .navigationTitle(Text("analysis.title", comment: "Planet analysis"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(DS.Colors.marks)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .task { loadPlaces() }
    }

    // MARK: - Period

    private var years: [Int] {
        Array(Set(places.compactMap { $0.eventDate?.year })).sorted(by: >)
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("analysis.period", comment: "Choose a period")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.s) {
                    chip(Text("analysis.period.all", comment: "All time"), .all)
                    ForEach(years, id: \.self) { year in
                        chip(Text(verbatim: String(year)), .year(year))
                    }
                    chip(Text("analysis.period.custom", comment: "Custom period"), .custom)
                }
            }

            if period == .custom {
                DatePicker(selection: $customStart, displayedComponents: .date) {
                    Text("analysis.period.from", comment: "From")
                }
                DatePicker(selection: $customEnd, in: customStart..., displayedComponents: .date) {
                    Text("analysis.period.to", comment: "To")
                }
            }

            Button(action: analyze) {
                Text("analysis.start", comment: "Analyze")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(DS.Colors.marks, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Spacing.s)
        }
    }

    private func chip(_ label: Text, _ value: Period) -> some View {
        let isSelected = period == value
        return Button {
            Haptics.select()
            period = value
        } label: {
            label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .padding(.horizontal, DS.Spacing.m)
                .frame(minHeight: 36)
                .background(isSelected ? DS.Colors.marks : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var interval: DateInterval {
        let calendar = Calendar.current
        switch period {
        case .all:
            return DateInterval(start: .distantPast, end: .distantFuture)
        case .year(let year):
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
            let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date()
            return DateInterval(start: start, end: end.addingTimeInterval(-1))
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd
            return DateInterval(start: start, end: max(start, end.addingTimeInterval(-1)))
        }
    }

    // MARK: - Analysis

    private func loadPlaces() {
        let request = Place.fetchRequest(scope: planet.page.scope)
        request.relationshipKeyPathsForPrefetching = ["track"]
        let context = environment.persistence.viewContext
        places = PlaceQueries.snapshots(of: (try? context.fetch(request)) ?? [], in: context)
    }

    private func analyze() {
        Haptics.tap()
        phase = .loading
        let places = places
        let interval = interval
        Task {
            let started = Date()
            // All-time history is huge — take only the needed range, but no wider than the places.
            let historyInterval = period == .all
                ? DateInterval(start: Date(timeIntervalSince1970: 0), end: Date())
                : interval
            let plays = await PlayHistoryStore.shared.plays(in: historyInterval)
            let report = await Task.detached(priority: .userInitiated) {
                PlanetAnalysis.report(places: places, plays: plays, interval: interval)
            }.value
            // The record manages a full turn — no screen flicker.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.9 { try? await Task.sleep(for: .seconds(0.9 - elapsed)) }
            Haptics.success()
            phase = .done(report)
        }
    }

    private var loading: some View {
        VStack(spacing: DS.Spacing.m) {
            TimelineView(.animation) { timeline in
                VinylRecordView(artworkURL: nil, skin: SkinCatalog.skin(id: environment.settings.defaultSkinID))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate * 200))
            }
            Text("analysis.loading", comment: "Calculating…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Spacing.l)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Result

    @ViewBuilder
    private func result(_ report: PlanetAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            if report.isEmpty {
                Text("analysis.empty", comment: "Nothing for this period")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.s), count: 3),
                          spacing: DS.Spacing.s) {
                    number(report.places, Text("profile.stat.records", comment: "Records"))
                    number(report.countries, Text("profile.stat.countries", comment: "Countries"))
                    number(report.cities, Text("profile.stat.cities", comment: "Cities"))
                }

                if let month = report.busiestMonth, let date = Calendar.current.date(from: month) {
                    card(Text("analysis.busiestMonth", comment: "Busiest month")) {
                        Text(date.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                    }
                }
                rankedCard(Text("analysis.topCities", comment: "Cities"), report.topCities)
                rankedCard(Text("analysis.topArtists", comment: "Artists on the planet"), report.topArtists)
                rankedCard(Text("analysis.topTracks", comment: "Tracks"), report.topTracks)

                if report.plays > 0 {
                    card(Text("analysis.history", comment: "What you listened to in this period")) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("analysis.plays \(report.plays)", comment: "Plays")
                                .font(.headline)
                            Text("analysis.hours \(String(format: "%.1f", report.listeningHours))",
                                 comment: "Hours of music")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ForEach(report.historyTopArtists) { item in
                                rankedRow(item)
                            }
                        }
                    }
                }
            }

            Button {
                phase = .choosing
            } label: {
                Text("analysis.again", comment: "Another period")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private func number(_ value: Int, _ title: Text) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(value)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
            title
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.small))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rankedCard(_ title: Text, _ items: [PlanetAnalysisReport.Ranked]) -> some View {
        if !items.isEmpty {
            card(title) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in rankedRow(item) }
                }
            }
        }
    }

    private func rankedRow(_ item: PlanetAnalysisReport.Ranked) -> some View {
        HStack {
            Text(verbatim: item.name)
                .lineLimit(1)
            Spacer()
            Text(verbatim: "\(item.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func card<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            title
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.m)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.medium))
    }
}

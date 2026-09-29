import MapKit
import SwiftUI

/// Trip summary: the route on the map, records along the way (with confirmation),
/// photos from the trip dates and a list of tracks. An already saved trip — history.
struct TripSummaryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let tripID: UUID
    let onSaved: () -> Void

    @State private var model: TripSummaryModel?
    @State private var isConfirmingDelete = false
    @State private var shareImage: ShareImage?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(Text("trip.summary.title", comment: "Trip summary title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .task {
            guard model == nil else { return }
            let created = TripSummaryModel(tripID: tripID, environment: environment)
            model = created
            await created.load()
        }
        .sheet(item: $shareImage) { item in
            ActivityView(items: [item.image])
        }
    }

    @ViewBuilder
    private func content(_ model: TripSummaryModel) -> some View {
        @Bindable var model = model

        List {
            Section {
                TextField(text: $model.name) {
                    Text("trip.name.placeholder", comment: "Trip name")
                }
                .font(.title3.weight(.semibold))
                .onSubmit { model.rename() }

                if let interval = model.interval {
                    Text(interval.displayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TripRouteMap(route: model.route,
                             stops: model.isHistory ? [] : model.stops,
                             places: model.savedPlaces)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.medium))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            }

            if model.phase == .loading {
                Section {
                    HStack(spacing: DS.Spacing.m) {
                        ProgressView()
                        Text("trip.summary.loading", comment: "Finding what played during the trip")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if model.isHistory {
                savedSection(model)
            } else {
                stopsSection(model)
            }

            if !model.photos.isEmpty {
                photosSection(model)
            }

            if !model.plays.isEmpty {
                tracksSection(model)
            }

            Section {
                if model.isHistory {
                    Button(action: { share(model) }) {
                        Label {
                            Text("trip.share", comment: "Share trip")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label {
                        Text("trip.delete", comment: "Delete trip")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            } footer: {
                Text("trip.delete.footer", comment: "Places stay on the planet")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.phase == .ready, !model.isHistory, !model.stops.isEmpty {
                Button {
                    Task {
                        if await model.save() { onSaved() }
                    }
                } label: {
                    Group {
                        if model.isSaving {
                            ProgressView()
                        } else {
                            Text("trip.save \(model.selectedCount)", comment: "Save N places")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(model.selectedCount == 0 || model.isSaving)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.s)
            }
        }
        .confirmationDialog(Text("trip.delete.confirm", comment: "Delete trip?"),
                            isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                if model.deleteTrip() {
                    Haptics.warning()
                    onSaved()
                    dismiss()
                }
            } label: {
                Text("trip.delete", comment: "Delete trip")
            }
        }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button(role: .cancel) { model.errorMessage = nil } label: { Text("common.ok", comment: "OK") }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Stops

    private func stopsSection(_ model: TripSummaryModel) -> some View {
        Section {
            if model.stops.isEmpty {
                Text(emptyStopsText(model))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                TripStopRow(number: index + 1,
                            stop: stop,
                            info: model.placeInfo[stop.id],
                            play: model.selectedPlay(of: stop),
                            isSelected: model.selectedStopIDs.contains(stop.id),
                            onToggle: { model.toggle(stop) },
                            onChooseTrack: { model.trackChoice[stop.id] = $0 })
            }
        } header: {
            Text("trip.stops", comment: "Records along the way")
        } footer: {
            if !model.stops.isEmpty {
                Text("trip.stops.footer", comment: "Mark the points to save")
            }
        }
    }

    private func emptyStopsText(_ model: TripSummaryModel) -> String {
        if !model.hasHistory {
            return String(localized: "trip.stops.noHistory",
                          defaultValue: "No listening history connected. Import Spotify or connect Last.fm in Settings, and your trip's songs will show up here.")
        }
        if model.route.isEmpty {
            return String(localized: "trip.stops.noRoute",
                          defaultValue: "The route wasn't recorded – location access seems to have been off.")
        }
        return String(localized: "trip.stops.none",
                      defaultValue: "Your history has no listening during this trip.")
    }

    private func savedSection(_ model: TripSummaryModel) -> some View {
        Section {
            ForEach(model.savedPlaces) { place in
                HStack(spacing: DS.Spacing.m) {
                    ArtworkImage(url: place.artworkURL, cornerRadius: 6)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.displayTitle).lineLimit(1)
                        Text(place.shortPlaceName ?? place.displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } header: {
            Text("trip.saved", comment: "Places from the trip")
        }
    }

    // MARK: - Photos and tracks

    private func photosSection(_ model: TripSummaryModel) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Spacing.s) {
                    ForEach(model.photos) { photo in
                        PhotoThumbnail(localIdentifier: photo.id)
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
            Text("trip.photos \(model.photos.count)", comment: "Photos from the trip dates")
        }
    }

    private func tracksSection(_ model: TripSummaryModel) -> some View {
        Section {
            ForEach(model.plays) { play in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(play.title).lineLimit(1)
                        Text(play.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(play.playedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("trip.tracks \(model.plays.count)", comment: "Trip tracks")
        }
    }

    // MARK: - Sharing

    private func share(_ model: TripSummaryModel) {
        Task {
            let route = await TripRouteSnapshot.render(route: model.route,
                                                       size: CGSize(width: 312, height: 312))
            var artworks: [UIImage] = []
            for place in model.savedPlaces.prefix(3) {
                if let url = place.artworkURL, let data = await ArtworkCache.shared.data(for: url),
                   let image = UIImage(data: data) {
                    artworks.append(image)
                }
            }
            let content = TripShareCard(name: model.name, interval: model.interval, route: route,
                                        places: Array(model.savedPlaces.prefix(3)), artworks: artworks)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            if let image = renderer.uiImage {
                shareImage = ShareImage(image: image)
            }
        }
    }
}

// MARK: - Stop row

private struct TripStopRow: View {
    let number: Int
    let stop: TripStop
    let info: PlaceInfo?
    let play: PlayRecord?
    let isSelected: Bool
    let onToggle: () -> Void
    let onChooseTrack: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? DS.Colors.accent : .secondary)
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected
                                ? Text("trip.stop.deselect", comment: "Don't save the stop")
                                : Text("trip.stop.select", comment: "Save the stop"))

            VStack(alignment: .leading, spacing: 4) {
                Text(info?.shortName ?? info?.city ?? String(localized: "trip.stop.number",
                                                            defaultValue: "Stop \(number)"))
                    .font(.body.weight(.semibold))
                if let play {
                    Text(verbatim: "\(play.title) — \(play.artist)")
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(play.playedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: DS.Spacing.m) {
                    if stop.plays.count > 1 {
                        Menu {
                            ForEach(Array(stop.plays.enumerated()), id: \.offset) { index, option in
                                Button("\(option.title) — \(option.artist)") { onChooseTrack(index) }
                            }
                        } label: {
                            Text("trip.stop.otherTracks \(stop.plays.count - 1)", comment: "Other tracks of the stop")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if !stop.photos.isEmpty {
                        Label {
                            Text(verbatim: "\(stop.photos.count)")
                        } icon: {
                            Image(systemName: "photo")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Route map

/// The trip route as a line and the dots of stops or saved places.
struct TripRouteMap: View {
    let route: [RouteSample]
    let stops: [TripStop]
    let places: [PlaceSnapshot]

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            if route.count > 1 {
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(DS.Colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                Annotation("", coordinate: stop.coordinate) {
                    Text(verbatim: "\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(DS.Colors.accent, in: Circle())
                }
            }
            ForEach(places) { place in
                Annotation("", coordinate: place.coordinate) {
                    Circle()
                        .fill(DS.Colors.vinyl)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().fill(DS.Colors.accent).frame(width: 6, height: 6))
                }
            }
            if let first = route.first, route.count == 1 {
                Marker("", coordinate: first.coordinate)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(Text("trip.map.accessibility", comment: "Trip route map"))
    }
}

/// Thumbnail of a photo from the library.
private struct PhotoThumbnail: View {
    @Environment(AppEnvironment.self) private var environment
    let localIdentifier: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: localIdentifier) {
            if let data = try? await environment.photos.imageData(for: localIdentifier,
                                                                  targetSize: CGSize(width: 200, height: 200)) {
                image = UIImage(data: data)
            }
        }
        .accessibilityHidden(true)
    }
}

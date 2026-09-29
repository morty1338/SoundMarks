import CoreLocation
import MapKit
import SwiftUI

/// Adding and editing a place: point, song, media, date.
///
/// Opens as a sheet at 70% height; closes with a swipe down.
struct AddPlaceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Where the dart landed. `nil` — use the current location.
    var initialCoordinate: CLLocationCoordinate2D?
    /// The place being edited.
    var editingPlaceID: UUID?
    /// Shared map the place is added to. `nil` — my planet.
    var targetMapID: UUID?
    let onSaved: () -> Void

    @State private var model: AddPlaceViewModel?
    @State private var isPickingTrack = false
    @State private var isPickingMedia = false
    @State private var isAdjustingPoint = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(backdrop)
            .navigationTitle(editingPlaceID == nil
                             ? Text("addPlace.title", comment: "New place")
                             : Text("addPlace.editTitle", comment: "Edit place"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard model == nil else { return }
            let created = AddPlaceViewModel(environment: environment,
                                            initialCoordinate: initialCoordinate,
                                            editingPlaceID: editingPlaceID,
                                            targetMapID: targetMapID)
            model = created
            await created.prepare()
        }
    }

    /// A soft vertical gradient instead of a flat fill.
    private var backdrop: some View {
        LinearGradient(
            colors: [Color(uiColor: .secondarySystemBackground),
                     Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ model: AddPlaceViewModel) -> some View {
        @Bindable var model = model

        ScrollView {
            VStack(spacing: 16) {
                placeCard(model)
                trackCard(model)
                mediaCard(model)
                dateCard(model)
                noteCard(model)

                RaisedPrimaryButton(title: "common.save", isBusy: model.isSaving) {
                    Task {
                        if await model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                }
                .disabled(!model.canSave)
                .opacity(model.canSave ? 1 : 0.5)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $isPickingTrack) {
            TrackSearchView(metadata: environment.metadata) { selected in
                model.selectTrackManually(selected)
            }
        }
        .sheet(isPresented: $isPickingMedia) {
            PhotoPicker(photoService: environment.photos) { picked in
                model.addMedia(picked)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isAdjustingPoint) {
            NavigationStack {
                PlacePickerMap(coordinate: $model.coordinate)
                    .navigationTitle(Text("addPlace.adjustPoint", comment: "Adjust point"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { isAdjustingPoint = false } label: {
                                Text("common.done", comment: "Done")
                            }
                        }
                    }
            }
        }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button(role: .cancel) { model.errorMessage = nil } label: {
                Text("common.ok", comment: "OK")
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Cards

    private func placeCard(_ model: AddPlaceViewModel) -> some View {
        RaisedCard(title: "addPlace.section.place", systemImage: "mappin.and.ellipse") {
            VStack(alignment: .leading, spacing: 12) {
                MapPreview(coordinate: model.coordinate)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture { isAdjustingPoint = true }

                HStack(spacing: 8) {
                    if model.isLocating {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.placeTitle ?? coordinateText(model.coordinate))
                        .font(.subheadline)
                        .foregroundStyle(model.placeTitle == nil ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                }

                HStack(spacing: 10) {
                    smallButton(titleKey: "addPlace.adjustPoint", systemImage: "hand.draw") {
                        isAdjustingPoint = true
                    }
                    smallButton(titleKey: "addPlace.locationMode.current", systemImage: "location") {
                        Task { await model.useCurrentLocation() }
                    }
                }
            }
        }
    }

    private func trackCard(_ model: AddPlaceViewModel) -> some View {
        RaisedCard(title: "addPlace.section.track", systemImage: "music.note") {
            if let track = model.track {
                HStack(spacing: 12) {
                    ArtworkImage(url: track.artworkURL, cornerRadius: 10)
                        .frame(width: 54, height: 54)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.body.weight(.medium)).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        isPickingTrack = true
                    } label: {
                        Text("addPlace.changeTrack", comment: "Change track")
                            .font(.footnote)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    smallButton(titleKey: "addPlace.findTrack", systemImage: "magnifyingglass") {
                        isPickingTrack = true
                    }

                    if model.isDetectingTrack {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("addPlace.detectingTrack", comment: "Detecting what is playing")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("addPlace.track.footer", comment: "Explanation of the track source")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func mediaCard(_ model: AddPlaceViewModel) -> some View {
        RaisedCard(title: "addPlace.section.media", systemImage: "photo.stack") {
            VStack(alignment: .leading, spacing: 12) {
                if !model.media.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.media) { item in
                                PickedMediaThumbnail(item: item) {
                                    model.removeMedia(item)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                smallButton(titleKey: "addPlace.addMedia", systemImage: "photo.badge.plus") {
                    isPickingMedia = true
                }
            }
        }
    }

    private func dateCard(_ model: AddPlaceViewModel) -> some View {
        @Bindable var model = model

        return RaisedCard(title: "addPlace.section.date", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                EventDateEditor(year: $model.year,
                                month: $model.month,
                                day: $model.day,
                                suggestion: model.photoDateSuggestion,
                                onApplySuggestion: model.applyPhotoDateSuggestion)

                Text("addPlace.date.footer", comment: "Month and day are optional")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func noteCard(_ model: AddPlaceViewModel) -> some View {
        @Bindable var model = model

        return RaisedCard(title: "addPlace.section.note", systemImage: "text.alignleft") {
            TextField(text: $model.note, axis: .vertical) {
                Text("addPlace.notePrompt", comment: "Note about the place")
            }
            .lineLimit(1...4)
        }
    }

    // MARK: - Small parts

    private func smallButton(titleKey: LocalizedStringKey,
                             systemImage: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(titleKey)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}

/// Non-interactive mini map of the chosen point.
private struct MapPreview: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 320,
            longitudinalMeters: 320
        ))) {
            Annotation("", coordinate: coordinate) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint, .white)
                    .shadow(radius: 3)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .id(coordinate.latitude + coordinate.longitude)
    }
}

/// Thumbnail of chosen media that is not saved yet.
private struct PickedMediaThumbnail: View {
    let item: PickedMedia
    let onRemove: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 5, y: 3)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel(Text("addPlace.removeMedia", comment: "Remove media"))
        }
        .task(id: item.id) {
            if let data = item.data {
                image = UIImage(data: data)
            } else if let localIdentifier = item.localIdentifier {
                let data = try? await environment.photos.imageData(
                    for: localIdentifier,
                    targetSize: CGSize(width: 220, height: 220)
                )
                image = data.flatMap(UIImage.init(data:))
            }
        }
    }
}

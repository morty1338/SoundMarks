import AVKit
import MapKit
import SwiftUI

/// Place detail screen.
///
/// The place name large in the content, the city and date below it; the song bar,
/// collage, dates, note and mini map. Closes with a swipe down.
struct PlaceDetailView: View {
    let place: PlaceSnapshot
    let player: PreviewAudioPlayer
    let loader: MediaLoader
    /// `nil` — a place from a friend's planet: view only.
    let onEdit: (() -> Void)?
    /// Deleting the place. The caller closes the sheet.
    let onDelete: (() -> Void)?

    @State private var mediaIndex = 0
    @State private var fullscreenMedia: PlaceSnapshot.Media?
    @State private var shareImage: ShareImage?
    @State private var shareFailure: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header
                trackBar
                mediaCollage
                dates
                if let note = place.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                miniMap
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xl)
        }
        .onDisappear { player.stop() }
        .fullScreenCover(item: $fullscreenMedia) { media in
            FullscreenMediaView(media: media, loader: loader)
        }
        .sheet(item: $shareImage) { item in
            ActivityView(items: [item.image])
        }
        .confirmationDialog(
            Text("place.delete.confirm", comment: "Really delete the place?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                player.stop()
                onDelete?()
            } label: {
                Text("place.delete", comment: "Delete place")
            }
        } message: {
            Text("place.delete.message", comment: "What happens on deletion")
        }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { shareFailure != nil },
                                    set: { if !$0 { shareFailure = nil } })) {
            Button(role: .cancel) { shareFailure = nil } label: {
                Text("common.ok", comment: "OK")
            }
        } message: {
            Text(shareFailure ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(place.shortPlaceName ?? place.displayTitle)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if let onEdit {
                    Button(action: onEdit) {
                        Label {
                            Text("place.edit", comment: "Edit")
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                }
                Button(action: makeShareCard) {
                    Label {
                        Text("place.share", comment: "Share")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if onDelete != nil {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label {
                            Text("place.delete", comment: "Delete place")
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                    .contentShape(Circle())
            }
            .liquidGlass(in: Circle())
            .accessibilityLabel(Text("place.menu", comment: "Place menu"))
        }
    }

    private var subtitle: String {
        [place.city, place.eventDate?.formatted()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Song bar

    private var trackBar: some View {
        HStack(spacing: DS.Spacing.m) {
            ArtworkImage(url: place.artworkURL, cornerRadius: 10)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let artist = place.trackArtist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let previewURL = place.previewURL {
                Button {
                    Haptics.tap()
                    player.play(previewURL)
                } label: {
                    Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(DS.Colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlayingThis
                    ? Text("player.pause", comment: "Pause")
                    : Text("player.play", comment: "Play"))
            }
        }
        .padding(DS.Spacing.m)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
    }

    private var isPlayingThis: Bool {
        player.isPlaying && player.currentURL == place.previewURL
    }

    // MARK: - Collage

    @ViewBuilder
    private var mediaCollage: some View {
        if !place.media.isEmpty {
            TabView(selection: $mediaIndex) {
                ForEach(Array(place.media.enumerated()), id: \.element.id) { index, media in
                    MediaThumbnail(media: media, loader: loader)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { fullscreenMedia = media }
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: place.media.count > 1 ? .always : .never))
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        }
    }

    // MARK: - Dates

    private var dates: some View {
        VStack(spacing: DS.Spacing.s) {
            if let eventDate = place.eventDate {
                LabeledContent {
                    Text(eventDate.formatted())
                } label: {
                    Text("place.eventDate", comment: "Memory date")
                }
            }
            LabeledContent {
                Text(place.createdAt.formatted(date: .abbreviated, time: .omitted))
            } label: {
                Text("place.createdAt", comment: "Added")
            }
        }
        .font(.subheadline)
    }

    // MARK: - Mini map

    private var miniMap: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        ))) {
            Annotation("", coordinate: place.coordinate) {
                VinylRecordView(artworkURL: place.artworkURL, labelRatio: 0.55)
                    .frame(width: 40, height: 40)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Sharing

    /// The card is drawn only when "Share" is tapped, not when the place opens.
    ///
    /// `ImageRenderer` draws synchronously, so the artwork and photos are loaded beforehand.
    private func makeShareCard() {
        Task {
            var artwork: UIImage?
            if let artworkURL = place.artworkURL,
               let data = await ArtworkCache.shared.data(for: artworkURL) {
                artwork = UIImage(data: data)
            }

            var photos: [UIImage] = []
            for media in place.media.prefix(3) {
                if let image = await loader.image(for: media,
                                                  targetSize: CGSize(width: 600, height: 600)) {
                    photos.append(image)
                }
            }

            let renderer = ImageRenderer(
                content: ShareCardContent(place: place, artwork: artwork, photos: photos)
            )
            renderer.scale = 3

            guard let image = renderer.uiImage else {
                shareFailure = String(localized: "error.shareCardFailed",
                                      defaultValue: "Couldn’t build the share card.")
                return
            }
            shareImage = ShareImage(image: image)
        }
    }
}

/// Wrapper to hand the finished image to `.sheet(item:)`.
struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Full-screen media.
private struct FullscreenMediaView: View {
    let media: PlaceSnapshot.Media
    let loader: MediaLoader

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var videoURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if media.kind == .video, let videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .ignoresSafeArea()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(Text("common.close", comment: "Close"))
                }
                Spacer()
            }
            .padding()
        }
        .task {
            if media.kind == .video {
                videoURL = await loader.videoURL(for: media)
            }
            if videoURL == nil {
                image = await loader.image(for: media, targetSize: CGSize(width: 2048, height: 2048))
            }
        }
    }
}

/// Native share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

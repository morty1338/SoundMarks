import CryptoKit
import SwiftUI

/// Candidate card: a full-bleed photo with the track, place and date on top of it.
///
/// Tap on the left or right half flips through the shots, the record in the corner
/// plays and pauses the preview.
struct CandidateCardView: View {
    let candidate: MemoryCandidate
    let loader: MediaLoader
    var artworkURL: URL?
    var hasPreview = false
    var isPlaying = false
    var onTogglePlayback: () -> Void = {}
    var onPickTrack: () -> Void = {}

    @State private var photoIndex = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                photo(size: proxy.size)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        flipPhoto(forward: location.x > proxy.size.width / 2)
                    }

                LinearGradient(stops: [.init(color: .clear, location: 0.42),
                                       .init(color: .black.opacity(0.55), location: 0.68),
                                       .init(color: .black.opacity(0.92), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)

                info
                    .padding(DS.Spacing.l)
            }
            .overlay(alignment: .top) { topBar.padding(DS.Spacing.m) }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Photo

    @ViewBuilder
    private func photo(size: CGSize) -> some View {
        let photos = candidate.photos
        if photos.indices.contains(photoIndex) {
            MediaThumbnail(media: Self.media(for: photos[photoIndex]),
                           loader: loader,
                           targetSize: CGSize(width: 1000, height: 1400))
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Rectangle()
                .fill(DS.Colors.vinyl)
                .frame(width: size.width, height: size.height)
        }
    }

    private func flipPhoto(forward: Bool) {
        let count = candidate.photos.count
        guard count > 1 else { return }
        let next = photoIndex + (forward ? 1 : -1)
        guard (0..<count).contains(next) else {
            Haptics.warning()
            return
        }
        Haptics.select()
        photoIndex = next
    }

    /// The image cache is keyed by media ID — every shot needs its own stable one.
    private static func media(for photo: PhotoAssetSnapshot) -> PlaceSnapshot.Media {
        PlaceSnapshot.Media(id: stableID(for: photo.id),
                            kind: photo.kind,
                            localIdentifier: photo.id,
                            hasEmbeddedData: false,
                            takenAt: photo.creationDate)
    }

    private static func stableID(for localIdentifier: String) -> UUID {
        // PhotoKit identifiers start with a UUID: "XXXXXXXX-…/L0/001".
        if let uuid = UUID(uuidString: String(localIdentifier.prefix(36))) { return uuid }
        let hex = SHA256.hash(data: Data(localIdentifier.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20).prefix(12)]
        return UUID(uuidString: parts.joined(separator: "-")) ?? UUID()
    }

    // MARK: - Overlays

    private var topBar: some View {
        VStack(spacing: DS.Spacing.s) {
            if candidate.photos.count > 1 {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(candidate.photos.indices, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == photoIndex ? 0.95 : 0.35))
                            .frame(height: 3)
                    }
                }
                .accessibilityHidden(true)
            }

            HStack {
                Spacer()
                if candidate.trackOptions.count > 1 {
                    Button {
                        Haptics.tap()
                        onPickTrack()
                    } label: {
                        Label {
                            Text(String(localized: "candidates.otherTracks",
                                         defaultValue: "\(candidate.trackOptions.count - 1) more matches"))
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Spacing.m)
                        .padding(.vertical, DS.Spacing.s)
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(in: Capsule())
                }
            }
        }
    }

    private var info: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                if let track = candidate.selectedTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 30, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(track.artist)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(DS.Colors.onDarkSecondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: DS.Spacing.s) {
                    if let place = candidate.placeName, !place.isEmpty {
                        chip(systemImage: "mappin.and.ellipse", text: place)
                            .layoutPriority(1)
                    }
                    chip(systemImage: "calendar", text: dateText)
                }
                .padding(.top, DS.Spacing.xs)
            }
            .foregroundStyle(DS.Colors.onDarkText)
            .frame(maxWidth: .infinity, alignment: .leading)

            record
        }
    }

    private func chip(systemImage: String, text: String) -> some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.16), in: Capsule())
    }

    /// The record spins while the preview plays — like on the map, just bigger.
    private var record: some View {
        Button {
            onTogglePlayback()
        } label: {
            TimelineView(.animation(paused: !isPlaying)) { timeline in
                let angle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4) / 4 * 360
                VinylRecordView(artworkURL: artworkURL)
                    .rotationEffect(.degrees(isPlaying ? angle : 0))
            }
            .frame(width: 68, height: 68)
            .overlay(alignment: .bottomTrailing) {
                if hasPreview {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Colors.vinyl)
                        .frame(width: 24, height: 24)
                        .background(DS.Colors.marks, in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasPreview)
        .accessibilityLabel(isPlaying
            ? Text("candidates.pausePreview", comment: "Pause the preview")
            : Text("candidates.playPreview", comment: "Play the preview"))
    }

    private var dateText: String {
        candidate.cluster.interval.start.formatted(.dateTime.day().month(.wide).year())
    }
}

import SwiftUI

/// Candidate card: "14 August 2023, Barcelona — you listened to X" with a photo.
struct CandidateCardView: View {
    let candidate: MemoryCandidate
    let loader: MediaLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let track = candidate.selectedTrack {
                    Text(track.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if candidate.photos.count > 1 {
                    Label {
                        Text(String(localized: "candidates.photoCount",
                                     defaultValue: "\(candidate.photos.count) shots at this place"))
                    } icon: {
                        Image(systemName: "photo.stack")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var photo: some View {
        if let first = candidate.photos.first {
            MediaThumbnail(media: PlaceSnapshot.Media(id: candidate.id,
                                                      kind: first.kind,
                                                      localIdentifier: first.id,
                                                      hasEmbeddedData: false,
                                                      takenAt: first.creationDate),
                           loader: loader)
                .frame(height: 300)
                .clipped()
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 300)
        }
    }

    private var headline: String {
        let date = candidate.cluster.interval.start
            .formatted(.dateTime.day().month(.wide).year())
        guard let place = candidate.placeName, !place.isEmpty else { return date }
        return "\(date), \(place)"
    }
}

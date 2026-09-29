import SwiftUI

/// Player under the map: appears after a place's detail screen.
/// Plays the track preview; a tap opens the full-screen view again.
struct CompactPlaceCard: View {
    let place: PlaceSnapshot
    let player: PreviewAudioPlayer
    let onOpenDetail: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: place.artworkURL)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let artist = place.trackArtist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // The title may be truncated, the date never.
                HStack(spacing: 4) {
                    if let name = place.shortPlaceName {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if place.shortPlaceName != nil, place.eventDate != nil {
                        Text("·")
                    }
                    if let date = place.eventDate?.formatted() {
                        Text(date)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let previewURL = place.previewURL {
                Button {
                    Haptics.tap()
                    if isPlayingThis { player.stop() } else { player.play(previewURL) }
                } label: {
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, isActive: isPlayingThis)
                        .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlayingThis
                                    ? Text("card.pause", comment: "Pause")
                                    : Text("card.play", comment: "Play"))
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("card.close", comment: "Close the place card"))
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpenDetail)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("card.openHint", comment: "Hint: open the full place"))
    }

    private var isPlayingThis: Bool {
        player.isPlaying && player.currentURL == place.previewURL
    }

}

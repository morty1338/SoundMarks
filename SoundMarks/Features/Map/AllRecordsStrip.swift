import AudioToolbox
import SwiftUI

/// The "All" strip at the bottom of the map: records from the nearest, paged one by one.
/// Every step clicks and gives haptic feedback like an iOS picker wheel,
/// and the map immediately moves to the new record. The strip is translucent, the map below slightly blurred.
///
/// The strip only knows the order of identifiers; record snapshots are read page by page
/// when `LazyHStack` builds the visible cells and a couple of neighbors.
struct AllRecordsStrip: View {
    let ids: [UUID]
    let model: MapViewModel
    let defaultSkinID: String
    @Binding var centeredID: UUID?
    let onOpen: (UUID) -> Void

    private let itemWidth: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { position, id in
                        Group {
                            if let place = model.snapshot(at: position, in: ids) {
                                item(place)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: itemWidth)
                        .id(id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (proxy.size.width - itemWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredID, anchor: .center)
        }
        .frame(height: 140)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.55)
        }
        .sensoryFeedback(.selection, trigger: centeredID)
        .onChange(of: centeredID) { _, _ in
            // Picker wheel click. The system sound is silent in silent mode.
            AudioServicesPlaySystemSound(1104)
        }
    }

    private func item(_ place: PlaceSnapshot) -> some View {
        let isCentered = place.id == centeredID
        return VStack(spacing: 4) {
            VinylRecordView(artworkURL: place.artworkURL, skin: place.skin(default: defaultSkinID))
                .frame(width: 62, height: 62)
                .scaleEffect(isCentered ? 1.15 : 0.85)
                .opacity(isCentered ? 1 : 0.7)
            // The city may be truncated, the date never.
            VStack(spacing: 0) {
                Text(verbatim: place.city ?? place.placeName ?? "")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: place.compactDate ?? "")
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCentered ? .primary : .secondary)
        }
        .padding(.vertical, DS.Spacing.s)
        .animation(DS.Motion.quick, value: isCentered)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCentered {
                onOpen(place.id)
            } else {
                withAnimation(DS.Motion.standard) { centeredID = place.id }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: place.displayTitle))
        .accessibilityAddTraits(isCentered ? [.isButton, .isSelected] : .isButton)
    }
}

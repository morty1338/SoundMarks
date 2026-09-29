import SwiftUI

/// Record roulette: all places of the current planet in a horizontal row.
///
/// First tap on the center record — preview, second — detail screen.
/// Tap on a side one — scroll to it. After 5 seconds the center one slowly spins.
/// Records look the same as on the map; the skin is changed via "…" at the top right.
///
/// The order is computed from the lightweight place index, and the records themselves are read page by page:
/// `LazyHStack` builds only the visible and neighboring ones, and snapshots are taken just for them.
struct RouletteView: View {
    @Environment(AppEnvironment.self) private var environment

    let model: MapViewModel
    let player: PreviewAudioPlayer
    var defaultSkinID: String = SkinCatalog.standardID
    /// Changing a place's skin; `nil` — a friend's planet, view only.
    var onChangeSkin: ((UUID, String?) -> Void)?
    let onOpenDetail: (UUID) -> Void

    /// Rank unlocks skins — counted over all my places.
    @State private var rank = RankLadder.rank(forPlaceCount: 0)

    @State private var sort: RouletteSort = .date
    /// Record order — identifiers; recomputed when the sorting or the places change.
    @State private var order: [UUID] = []
    /// Group captions (country, year) by identifier — without snapshots.
    @State private var entries: [UUID: PlaceIndexEntry] = [:]
    @State private var centeredID: UUID?
    /// Since when the current record has been in the center. Spinning starts after 5 seconds.
    @State private var centeredSince = Date()

    /// Delay before spinning and the speed: one turn every 12 seconds.
    private static let spinDelay: TimeInterval = 5
    private static let degreesPerSecond: Double = 30

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = min(proxy.size.width * 0.62, 300)
            let sideInset = (proxy.size.width - itemWidth) / 2

            VStack(spacing: DS.Spacing.m) {
                header

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(order.enumerated()), id: \.element) { position, id in
                            Group {
                                if let place = model.snapshot(at: position, in: order) {
                                    item(for: place, width: itemWidth)
                                } else {
                                    Color.clear.frame(width: itemWidth)
                                }
                            }
                            .id(id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, sideInset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centeredID, anchor: .center)
                .frame(maxHeight: .infinity)
            }
            .padding(.top, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xl)
        }
        .preferredColorScheme(.dark)
        .task {
            let count = (try? environment.persistence.viewContext.count(for: Place.fetchRequest(scope: .mine))) ?? 0
            rank = RankLadder.rank(forPlaceCount: count)
        }
        .onAppear {
            rebuildOrder()
            if centeredID == nil { centeredID = order.first }
            centeredSince = Date()
        }
        .onChange(of: sort) { _, _ in
            rebuildOrder()
            withAnimation(DS.Motion.standard) { centeredID = order.first }
        }
        .onChange(of: model.revision) { _, _ in rebuildOrder() }
        .onChange(of: centeredID) { _, _ in centeredSince = Date() }
        .onDisappear { player.stop() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Menu {
                Picker(selection: $sort) {
                    ForEach(RouletteSort.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                } label: {
                    Text("roulette.filters", comment: "Filters")
                }
            } label: {
                Label {
                    Text("roulette.filters", comment: "Filters")
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Colors.onDarkText)
                .padding(.horizontal, DS.Spacing.m)
                .frame(minHeight: DS.Size.tapTarget)
                .contentShape(Capsule())
            }
            .liquidGlass(in: Capsule())

            Spacer()

            if let group = currentGroup {
                Text(group)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Colors.onDarkSecondary)
                    .transition(.opacity)
                    .id(group)
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .animation(DS.Motion.quick, value: currentGroup)
    }

    private var currentGroup: String? {
        guard let centeredID, let entry = entries[centeredID] else { return nil }
        return RouletteOrdering.group(of: entry, by: sort)
    }

    /// Order from the lightweight index: sorting a thousand entries takes a fraction of a millisecond,
    /// and it is no longer repeated on every scroll frame.
    private func rebuildOrder() {
        let index = model.index
        order = RouletteOrdering.ordered(index, by: sort).map(\.id)
        entries = Dictionary(index.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Record

    private func item(for place: PlaceSnapshot, width: CGFloat) -> some View {
        let isCentered = place.id == centeredID

        return VStack(spacing: DS.Spacing.s) {
            // "City · dd.mm.yyyy": the city is truncated, the date never.
            HStack(spacing: 4) {
                if let city = place.city ?? place.placeName {
                    Text(city).lineLimit(1).truncationMode(.tail)
                }
                if let date = place.compactDate {
                    Text("·")
                    Text(date).lineLimit(1).fixedSize()
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(DS.Colors.onDarkSecondary)

            spinningRecord(place, isCentered: isCentered)
                .frame(width: width * 0.88, height: width * 0.88)
                .overlay(alignment: .topTrailing) {
                    if isCentered, onChangeSkin != nil {
                        skinMenu(for: place)
                    }
                }

            Text(place.displayTitle)
                .font(.caption)
                .foregroundStyle(DS.Colors.onDarkText.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DS.Spacing.s)
        .frame(width: width)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.72)
                .opacity(phase.isIdentity ? 1 : 0.75)
                .brightness(phase.isIdentity ? 0 : -0.06)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap(on: place, isCentered: isCentered) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText(for: place)))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func spinningRecord(_ place: PlaceSnapshot, isCentered: Bool) -> some View {
        if isCentered {
            TimelineView(.animation) { timeline in
                VinylRecordView(artworkURL: place.artworkURL, skin: place.skin(default: defaultSkinID))
                    .rotationEffect(.degrees(Self.spinAngle(since: centeredSince, now: timeline.date)))
            }
        } else {
            VinylRecordView(artworkURL: place.artworkURL, skin: place.skin(default: defaultSkinID))
        }
    }

    /// "…" at the top right of the record: choosing a skin from the unlocked ones.
    private func skinMenu(for place: PlaceSnapshot) -> some View {
        Menu {
            Button {
                onChangeSkin?(place.id, nil)
            } label: {
                if place.skinID == nil {
                    Label(String(localized: "roulette.skin.default", defaultValue: "Same as the rest"),
                          systemImage: "checkmark")
                } else {
                    Text("roulette.skin.default", comment: "Default skin")
                }
            }
            Divider()
            ForEach(SkinCatalog.unlocked(at: environment.settings.skinUnlockLevel(for: rank))) { skin in
                Button {
                    Haptics.select()
                    onChangeSkin?(place.id, skin.id)
                } label: {
                    if place.skinID == skin.id {
                        Label(skin.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: skin.name)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.Colors.onDarkText)
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                .contentShape(Circle())
        }
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text("roulette.skin", comment: "Change record look"))
    }

    /// Rotation angle: 0 for the first 5 seconds, then a smooth ramp-up to one turn per 12 seconds.
    static func spinAngle(since start: Date, now: Date) -> Double {
        let elapsed = now.timeIntervalSince(start) - spinDelay
        guard elapsed > 0 else { return 0 }
        // The first second — quadratic ramp-up, then uniform.
        let accelerated = elapsed < 1 ? elapsed * elapsed / 2 : elapsed - 0.5
        return accelerated * degreesPerSecond
    }

    private func handleTap(on place: PlaceSnapshot, isCentered: Bool) {
        guard isCentered else {
            Haptics.select()
            withAnimation(DS.Motion.standard) { centeredID = place.id }
            return
        }

        let isPlayingThis = player.isPlaying && player.currentURL == place.previewURL
        if let preview = place.previewURL, !isPlayingThis {
            Haptics.tap()
            player.play(preview)
        } else {
            player.stop()
            onOpenDetail(place.id)
        }
    }

    private func caption(for place: PlaceSnapshot) -> String {
        [place.city ?? place.placeName, place.compactDate]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func accessibilityText(for place: PlaceSnapshot) -> String {
        [place.displayTitle, place.trackArtist, caption(for: place)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

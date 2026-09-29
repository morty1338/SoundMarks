import CoreLocation
import SwiftUI

/// Home screen slot while paging.
enum HomeSlot: Hashable {
    /// Paired planet — to the left of mine.
    case shared(UUID)
    /// My planet — "My Marks".
    case own(UUID)
    /// A friend's planet as its own page — when there is only one friend on the screen.
    case friend(UUID)
    /// "Friends Marks" grid page — on the right, 6 friends per page.
    case friends(Int)

    var planet: PlanetPage? {
        switch self {
        case .shared(let id): .shared(id)
        case .own(let id): .own(id)
        case .friend(let id): .friend(id)
        case .friends: nil
        }
    }
}

/// A friend's planet opened from the grid.
struct FriendFocus: Equatable {
    var stack: FriendStack
    var index: Int
    /// Where the mini planet was — the big one "grows" from there.
    var origin: CGRect

    var current: PlanetInfo {
        stack.planets[min(max(index, 0), stack.planets.count - 1)]
    }
}

/// Home screen — a carousel of planets.
///
/// On the left — paired planets, in the center — mine, on the right — "Friends Marks" pages.
/// Neighboring planets are real and peek in slightly at the edges; while paging
/// they follow the finger and settle in the center. Paging is a swipe outside the planet disc
/// (on the planet itself the finger spins it) or a tap on a neighbor.
/// Long press on a planet — edit mode: the planet "lifts", it can be
/// dragged onto a neighbor's spot, renamed or deleted.
struct HomeScreen: View {
    let directory: PlanetDirectory
    @Binding var slot: HomeSlot
    @Binding var focus: FriendFocus?
    /// The splash is over — Earth fades in from the dark.
    let isRevealed: Bool
    let isDay: Bool
    /// Lights, flags or pushpins.
    let markerStyle: PlanetMarkerStyle
    @Binding var command: GlobeCommand?
    /// Transition from a zooming-out map: the globe looks at its center and pulls back with the gesture.
    let zoom: ZoomOutState
    let isMapStage: Bool

    let onEnterMap: (CLLocationCoordinate2D) -> Void
    let onOpenSettings: () -> Void
    let onOpenFriends: () -> Void
    let onOpenProfile: () -> Void
    let onOpenRoulette: () -> Void
    let onAddPlanet: () -> Void
    let onRename: (PlanetPage, String) -> Void
    let onDelete: (PlanetPage) -> Void
    /// Tap on the block with the friend's name — their profile.
    let onOpenFriend: (UUID) -> Void
    let onRemoveStack: (UUID) -> Void

    /// Carousel offset by the finger.
    @State private var dragOffset: CGFloat = 0
    @State private var isSnapping = false
    /// Edit mode: the planet is lifted and wobbles together with its name.
    @State private var isEditing = false
    /// Offset of the lifted planet by the finger.
    @State private var liftOffset: CGSize = .zero
    /// The finger is held at the screen edge — the planet jumps over to the neighbor.
    @State private var edgeDwell: Task<Void, Never>?
    @State private var dwellEdge = 0
    /// Renaming: an input field and a green checkmark instead of the caption.
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isRenameFocused: Bool
    /// The mini planet of the new current one is still visible over the big one while it finishes drawing.
    @State private var currentMiniOpacity: Double = 0.001
    /// Edit mode of the friends grid.
    @State private var isEditingGrid = false
    /// 0 — the friend's planet is still the size of a grid cell, 1 — full screen.
    @State private var focusProgress: CGFloat = 1
    @State private var focusSlide: CGFloat = 0
    @State private var focusOpacity: Double = 1

    static let stacksPerPage = 6

    var body: some View {
        ZStack {
            GeometryReader { full in
                stage(size: full.size)
            }
            .ignoresSafeArea()

            // From the dark: the splash ends in black, Earth fades in.
            Color.black
                .ignoresSafeArea()
                .opacity(isRevealed ? 0 : 1)
                .allowsHitTesting(false)

            controls
                .opacity(isRevealed ? 1 : 0)
        }
        // The keyboard during renaming must not move the scene.
        .ignoresSafeArea(.keyboard)
        .animation(.easeOut(duration: 1.0), value: isRevealed)
        .preferredColorScheme(.dark)
    }

    // MARK: - Slots

    private var stacks: [FriendStack] { directory.friendStacks }

    private var friendPageCount: Int {
        stacks.isEmpty ? 0 : (stacks.count + Self.stacksPerPage - 1) / Self.stacksPerPage
    }

    /// Only one friend on screen — their planets are regular pages, without the grid:
    /// the same screen as after tapping a planet in the grid.
    private var slots: [HomeSlot] {
        let friends: [HomeSlot] = stacks.count == 1
            ? stacks[0].planets.map { HomeSlot.friend($0.page.mapID) }
            : (0..<friendPageCount).map { HomeSlot.friends($0) }
        return directory.sharedPlanets.map { HomeSlot.shared($0.page.mapID) }
            + directory.ownPlanets.map { HomeSlot.own($0.page.mapID) }
            + friends
    }

    private var currentIndex: Int {
        slots.firstIndex(of: slot) ?? slots.firstIndex(of: .own(directory.mainPlanetID)) ?? 0
    }

    /// Planet on the big globe.
    private var displayedPlanet: PlanetPage? {
        focus?.current.page ?? slot.planet
    }

    /// The planet's dots come from the registry right away — without waiting for places to reload.
    private var displayedDots: [SphereMapping.Coordinate] {
        if let focus { return focus.current.dots }
        guard let planet = slot.planet else { return [] }
        return directory.info(for: planet)?.dots ?? []
    }

    /// Pages around the current one: planets — two on each side, grids — one.
    /// They are already drawn when they slide into view and aren't recreated when the current one changes.
    private var pageSlots: [HomeSlot] {
        (currentIndex - 2...currentIndex + 2)
            .filter { slots.indices.contains($0) }
            .filter { index in
                if case .friends = slots[index] { return abs(index - currentIndex) <= 1 }
                return true
            }
            .map { slots[$0] }
    }

    // MARK: - Scene

    @ViewBuilder
    private func stage(size: CGSize) -> some View {
        let disc = size.width * GlobeScene.discWidthFraction
        let offset = GlobeScene.discCenterOffset(forWidth: size.width)
        let discCenter = CGPoint(x: size.width / 2, y: size.height / 2 + offset)
        let nameY = discCenter.y - disc / 2 - 44

        ZStack {
            StarryBackground()

            ForEach(pageSlots, id: \.self) { item in
                let index = slots.firstIndex(of: item) ?? currentIndex
                page(item, index: index, size: size, disc: disc, discCenter: discCenter, nameY: nameY)
            }

            // The big planet always exists — on the grid page it is simply transparent.
            // Recreating SceneKit on every return — that was the hitch.
            GlobeView(places: displayedDots, page: displayedPlanet, isDay: isDay,
                      markerStyle: markerStyle, tracking: zoom.tracking(isMapStage: isMapStage), isInteractive: !isEditing && displayedPlanet != nil,
                      onLongPress: startEditing, command: $command) { coordinate in
                onEnterMap(CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                  longitude: coordinate.longitude))
            }
            .modifier(GrowFromCell(focus: focus, progress: focusProgress, disc: disc,
                                   discCenter: discCenter, size: size))
            .modifier(Lifted(isLifted: isEditing, anchor: UnitPoint(x: 0.5, y: discCenter.y / size.height)))
            .offset(x: dragOffset + liftOffset.width + focusSlide, y: liftOffset.height)
            .opacity(displayedPlanet == nil ? 0 : focusOpacity)
            .scaleEffect(isRevealed ? 1 : 0.94)
            .allowsHitTesting(displayedPlanet != nil)
            .zIndex(1)
            .accessibilityHidden(displayedPlanet == nil)
            .accessibilityLabel(Text("planet.globe.accessibility", comment: "Planet: tap a dot"))

            // A friend's planet opened from the grid: the same block as on the friend's page.
            if let friend = focus?.stack {
                Button {
                    Haptics.tap()
                    onOpenFriend(friend.ownerID)
                } label: {
                    FriendInfoBlock(stack: friend)
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: size.width / 2 + focusSlide, y: nameY - 92)
                .opacity(focusOpacity * Double(focusProgress))
                .zIndex(4)
            }

            if displayedPlanet != nil {
                currentName(width: size.width)
                    .position(x: size.width / 2 + dragOffset + liftOffset.width * 0.5 + focusSlide,
                              y: nameY + liftOffset.height * 0.5)
                    .opacity(focusOpacity)
                    .zIndex(4)
            }

            // Swipe zone above the big planet: otherwise the full-screen globe view
            // takes all touches for itself and paging does not work.
            if displayedPlanet != nil, !isEditing {
                swipeArea(size: size, disc: disc, offset: offset)
                    .zIndex(1.5)
            }

            if isEditing {
                editOverlay(size: size, disc: disc, discCenter: discCenter)
                    .zIndex(3)
            }
        }
        .animation(.smooth(duration: 0.4), value: slots)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isEditing)
        .coordinateSpace(name: HomeSpace.name)
    }

    /// Carousel page: a planet with its name above it, or the friends grid.
    @ViewBuilder
    private func page(_ item: HomeSlot, index: Int, size: CGSize, disc: CGFloat,
                      discCenter: CGPoint, nameY: CGFloat) -> some View {
        let isCurrent = index == currentIndex
        let x = size.width * CGFloat(index - currentIndex) + dragOffset
        switch item {
        case .friends(let page):
            FriendsGridPage(stacks: stacksOnPage(page), pageOffset: page * Self.stacksPerPage,
                            size: size, fullDiameter: disc,
                            discCenter: discCenter, top: nameY - 10, isDay: isDay,
                            isEditing: isEditingGrid && isCurrent,
                            focusedStack: focus?.stack.ownerID,
                            onSelect: openFocus,
                            onStartEditing: {
                                Haptics.select()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { isEditingGrid = true }
                            },
                            onEndEditing: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { isEditingGrid = false }
                            },
                            onMove: { ownerID, index in
                                Haptics.select()
                                withAnimation(.smooth(duration: 0.3)) {
                                    directory.moveStack(ownerID: ownerID, to: index)
                                }
                            },
                            onRemove: onRemoveStack,
                            onEdgeDwell: { ownerID, direction in
                                moveStackAcrossPages(ownerID, direction: direction, width: size.width)
                            })
                .offset(x: x)
                .opacity(focus == nil ? 1 : 0)
                .allowsHitTesting(isCurrent && focus == nil)
                .simultaneousGesture(pagingGesture(width: size.width),
                                     including: isEditingGrid || !isCurrent ? .subviews : .all)
                .zIndex(isCurrent ? 1.2 : 0)

        default:
            let side = (disc / GlobeScene.miniDiscFraction).rounded()
            // In edit mode the neighbors that can be swapped with peek in at the sides.
            let editX = CGFloat(index - currentIndex) * (size.width / 2 + disc / 2 - 34)
            let planetX = isEditing && !isCurrent ? editX : x
            let isVisibleInEdit = isCurrent || (abs(index - currentIndex) == 1 && canSwap(item))
            MiniGlobeView(dots: item.planet.flatMap { directory.info(for: $0)?.dots } ?? [],
                          isDay: isDay, markerStyle: markerStyle, rotates: false)
                .frame(width: side, height: side)
                .modifier(Lifted(isLifted: isCurrent && isEditing,
                                 anchor: .center))
                .position(x: size.width / 2 + planetX + (isCurrent ? liftOffset.width : 0),
                          y: discCenter.y + (isCurrent ? liftOffset.height : 0))
                .opacity(focus != nil ? 0
                         : isCurrent ? currentMiniOpacity
                         : (isEditing && !isVisibleInEdit ? 0 : 1))
                .allowsHitTesting(false)
                .zIndex(isCurrent ? 2 : 0)
                .accessibilityHidden(true)

            if !isCurrent {
                PlanetNameLabel(text: planetName(for: item))
                    .frame(width: size.width - 120)
                    .position(x: size.width / 2 + x, y: nameY)
                    .opacity(focus == nil && !isEditing ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(0)
            }

            // Whose planet it is — attached to its page and slides away with it.
            if case .friend = item, let friend = friendStack(for: item) {
                Button {
                    Haptics.tap()
                    onOpenFriend(friend.ownerID)
                } label: {
                    FriendInfoBlock(stack: friend)
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: size.width / 2 + x, y: nameY - 92)
                .opacity(focus == nil && !isEditing ? 1 : 0)
                .allowsHitTesting(isCurrent && focus == nil && !isEditing)
                .zIndex(4)
                .accessibilityHint(Text("friend.open.hint", comment: "Open the friend's profile"))
            }
        }
    }

    private func friendStack(for slot: HomeSlot) -> FriendStack? {
        guard case .friend(let id) = slot else { return nil }
        return stacks.first { $0.planets.contains { $0.page.mapID == id } }
    }

    /// Who a lifted planet can swap places with: own with own, paired with paired.
    private func canSwap(_ other: HomeSlot) -> Bool {
        switch (slot, other) {
        case (.own, .own), (.shared, .shared): true
        default: false
        }
    }

    private func stacksOnPage(_ page: Int) -> [FriendStack] {
        Array(stacks.dropFirst(page * Self.stacksPerPage).prefix(Self.stacksPerPage))
    }

    // MARK: - Titles

    /// Planet name above it.
    private func planetName(for slot: HomeSlot) -> String {
        guard let planet = slot.planet, let info = directory.info(for: planet) else { return "" }
        if case .shared = planet {
            // The "[nick] and your Marks" caption is already in the header — above the planet goes its own name.
            return info.title == String(localized: "planet.pairedCaption",
                                        defaultValue: "\(info.nickname ?? "") with your Marks")
                ? String(localized: "planet.pairedName", defaultValue: "Paired planet")
                : info.title
        }
        return info.title
    }

    /// Name of the current planet: in edit mode it is highlighted and wobbles with it,
    /// a long press on it renames it right in place.
    @ViewBuilder
    private func currentName(width: CGFloat) -> some View {
        let title = focus?.current.title ?? planetName(for: slot)
        if isRenaming {
            HStack(spacing: DS.Spacing.s) {
                TextField(text: $renameText) {
                    Text("planet.rename.placeholder", comment: "Planet caption")
                }
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Colors.onDarkText)
                .focused($isRenameFocused)
                .submitLabel(.done)
                .onSubmit(commitRename)
                .padding(.horizontal, DS.Spacing.m)
                .frame(height: 48)
                .background(Color.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Colors.marks, lineWidth: 2))

                ConfirmButton(action: commitRename)
                    .transition(.scale.combined(with: .opacity))
            }
            .frame(width: width - 48)
        } else {
            PlanetNameLabel(text: title, isHighlighted: isEditing)
                .modifier(Lifted(isLifted: isEditing, anchor: .center))
                .frame(width: width - 120)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) { startRenaming(from: title) }
        }
    }

    private var headerText: String {
        if focus != nil { return "Friends Marks" }
        switch slot {
        case .own: return "My Marks"
        case .friends, .friend: return "Friends Marks"
        case .shared(let id):
            let nickname = directory.info(for: .shared(id))?.nickname ?? ""
            return String(localized: "planet.pairedCaption", defaultValue: "\(nickname) with your Marks")
        }
    }

    // MARK: - Paging

    /// Everything outside the planet disc catches the swipe; the disc itself stays with the globe.
    private func swipeArea(size: CGSize, disc: CGFloat, offset: CGFloat) -> some View {
        Color.clear
            .contentShape(DiscCutout(diameter: disc + 16, centerOffset: offset), eoFill: true)
            .gesture(pagingGesture(width: size.width))
            .accessibilityHidden(true)
    }

    private func pagingGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isSnapping, abs(value.translation.width) > abs(value.translation.height) * 0.7 else { return }
                if focus != nil {
                    focusSlide = value.translation.width * 0.3
                    return
                }
                dragOffset = rubberBanded(value.translation.width)
            }
            .onEnded { value in
                guard !isSnapping else { return }
                let velocity = value.velocity.width
                let projected = value.translation.width + velocity * 0.2
                let direction = projected < -width * 0.3 ? 1 : (projected > width * 0.3 ? -1 : 0)
                if focus != nil {
                    moveInStack(by: direction, width: width)
                } else {
                    snap(by: direction, width: width, velocity: velocity)
                }
            }
    }

    /// Past the last planet — elastic resistance, like iOS lists.
    private func rubberBanded(_ translation: CGFloat) -> CGFloat {
        let atStart = currentIndex == 0 && translation > 0
        let atEnd = currentIndex == slots.count - 1 && translation < 0
        guard atStart || atEnd else { return translation }
        let limit: CGFloat = 120
        return limit * (1 - 1 / (abs(translation) / limit * 0.55 + 1)) * (translation > 0 ? 1 : -1)
    }

    /// The carousel moves on to the neighboring page, and it becomes current.
    /// The spring starts at the finger's velocity — no jolt at the moment of release.
    private func snap(by direction: Int, width: CGFloat, velocity: CGFloat = 0) {
        let target = currentIndex + direction
        guard direction != 0, slots.indices.contains(target), !isSnapping else {
            withAnimation(springAnimation(from: dragOffset, to: 0, velocity: velocity)) { dragOffset = 0 }
            return
        }
        isSnapping = true
        Haptics.select()
        let destination = -CGFloat(direction) * width
        withAnimation(springAnimation(from: dragOffset, to: destination, velocity: velocity)) {
            dragOffset = destination
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                slot = slots[target]
                dragOffset = 0
                // The big planet redraws within a frame or two — until then its mini copy is visible.
                currentMiniOpacity = 1
            }
            isSnapping = false
            withAnimation(.easeOut(duration: 0.16).delay(0.08)) { currentMiniOpacity = 0.001 }
        }
    }

    /// A critically damped spring continuing the finger's motion.
    private func springAnimation(from start: CGFloat, to end: CGFloat, velocity: CGFloat) -> Animation {
        let distance = end - start
        let relative = abs(distance) > 1 ? velocity / distance : 0
        return .interpolatingSpring(duration: 0.42, bounce: 0, initialVelocity: min(max(relative, 0), 12))
    }

    // MARK: - Edit mode

    private func startEditing() {
        guard slot.planet != nil || focus != nil else { return }
        Haptics.select()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { isEditing = true }
    }

    private func finishEditing() {
        edgeDwell?.cancel()
        dwellEdge = 0
        isRenameFocused = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            isEditing = false
            isRenaming = false
            liftOffset = .zero
        }
    }

    private func startRenaming(from title: String) {
        // Only a lifted planet can be renamed — not a spinning or just opened one.
        guard isEditing else { return }
        Haptics.select()
        renameText = title
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditing = true
            isRenaming = true
        }
        isRenameFocused = true
    }

    /// Green checkmark: save and return to the planet's page.
    private func commitRename() {
        guard let planet = displayedPlanet else { return }
        let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onRename(planet, text) }
        Haptics.success()
        finishEditing()
    }

    /// A lifted planet follows the finger across the whole screen and returns when released.
    /// Hold it at the edge — it swaps places with the neighbor: the neighbor flies to the other side.
    @ViewBuilder
    private func editOverlay(size: CGSize, disc: CGFloat, discCenter: CGPoint) -> some View {
        // A tap outside the planet — leave edit mode.
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: finishEditing)

        if !isRenaming {
            Circle()
                .fill(Color.clear)
                .contentShape(Circle())
                .frame(width: disc, height: disc)
                .position(x: discCenter.x + liftOffset.width, y: discCenter.y + liftOffset.height)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named(HomeSpace.name))
                        .onChanged { value in
                            liftOffset = value.translation
                            let edge = value.location.x < 40 ? -1 : (value.location.x > size.width - 40 ? 1 : 0)
                            guard edge != dwellEdge else { return }
                            dwellEdge = edge
                            edgeDwell?.cancel()
                            guard edge != 0 else { return }
                            edgeDwell = Task { await dwell(edge: edge) }
                        }
                        .onEnded { _ in
                            edgeDwell?.cancel()
                            dwellEdge = 0
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { liftOffset = .zero }
                        }
                )
        }
    }

    /// While the finger is at the edge — the planet swaps places with neighbors step by step.
    /// Own ones swap with own ones, paired with paired.
    private func dwell(edge: Int) async {
        var warned = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, dwellEdge == edge, let planet = slot.planet else { return }
            var moved = false
            withAnimation(.smooth(duration: 0.45)) { moved = directory.move(planet, by: edge) }
            if moved {
                Haptics.select()
            } else if !warned {
                warned = true
                Haptics.warning()
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// A friend's stack held at the grid edge — it moves to the neighboring page.
    private func moveStackAcrossPages(_ ownerID: UUID, direction: Int, width: CGFloat) {
        guard case .friends(let page) = slot else { return }
        let target = page + direction
        guard target >= 0, target < friendPageCount else {
            Haptics.warning()
            return
        }
        let index = direction > 0
            ? target * Self.stacksPerPage
            : min(target * Self.stacksPerPage + Self.stacksPerPage - 1, stacks.count - 1)
        withAnimation(.smooth(duration: 0.3)) { directory.moveStack(ownerID: ownerID, to: index) }
        snap(by: direction, width: width)
    }

    // MARK: - Friend's planet

    private func openFocus(_ stack: FriendStack, origin: CGRect, isFullSize: Bool) {
        guard !stack.planets.isEmpty else { return }
        Haptics.select()
        focus = FriendFocus(stack: stack, index: 0, origin: origin)

        // The only friend on the page and their planet is already full screen — straight to the map.
        if isFullSize, stack.planets.count == 1 {
            focusProgress = 1
            let home = PlanetDots.home(for: stack.planets[0].dots)
            onEnterMap(CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude))
            return
        }

        focusProgress = 0
        command = .spinToHome
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { focusProgress = 1 }
    }

    private func closeFocus() {
        Haptics.select()
        finishEditing()
        withAnimation(.easeInOut(duration: 0.32)) {
            focusProgress = 0
        } completion: {
            focus = nil
            focusProgress = 1
        }
    }

    /// One friend's planets are paged in place.
    private func moveInStack(by direction: Int, width: CGFloat) {
        guard let focus, direction != 0, focus.stack.planets.indices.contains(focus.index + direction) else {
            withAnimation(.smooth(duration: 0.25)) { focusSlide = 0 }
            return
        }
        Haptics.select()
        let distance = width * 0.5 * CGFloat(direction)
        withAnimation(.easeIn(duration: 0.14)) {
            focusSlide = -distance
            focusOpacity = 0
        } completion: {
            self.focus?.index += direction
            command = .spinToHome
            focusSlide = distance
            withAnimation(.smooth(duration: 0.3)) {
                focusSlide = 0
                focusOpacity = 1
            }
        }
    }

    // MARK: - Buttons

    private var isAnyEditing: Bool { isEditing || isEditingGrid }

    private var controls: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The section title — top center, level with settings.
                MarksTitle(text: headerText, size: 28)
                    .frame(maxWidth: 230)
                    .frame(height: DS.Size.tapTarget)
                    .id(headerText)
                    .transition(.opacity)

                HStack(alignment: .top) {
                    if focus != nil {
                        GlassIconButton(systemImage: "chevron.backward", accessibilityKey: "map.back",
                                        action: closeFocus)
                    } else if !isAnyEditing {
                        GlassIconButton(systemImage: "person.crop.circle", accessibilityKey: "planet.profile",
                                        action: onOpenProfile)
                    }
                    Spacer()
                    if !isAnyEditing {
                        VStack(spacing: DS.Spacing.m) {
                            GlassIconButton(systemImage: "gearshape", accessibilityKey: "map.settings",
                                            action: onOpenSettings)
                            if focus == nil {
                                FriendsButton(action: onOpenFriends)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.s)
            .animation(.smooth(duration: 0.25), value: headerText)

            Spacer()

            ZStack {
                if !isAnyEditing {
                    RecordCountButton(count: recordCount, action: onOpenRoulette)
                    if focus == nil {
                        HStack {
                            Spacer()
                            GlassTextButton(title: "Add Planet", action: onAddPlanet)
                                .accessibilityLabel(Text("planet.add", comment: "Add planet"))
                        }
                    }
                } else if isEditing, !isRenaming, let planet = displayedPlanet, focus == nil,
                          directory.canDelete(planet) {
                    HStack {
                        Spacer()
                        TrashButton {
                            onDelete(planet)
                            finishEditing()
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minHeight: DS.Size.tapTarget + 8)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
        }
        .animation(.smooth(duration: 0.25), value: focus != nil)
        .animation(.smooth(duration: 0.25), value: isAnyEditing)
    }

    /// The counter comes from the planet registry, without waiting for places to reload.
    private var recordCount: Int {
        if let focus { return focus.current.placeCount }
        guard let planet = slot.planet else { return directory.friendsPlaceCount }
        return directory.info(for: planet)?.placeCount ?? 0
    }
}

/// Whose planet it is: avatar and framed name — together exactly in the screen center,
/// below them the rank statuette and its name in a special font.
struct FriendInfoBlock: View {
    let stack: FriendStack

    var body: some View {
        let rank = RankLadder.rank(forPlaceCount: stack.placeCount)
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(nickname: stack.nickname, colorHex: stack.avatarColorHex,
                           imageData: stack.avatarData, size: 36)
                    .overlay(Circle().strokeBorder(DS.Colors.marks.opacity(0.8), lineWidth: 1.5))
                NameFrame(text: stack.nickname)
            }
            .fixedSize()

            RankLine(rank: rank)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Framed name in the app style: glass and a green edge.
struct NameFrame: View {
    let text: String
    var size: CGFloat = 20

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(DS.Colors.onDarkText)
            .lineLimit(1)
            .padding(.horizontal, size * 0.7)
            .padding(.vertical, size * 0.3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [DS.Colors.marks, DS.Colors.marksShade.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5))
    }
}

/// Rank statuette and its name — small caps with a metallic sheen.
struct RankLine: View {
    let rank: Rank
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            RankStatuette(level: rank.level, size: size)
            Text(verbatim: rank.title)
                .font(.system(size: size * 0.52, weight: .black, design: .serif).smallCaps())
                .tracking(1.5)
                .foregroundStyle(RankStatuette.metal(for: rank.level))
        }
    }
}

/// Planet name above it: an elegant serif with a raised sheen.
struct PlanetNameLabel: View {
    let text: String
    var isHighlighted = false

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 30, weight: .semibold, design: .serif).italic())
            .foregroundStyle(LinearGradient(colors: [.white, DS.Colors.marks],
                                            startPoint: .top, endPoint: .bottom))
            .overlay {
                Text(verbatim: text)
                    .font(.system(size: 30, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.6), .clear],
                                                    startPoint: .top, endPoint: .center))
                    .blendMode(.screen)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, isHighlighted ? DS.Spacing.m : 0)
            .padding(.vertical, isHighlighted ? 6 : 0)
            .background {
                if isHighlighted {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .overlay(Capsule().strokeBorder(DS.Colors.marks.opacity(0.8), lineWidth: 1.5))
                }
            }
            .scaleEffect(isHighlighted ? 1.06 : 1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A raised green checkmark — save the new name.
private struct ConfirmButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.92, blue: 0.45),
                                                      Color(red: 0.18, green: 0.62, blue: 0.25)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                        .overlay(alignment: .top) {
                            // Highlight on top — the button looks convex.
                            Ellipse()
                                .fill(.white.opacity(0.35))
                                .frame(width: 28, height: 12)
                                .offset(y: 5)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("planet.rename.save", comment: "Save"))
    }
}

/// Red trash can — delete the planet.
private struct TrashButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.warning()
            action()
        } label: {
            Image(systemName: "trash.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.38, blue: 0.36),
                                                      Color(red: 0.78, green: 0.1, blue: 0.14)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("planet.delete", comment: "Delete planet"))
    }
}

/// Scene coordinate space: mini planet frames are measured in it.
enum HomeSpace {
    static let name = "home"
}

/// The big planet "grows" out of a grid cell.
/// The modifiers are always present, only the values change — the SceneKit view isn't recreated.
private struct GrowFromCell: ViewModifier {
    let focus: FriendFocus?
    let progress: CGFloat
    let disc: CGFloat
    let discCenter: CGPoint
    let size: CGSize

    func body(content: Content) -> some View {
        let origin = focus?.origin
        let start = origin.map { max($0.width / max(disc, 1), 0.05) } ?? 1
        let scale = start + (1 - start) * progress
        content
            .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: discCenter.y / max(size.height, 1)))
            .offset(x: origin.map { ($0.midX - discCenter.x) * (1 - progress) } ?? 0,
                    y: origin.map { ($0.midY - discCenter.y) * (1 - progress) } ?? 0)
    }
}

/// A planet lifted in edit mode: slightly larger and wobbling, like an icon on the Home Screen.
/// The modifiers are always present, only the values change — the SceneKit view isn't recreated.
private struct Lifted: ViewModifier {
    let isLifted: Bool
    let anchor: UnitPoint

    @State private var tilt = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isLifted ? 1.06 : 1, anchor: anchor)
            .rotationEffect(.degrees(isLifted ? (tilt ? 1.4 : -1.4) : 0), anchor: anchor)
            .onChange(of: isLifted, initial: true) { _, lifted in
                guard lifted else { return }
                withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { tilt.toggle() }
            }
    }
}

/// Cell wobble in grid edit mode.
private struct Wobble: ViewModifier {
    let isOn: Bool
    let seed: Double

    @State private var tilt = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isOn ? (tilt ? 2 : -2) : 0))
            .onChange(of: isOn, initial: true) { _, on in
                guard on else { return }
                withAnimation(.easeInOut(duration: 0.13 + seed.truncatingRemainder(dividingBy: 3) * 0.01)
                    .repeatForever(autoreverses: true)) { tilt.toggle() }
            }
    }
}

// MARK: - "Friends Marks" grid

/// Grid page: up to 3 planets per row, up to 6 per page.
/// The more friends — the smaller the planets; one friend — a planet like on the home screen.
/// Long press — editing: stacks are dragged onto each other's places and removed from the screen.
struct FriendsGridPage: View {
    let stacks: [FriendStack]
    /// Index of the page's first stack among all stacks.
    let pageOffset: Int
    let size: CGSize
    let fullDiameter: CGFloat
    let discCenter: CGPoint
    /// Top of the grid area — below the title.
    let top: CGFloat
    let isDay: Bool
    let isEditing: Bool
    let focusedStack: UUID?
    let onSelect: (FriendStack, CGRect, Bool) -> Void
    let onStartEditing: () -> Void
    /// A tap outside the planets — leave edit mode.
    let onEndEditing: () -> Void
    let onMove: (UUID, Int) -> Void
    let onRemove: (UUID) -> Void
    /// A stack held at the edge — move it to the neighboring page.
    let onEdgeDwell: (UUID, Int) -> Void

    private let labelHeight: CGFloat = 28

    /// The dragged stack and where it was picked up.
    @State private var dragged: UUID?
    @State private var dragStart: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var dwellEdge = 0
    @State private var dwellTask: Task<Void, Never>?

    var body: some View {
        let layout = cells
        ZStack {
            // The background catches swipes between pages; in edit mode a tap on it leaves editing.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { if isEditing { onEndEditing() } }

            ForEach(Array(layout.enumerated()), id: \.element.stack.id) { index, cell in
                let isDragged = dragged == cell.stack.ownerID
                FriendPlanetCell(stack: cell.stack, diameter: cell.diameter, isDay: isDay,
                                 isHidden: focusedStack == cell.stack.ownerID)
                    .modifier(Wobble(isOn: isEditing && !isDragged, seed: Double(index)))
                    .overlay(alignment: .topLeading) {
                        if isEditing {
                            removeBadge(for: cell.stack)
                                .offset(y: labelHeight)
                        }
                    }
                    .scaleEffect(isDragged ? 1.1 : 1)
                    .position(isDragged
                              ? CGPoint(x: dragStart.x + dragTranslation.width,
                                        y: dragStart.y + dragTranslation.height - labelHeight / 2)
                              : CGPoint(x: cell.center.x, y: cell.center.y - labelHeight / 2))
                    .zIndex(isDragged ? 1 : 0)
                    .onTapGesture {
                        guard !isEditing else { return }
                        let frame = CGRect(x: cell.center.x - cell.diameter / 2,
                                           y: cell.center.y - cell.diameter / 2,
                                           width: cell.diameter, height: cell.diameter)
                        onSelect(cell.stack, frame, layout.count == 1)
                    }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        if !isEditing { onStartEditing() }
                    }
                    .gesture(reorderGesture(for: cell, in: layout), including: isEditing ? .all : .subviews)
            }
        }
    }

    private func removeBadge(for stack: FriendStack) -> some View {
        Button {
            Haptics.warning()
            onRemove(stack.ownerID)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color(white: 0.2), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("planet.removeFromScreen", comment: "Remove from screen"))
    }

    /// Dragging a stack: over another cell — they swap places.
    private func reorderGesture(for cell: Cell, in layout: [Cell]) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(HomeSpace.name))
            .onChanged { value in
                if dragged != cell.stack.ownerID {
                    dragged = cell.stack.ownerID
                    dragStart = cell.center
                }
                dragTranslation = value.translation
                trackEdge(x: value.location.x, ownerID: cell.stack.ownerID)
                let point = CGPoint(x: dragStart.x + value.translation.width,
                                    y: dragStart.y + value.translation.height)
                guard let target = layout.firstIndex(where: {
                    $0.stack.ownerID != cell.stack.ownerID
                        && hypot($0.center.x - point.x, $0.center.y - point.y) < $0.diameter * 0.45
                }) else { return }
                onMove(cell.stack.ownerID, pageOffset + target)
            }
            .onEnded { _ in
                dwellTask?.cancel()
                dwellEdge = 0
                withAnimation(DS.Motion.standard) {
                    dragged = nil
                    dragTranslation = .zero
                }
            }
    }

    /// Finger at the screen edge — after a moment the stack moves to the neighboring page.
    private func trackEdge(x: CGFloat, ownerID: UUID) {
        let edge = x < 36 ? -1 : (x > size.width - 36 ? 1 : 0)
        guard edge != dwellEdge else { return }
        dwellEdge = edge
        dwellTask?.cancel()
        guard edge != 0 else { return }
        dwellTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(480))
                guard !Task.isCancelled, dwellEdge == edge else { return }
                onEdgeDwell(ownerID, edge)
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    struct Cell {
        let stack: FriendStack
        /// Center of the planet disc.
        let center: CGPoint
        let diameter: CGFloat
    }

    private var cells: [Cell] {
        guard !stacks.isEmpty else { return [] }
        if stacks.count == 1 {
            return [Cell(stack: stacks[0], center: discCenter, diameter: fullDiameter)]
        }

        let columns = min(stacks.count, 3)
        let rows = (stacks.count + 2) / 3
        let bottom = size.height - 150
        let area = max(bottom - top, 200)
        let columnWidth = (size.width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns)
        let rowSpacing: CGFloat = 22
        let byHeight = (area - CGFloat(rows) * labelHeight - CGFloat(rows - 1) * rowSpacing) / CGFloat(rows)
        let diameter = min(columnWidth * 0.92, byHeight * 0.95)
        let rowHeight = diameter + labelHeight
        let totalHeight = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
        let firstRowTop = top + (area - totalHeight) / 2

        return stacks.enumerated().map { index, stack in
            let row = index / 3
            let inRow = row == rows - 1 ? stacks.count - row * 3 : 3
            let column = index % 3
            // An incomplete row — centered.
            let rowWidth = CGFloat(inRow) * columnWidth + CGFloat(inRow - 1) * 12
            let x = (size.width - rowWidth) / 2 + columnWidth * (CGFloat(column) + 0.5) + CGFloat(column) * 12
            let y = firstRowTop + CGFloat(row) * (rowHeight + rowSpacing) + labelHeight + diameter / 2
            return Cell(stack: stack, center: CGPoint(x: x, y: y), diameter: diameter)
        }
    }
}

/// Grid cell: avatar and name on top, a slowly spinning planet below.
/// Several planets of one friend lie in a stack.
struct FriendPlanetCell: View {
    let stack: FriendStack
    let diameter: CGFloat
    let isDay: Bool
    var isHidden = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                AvatarView(nickname: stack.nickname, colorHex: stack.avatarColorHex,
                           imageData: stack.avatarData, size: 20)
                Text(verbatim: stack.nickname)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Colors.onDarkText)
                    .lineLimit(1)
            }
            .frame(height: 22)

            PlanetStackView(planets: stack.planets, diameter: diameter, isDay: isDay)
        }
        .opacity(isHidden ? 0 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: stack.planets.first?.title ?? stack.nickname))
        .accessibilityAddTraits(.isButton)
    }
}

/// A planet with the other planets stacked behind it (small offset copies).
struct PlanetStackView: View {
    @Environment(AppEnvironment.self) private var environment

    let planets: [PlanetInfo]
    let diameter: CGFloat
    let isDay: Bool

    var body: some View {
        let side = (diameter / GlobeScene.miniDiscFraction).rounded()
        ZStack {
            ForEach(Array(planets.dropFirst().prefix(2).enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.2, green: 0.35, blue: 0.7), Color(red: 0.05, green: 0.08, blue: 0.2)],
                                         center: .center, startRadius: 0, endRadius: diameter / 2))
                    .frame(width: diameter * 0.96, height: diameter * 0.96)
                    .opacity(0.6 - Double(index) * 0.2)
                    .offset(x: CGFloat(index + 1) * diameter * 0.07, y: -CGFloat(index + 1) * diameter * 0.07)
            }
            MiniGlobeView(dots: planets.first?.dots ?? [], isDay: isDay,
                          markerStyle: environment.settings.planetMarker)
                .frame(width: side, height: side)
        }
        .frame(width: diameter, height: diameter)
    }
}

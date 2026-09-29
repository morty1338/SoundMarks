import SwiftUI

/// "Add Planet" in the app style: a new own planet, friend planets
/// that can be added, and a paired planet with a friend.
struct AddPlanetSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let directory: PlanetDirectory
    let isDay: Bool
    /// Show the added or created planet on the home screen.
    let onShow: (PlanetPage) -> Void

    @State private var newPlanetName = ""
    @State private var preview: Preview?
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private struct Preview: Identifiable, Equatable {
        let planet: PlanetInfo
        let ownerID: UUID
        let nickname: String
        var id: PlanetPage { planet.page }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.m), count: 3)

    var body: some View {
        ZStack {
            SettingsStyle.background.ignoresSafeArea()
            StarryBackground().opacity(0.5)

            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    hero
                    ownPlanetCard
                    friendPlanetsCard
                    pairedCard
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.vertical, DS.Spacing.l)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            if let preview {
                previewCard(preview)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.smooth(duration: 0.3), value: preview)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .preferredColorScheme(.dark)
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(role: .cancel) { errorMessage = nil } label: { Text("common.ok", comment: "OK") }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    /// Three live planets: own, a friend's and paired — it's clear at once what can be done here.
    private var hero: some View {
        VStack(spacing: DS.Spacing.m) {
            MarksTitle(text: "Add Planet", size: 34)
            HStack(alignment: .bottom, spacing: DS.Spacing.l) {
                heroPlanet(size: 58, dots: sampleDots(seed: 1), label: Text("addPlanet.hero.own", comment: "Own"))
                heroPlanet(size: 86, dots: sampleDots(seed: 2), label: Text("addPlanet.hero.friend", comment: "Friend's"))
                heroPlanet(size: 58, dots: sampleDots(seed: 3), label: Text("addPlanet.hero.paired", comment: "Paired"))
            }
        }
        .padding(.top, DS.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func heroPlanet(size: CGFloat, dots: [SphereMapping.Coordinate], label: Text) -> some View {
        VStack(spacing: 6) {
            MiniGlobeView(dots: dots, isDay: isDay, markerStyle: environment.settings.planetMarker)
                .frame(width: size, height: size)
            label
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Colors.onDarkSecondary)
        }
    }

    /// A few dots for the decorative planets in the header.
    private func sampleDots(seed: Int) -> [SphereMapping.Coordinate] {
        [
            SphereMapping.Coordinate(latitude: 48 + Double(seed), longitude: 10 + Double(seed * 7)),
            SphereMapping.Coordinate(latitude: 40 - Double(seed * 3), longitude: -3 + Double(seed * 11)),
            SphereMapping.Coordinate(latitude: 55, longitude: 30 - Double(seed * 5)),
        ]
    }

    // MARK: - Own planet

    private var ownPlanetCard: some View {
        SettingsCard(Text("addPlanet.own", comment: "New own planet"),
                     footer: Text("addPlanet.own.footer", comment: "What an own planet is")) {
            HStack(spacing: DS.Spacing.m) {
                ZStack {
                    MiniGlobeView(dots: [], isDay: isDay, markerStyle: environment.settings.planetMarker)
                        .frame(width: 58, height: 58)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(DS.Colors.marks, in: Circle())
                        .offset(x: 20, y: 20)
                }

                TextField(text: $newPlanetName) {
                    Text("addPlanet.own.placeholder", comment: "For example, Italy 2025")
                }
                .focused($isNameFocused)
                .textInputAutocapitalization(.sentences)
                .foregroundStyle(DS.Colors.onDarkText)
                .padding(.horizontal, DS.Spacing.m)
                .frame(minHeight: DS.Size.tapTarget)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(isNameFocused ? DS.Colors.marks : .clear, lineWidth: 1.5))
                .submitLabel(.done)
                .onSubmit(createOwnPlanet)

                Button(action: createOwnPlanet) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                        .background(isNameEmpty ? Color.white.opacity(0.15) : DS.Colors.marks, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isNameEmpty)
                .accessibilityLabel(Text("addPlanet.own.create", comment: "Create"))
            }
            .padding(DS.Spacing.m)
        }
    }

    private var isNameEmpty: Bool {
        newPlanetName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createOwnPlanet() {
        let name = newPlanetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let page = try directory.createOwnPlanet(named: name)
            Haptics.success()
            onShow(page)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Friend planets

    private var friendPlanetsCard: some View {
        let items = directory.availableStacks.flatMap { stack in
            stack.planets.map { Preview(planet: $0, ownerID: stack.ownerID, nickname: stack.nickname) }
        }

        return SettingsCard(Text("addPlanet.friends", comment: "Friend planets")) {
            if items.isEmpty {
                VStack(spacing: DS.Spacing.s) {
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(DS.Colors.marks)
                    Text(environment.profiles.friends.isEmpty
                         ? String(localized: "addPlanet.friends.noFriends",
                                  defaultValue: "Add friends first – the “F” button on the home screen.")
                         : String(localized: "addPlanet.friends.empty",
                                  defaultValue: "No new planets yet. They appear after syncing nearby or via a file."))
                        .font(.subheadline)
                        .foregroundStyle(DS.Colors.onDarkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(DS.Spacing.l)
            } else {
                LazyVGrid(columns: columns, spacing: DS.Spacing.l) {
                    ForEach(items) { item in
                        Button {
                            Haptics.tap()
                            preview = item
                        } label: {
                            planetTile(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DS.Spacing.m)
            }
        }
    }

    private func planetTile(_ item: Preview) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                AvatarView(nickname: item.planet.nickname, colorHex: item.planet.avatarColorHex,
                           imageData: item.planet.avatarData, size: 18)
                Text(verbatim: item.nickname)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Colors.onDarkText)
                    .lineLimit(1)
            }
            MiniGlobeView(dots: item.planet.dots, isDay: isDay, markerStyle: environment.settings.planetMarker)
                .frame(width: 84, height: 84)
            Text(verbatim: item.planet.title)
                .font(.caption2)
                .foregroundStyle(DS.Colors.onDarkSecondary)
                .lineLimit(1)
            countBadge(item.planet.placeCount)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func countBadge(_ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
            VinylGlyph(size: 14)
        }
        .foregroundStyle(DS.Colors.onDarkText)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    /// A small window: the planet spins, below it — "add" or "paired".
    private func previewCard(_ item: Preview) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { preview = nil }

            VStack(spacing: DS.Spacing.m) {
                MiniGlobeView(dots: item.planet.dots, isDay: isDay, markerStyle: environment.settings.planetMarker)
                    .frame(width: 200, height: 200)
                PlanetNameLabel(text: item.planet.title)
                HStack(spacing: DS.Spacing.s) {
                    AvatarView(nickname: item.planet.nickname, colorHex: item.planet.avatarColorHex,
                               imageData: item.planet.avatarData, size: 26)
                    NameFrame(text: item.nickname, size: 15)
                    countBadge(item.planet.placeCount)
                }

                Button {
                    addFriendPlanet(item)
                } label: {
                    Text("addPlanet.add", comment: "Add their planet to mine")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(DS.Colors.marks, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    createPaired(with: item.ownerID)
                } label: {
                    Text("addPlanet.pair \(item.nickname)", comment: "Create a paired planet with the friend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Colors.onDarkText)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(DS.Colors.marks.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.l)
            .frame(maxWidth: 330)
            .background(Color(red: 0.08, green: 0.09, blue: 0.15), in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(SettingsStyle.cardStroke))
            .padding(DS.Spacing.l)
        }
    }

    private func addFriendPlanet(_ item: Preview) {
        do {
            try directory.add(item.planet.page)
            Haptics.success()
            onShow(item.planet.page)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Paired planet

    private var pairedCard: some View {
        SettingsCard(Text("addPlanet.paired", comment: "Paired planet"),
                     footer: Text("addPlanet.paired.footer", comment: "What a paired planet is")) {
            if environment.profiles.friends.isEmpty {
                Text("addPlanet.friends.noFriends", comment: "Add friends first")
                    .font(.subheadline)
                    .foregroundStyle(DS.Colors.onDarkSecondary)
                    .padding(DS.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(environment.profiles.friends.enumerated()), id: \.element.id) { index, friend in
                HStack(spacing: DS.Spacing.m) {
                    pairBadge(friend)
                    NameFrame(text: friend.nickname ?? "", size: 15)
                    Spacer(minLength: 0)
                    Button {
                        if let id = friend.id { createPaired(with: id) }
                    } label: {
                        Text("addPlanet.paired.create", comment: "Create paired")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, DS.Spacing.m)
                            .frame(minHeight: 36)
                            .background(DS.Colors.marks, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, 10)

                if index < environment.profiles.friends.count - 1 {
                    SettingsStyle.divider.frame(height: 1).padding(.leading, DS.Spacing.m)
                }
            }
        }
    }

    /// Two avatars above two linked planets — "one planet for two".
    private func pairBadge(_ friend: Profile) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.86), Color(red: 0.1, green: 0.2, blue: 0.45)],
                                     center: .topLeading, startRadius: 2, endRadius: 30))
                .frame(width: 34, height: 34)
                .offset(x: -9)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.53, green: 0.75, blue: 0.45), Color(red: 0.15, green: 0.35, blue: 0.2)],
                                     center: .topLeading, startRadius: 2, endRadius: 30))
                .frame(width: 34, height: 34)
                .offset(x: 9)
            if let me = environment.profiles.me {
                AvatarView(profile: me, size: 20)
                    .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                    .offset(x: -14, y: -14)
            }
            AvatarView(profile: friend, size: 20)
                .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                .offset(x: 14, y: -14)
        }
        .frame(width: 60, height: 50)
        .accessibilityHidden(true)
    }

    private func createPaired(with ownerID: UUID) {
        guard let friend = environment.profiles.trustedFriend(id: ownerID) else { return }
        do {
            let map = try environment.sync.createSharedMap(with: friend)
            Haptics.success()
            // The friend sees it after the next nearby exchange.
            environment.nearby.syncNow(with: friend)
            directory.reload()
            if let id = map.id { onShow(.shared(id)) }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

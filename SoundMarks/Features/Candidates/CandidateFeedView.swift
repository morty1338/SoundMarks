import SwiftUI

/// Feed of candidate cards: swipe right — add, left — skip.
///
/// The preview of the top card starts by itself; the next card's preview is loaded in advance.
struct CandidateFeedView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL

    let scanner: MemoryScanner
    let onDone: () -> Void

    @State private var model: CandidateFeedViewModel?
    @State private var player = PreviewAudioPlayer()
    @State private var dragOffset: CGSize = .zero
    @State private var isPastThreshold = false
    @State private var isPickingTrack = false
    /// Cards that already flew away. Confirmation saves asynchronously — without this
    /// the next card would show up for a moment at the flown-away offset.
    @State private var departedIDs: Set<UUID> = []

    private static let threshold: CGFloat = 110
    private static let skipTint = Color(red: 1.0, green: 0.38, blue: 0.42)

    var body: some View {
        ZStack {
            background

            if let model {
                let visible = model.candidates.filter { !departedIDs.contains($0.id) }
                if let candidate = visible.first {
                    feed(model: model, candidate: candidate, next: visible.dropFirst().first,
                         remaining: visible.count)
                } else {
                    summary(model)
                        .onAppear { player.stop() }
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(Text("candidates.title", comment: "Candidate feed title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Colors.space, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            guard model == nil else { return }
            let created = CandidateFeedViewModel(scanner: scanner, environment: environment)
            model = created
            await created.geocodeUpcoming()
        }
        .onDisappear { player.stop() }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { model?.errorMessage != nil },
                                    set: { if !$0 { model?.errorMessage = nil } })) {
            Button(role: .cancel) { model?.errorMessage = nil } label: {
                Text("common.ok", comment: "OK")
            }
        } message: {
            Text(model?.errorMessage ?? "")
        }
    }

    private var background: some View {
        ZStack {
            DS.Colors.space
            RadialGradient(colors: [DS.Colors.marks.opacity(0.16), .clear],
                           center: .top, startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    // MARK: - Feed

    private struct PlaybackKey: Hashable {
        let candidateID: UUID
        let trackIndex: Int
    }

    private func feed(model: CandidateFeedViewModel,
                      candidate: MemoryCandidate,
                      next: MemoryCandidate?,
                      remaining: Int) -> some View {
        let entry = model.catalogEntry(for: candidate)
        let previewURL = entry?.previewURL
        let progress = min(1, abs(dragOffset.width) / Self.threshold)

        return VStack(spacing: DS.Spacing.l) {
            counters(remaining: remaining, added: model.confirmedCount)

            ZStack {
                // The next card waits underneath and grows as the top one is dragged away.
                if let next {
                    CandidateCardView(candidate: next,
                                      loader: environment.mediaLoader,
                                      artworkURL: model.catalogEntry(for: next)?.artworkURL)
                        .id(next.id)
                        .scaleEffect(0.93 + 0.07 * progress)
                        .offset(y: 14 * (1 - progress))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                CandidateCardView(candidate: candidate,
                                  loader: environment.mediaLoader,
                                  artworkURL: entry?.artworkURL,
                                  hasPreview: previewURL != nil,
                                  isPlaying: previewURL != nil && player.currentURL == previewURL && player.isPlaying,
                                  onTogglePlayback: {
                                      if let previewURL { player.toggle(previewURL) }
                                  },
                                  onPickTrack: { isPickingTrack = true })
                    .id(candidate.id)
                    .overlay(alignment: .topLeading) {
                        stamp("candidates.add", color: DS.Colors.marks, angle: -14)
                            .opacity(dragOffset.width > 0 ? progress : 0)
                            .padding(.top, 44)
                            .padding(.leading, DS.Spacing.l)
                    }
                    .overlay(alignment: .topTrailing) {
                        stamp("candidates.skip", color: Self.skipTint, angle: 14)
                            .opacity(dragOffset.width < 0 ? progress : 0)
                            .padding(.top, 44)
                            .padding(.trailing, DS.Spacing.l)
                    }
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)), anchor: .bottom)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                                let past = abs(value.translation.width) > Self.threshold
                                if past != isPastThreshold {
                                    isPastThreshold = past
                                    if past { Haptics.select() }
                                }
                            }
                            .onEnded { value in
                                isPastThreshold = false
                                decide(value.translation.width, model: model, candidate: candidate)
                            }
                    )
                    .animation(DS.Motion.quick, value: dragOffset)
                    .accessibilityAction(named: Text("candidates.add", comment: "Add")) {
                        commit(direction: 1, model: model, candidate: candidate)
                    }
                    .accessibilityAction(named: Text("candidates.skip", comment: "Skip")) {
                        commit(direction: -1, model: model, candidate: candidate)
                    }
            }
            .padding(.horizontal, DS.Spacing.m)
            .frame(maxHeight: .infinity)

            actions(model: model, candidate: candidate)
        }
        .padding(.bottom, DS.Spacing.m)
        .confirmationDialog(
            Text("candidates.pickTrack", comment: "Pick another track"),
            isPresented: $isPickingTrack,
            titleVisibility: .visible
        ) {
            ForEach(Array(candidate.trackOptions.enumerated()), id: \.offset) { index, option in
                Button("\(option.title) — \(option.artist)") {
                    model.selectTrack(at: index, for: candidate)
                }
            }
        }
        .task(id: candidate.id) {
            await model.geocodeUpcoming()
        }
        .task(id: PlaybackKey(candidateID: candidate.id, trackIndex: candidate.selectedTrackIndex)) {
            await model.loadCatalogUpcoming()
            guard !Task.isCancelled else { return }
            if let url = model.catalogEntry(for: candidate)?.previewURL {
                if player.currentURL != url { player.play(url) }
            } else {
                player.stop()
            }
        }
    }

    private func counters(remaining: Int, added: Int) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Label {
                Text(String(localized: "candidates.remaining", defaultValue: "Left: \(remaining)"))
            } icon: {
                Image(systemName: "rectangle.stack")
            }
            Label {
                Text(String(localized: "candidates.added", defaultValue: "Added: \(added)"))
            } icon: {
                Image(systemName: "mappin.circle")
            }
            .foregroundStyle(DS.Colors.marks)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(DS.Colors.onDarkSecondary)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .liquidGlass(in: Capsule())
        .padding(.top, DS.Spacing.s)
    }

    /// Tinder-style stamp that shows up while dragging.
    private func stamp(_ key: LocalizedStringKey, color: Color, angle: Double) -> some View {
        Text(key)
            .font(.system(size: 28, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func actions(model: CandidateFeedViewModel, candidate: MemoryCandidate) -> some View {
        HStack(spacing: DS.Spacing.l) {
            roundButton(systemImage: "xmark", tint: Self.skipTint, labelKey: "candidates.skip") {
                commit(direction: -1, model: model, candidate: candidate)
            }

            if let play = candidate.selectedTrack, let url = SpotifyLink.url(for: play) {
                Button {
                    Haptics.tap()
                    player.stop()
                    openURL(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                        Text(verbatim: "Spotify")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, DS.Spacing.l)
                    .frame(height: DS.Size.tapTarget + 4)
                    .background(DS.Colors.spotify, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("candidates.openSpotify", comment: "Listen on Spotify"))
            }

            roundButton(systemImage: "checkmark", tint: DS.Colors.marks, labelKey: "candidates.add") {
                commit(direction: 1, model: model, candidate: candidate)
            }
        }
    }

    private func roundButton(systemImage: String,
                             tint: Color,
                             labelKey: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 66, height: 66)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Circle())
        .accessibilityLabel(Text(labelKey))
    }

    // MARK: - Summary

    private func summary(_ model: CandidateFeedViewModel) -> some View {
        VStack(spacing: DS.Spacing.l) {
            Spacer()

            Image(systemName: model.confirmedCount > 0 ? "checkmark.circle" : "tray")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(DS.Colors.marks)

            Text("candidates.done.title", comment: "The feed is over")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Colors.onDarkText)

            Text(String(localized: "candidates.done.body",
                        defaultValue: "Added \(model.confirmedCount), skipped \(model.skippedCount)."))
                .font(.subheadline)
                .foregroundStyle(DS.Colors.onDarkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                Task {
                    await model.finish()
                    onDone()
                }
            } label: {
                Text("candidates.done.action", comment: "Open the map")
                    .font(.headline)
                    .foregroundStyle(DS.Colors.vinyl)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Colors.marks, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Decisions

    private func decide(_ width: CGFloat, model: CandidateFeedViewModel, candidate: MemoryCandidate) {
        if width > Self.threshold {
            commit(direction: 1, model: model, candidate: candidate)
        } else if width < -Self.threshold {
            commit(direction: -1, model: model, candidate: candidate)
        } else {
            dragOffset = .zero
        }
    }

    private func commit(direction: CGFloat, model: CandidateFeedViewModel, candidate: MemoryCandidate) {
        guard !departedIDs.contains(candidate.id) else { return }
        if direction > 0 { Haptics.success() } else { Haptics.tap() }

        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGSize(width: direction * 700, height: dragOffset.height + 40)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            // The next card takes the place without animation — it is already under the flown-away one.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                departedIDs.insert(candidate.id)
                dragOffset = .zero
            }

            if direction > 0 {
                await model.confirm(candidate)
            } else {
                model.skip(candidate)
            }
            // Gone from the feed — the marker isn't needed; saving failed — the card comes back.
            departedIDs.remove(candidate.id)
        }
    }
}

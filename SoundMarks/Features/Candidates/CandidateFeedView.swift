import SwiftUI

/// Feed of candidate cards: swipe right — add, left — skip.
struct CandidateFeedView: View {
    @Environment(AppEnvironment.self) private var environment

    let scanner: MemoryScanner
    let onDone: () -> Void

    @State private var model: CandidateFeedViewModel?
    @State private var dragOffset: CGSize = .zero
    @State private var isPickingTrack = false

    var body: some View {
        Group {
            if let model {
                if let candidate = model.candidates.first {
                    feed(model: model, candidate: candidate)
                } else {
                    summary(model)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text("candidates.title", comment: "Candidate feed title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let created = CandidateFeedViewModel(scanner: scanner, environment: environment)
            model = created
            await created.geocodeUpcoming()
        }
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

    // MARK: - Feed

    private func feed(model: CandidateFeedViewModel, candidate: MemoryCandidate) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(String(localized: "candidates.remaining",
                             defaultValue: "Left: \(model.candidates.count)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "candidates.added",
                             defaultValue: "Added: \(model.confirmedCount)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ZStack {
                // The next card peeks from the edge — it's clear the feed continues.
                if model.candidates.count > 1 {
                    CandidateCardView(candidate: model.candidates[1], loader: environment.mediaLoader)
                        .scaleEffect(0.95)
                        .opacity(0.5)
                        .allowsHitTesting(false)
                }

                CandidateCardView(candidate: candidate, loader: environment.mediaLoader)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 22)))
                    .overlay(alignment: .topLeading) { decisionBadge }
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { value in decide(value.translation.width, model: model, candidate: candidate) }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
            }
            .padding(.horizontal, 20)

            trackPicker(model: model, candidate: candidate)

            HStack(spacing: 18) {
                decisionButton(system: "xmark", tint: .secondary) {
                    commit(direction: -1, model: model, candidate: candidate)
                }
                decisionButton(system: "checkmark", tint: .accentColor) {
                    commit(direction: 1, model: model, candidate: candidate)
                }
            }
            .padding(.bottom, 12)
        }
        .task(id: candidate.id) {
            await model.geocodeUpcoming()
        }
    }

    @ViewBuilder
    private var decisionBadge: some View {
        if abs(dragOffset.width) > 40 {
            let isAdding = dragOffset.width > 0
            Text(isAdding ? "candidates.add" : "candidates.skip")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isAdding ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary), in: Capsule())
                .foregroundStyle(.white)
                .padding(16)
                .opacity(min(1, abs(dragOffset.width) / 110))
        }
    }

    private func trackPicker(model: CandidateFeedViewModel, candidate: MemoryCandidate) -> some View {
        Group {
            if candidate.trackOptions.count > 1 {
                Button {
                    isPickingTrack = true
                } label: {
                    Label {
                        Text(String(localized: "candidates.otherTracks",
                                     defaultValue: "\(candidate.trackOptions.count - 1) more matches"))
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .font(.footnote)
                }
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
            }
        }
    }

    private func decisionButton(system: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 58, height: 58)
                .background(.regularMaterial, in: Circle())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(system == "checkmark"
            ? Text("candidates.add", comment: "Add")
            : Text("candidates.skip", comment: "Skip"))
    }

    private func summary(_ model: CandidateFeedViewModel) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: model.confirmedCount > 0 ? "checkmark.circle" : "tray")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)

            Text("candidates.done.title", comment: "The feed is over")
                .font(.title3.weight(.semibold))

            Text(String(localized: "candidates.done.body",
                        defaultValue: "Added \(model.confirmedCount), skipped \(model.skippedCount)."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Decisions

    private func decide(_ width: CGFloat, model: CandidateFeedViewModel, candidate: MemoryCandidate) {
        let threshold: CGFloat = 110
        if width > threshold {
            commit(direction: 1, model: model, candidate: candidate)
        } else if width < -threshold {
            commit(direction: -1, model: model, candidate: candidate)
        } else {
            dragOffset = .zero
        }
    }

    private func commit(direction: CGFloat, model: CandidateFeedViewModel, candidate: MemoryCandidate) {
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = CGSize(width: direction * 600, height: 0)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(180))
            if direction > 0 {
                await model.confirm(candidate)
            } else {
                model.skip(candidate)
            }
            dragOffset = .zero
        }
    }
}

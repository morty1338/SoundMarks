import SwiftUI

/// Manual track search in the catalog (iTunes Search API).
struct TrackSearchView: View {
    let metadata: MetadataService
    let onSelect: (TrackMetadata) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [TrackMetadata] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(results) { track in
                    Button {
                        onSelect(track)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImage(url: track.artworkURL, cornerRadius: 6)
                                .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if track.previewURL == nil {
                                Image(systemName: "speaker.slash")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityLabel(Text("track.noPreview", comment: "No preview"))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if results.isEmpty, !query.isEmpty, !isSearching, errorMessage == nil {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.plain)
            .overlay {
                if isSearching, results.isEmpty { ProgressView() }
            }
            .navigationTitle(Text("addPlace.findTrack", comment: "Track search title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("addPlace.searchPrompt", comment: "Search field hint"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("common.cancel", comment: "Cancel")
                    }
                }
            }
            .task(id: query) {
                await search()
            }
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }

        // A pause suppresses requests on every keystroke — the catalog has a rate limit.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            results = try await metadata.search(query: term, limit: 25)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as AppError {
            errorMessage = error.errorDescription
            results = []
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}

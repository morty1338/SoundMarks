import SwiftUI

/// Import of a history file opened from Files or the share sheet.
struct HistoryImportSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let url: URL

    @State private var phase: Phase = .working

    private enum Phase {
        case working
        case done(StreamingHistoryImportSummary)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()

                switch phase {
                case .working:
                    ProgressView()
                    Text("import.working", comment: "Parsing the history file")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                case .done(let summary):
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.tint)
                    Text(String(localized: "import.done",
                                defaultValue: "Plays imported: \(summary.playCount)"))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if summary.skippedShortPlays > 0 {
                        Text(String(localized: "import.skipped",
                                    defaultValue: "Short plays skipped: \(summary.skippedShortPlays)"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .navigationTitle(Text("import.title", comment: "Import title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("common.done", comment: "Done")
                    }
                }
            }
        }
        .task(id: url) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let summary = try await environment.spotifyImporter.importArchive(at: url)
                phase = .done(summary)
            } catch let error as AppError {
                phase = .failed([error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: "\n"))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

/// Wrapper for `.sheet(item:)`.
struct ImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

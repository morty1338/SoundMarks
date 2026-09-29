import SwiftUI

/// A `.soundmap` file opened from AirDrop, a messenger or Files.
/// Accepted only from a friend; the result is shown in plain language.
struct SoundmapImportSheet: View {
    @Environment(AppEnvironment.self) private var environment

    let url: URL
    let onImported: () -> Void

    private enum Phase {
        case importing
        case done(SyncSummary)
        case failed(String)
    }

    @State private var phase: Phase = .importing

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            switch phase {
            case .importing:
                ProgressView()
                    .controlSize(.large)
                Text("soundmap.import.progress", comment: "Importing the map file")
                    .foregroundStyle(.secondary)

            case .done(let summary):
                Image(systemName: summary.planetHidden ? "eye.slash" : "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(summary.planetHidden ? Color.secondary : DS.Colors.accent)
                Text(summary.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(summary.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("soundmap.import.failed", comment: "Title: file not accepted")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .task { importFile() }
    }

    private func importFile() {
        do {
            let summary = try environment.sync.importFile(at: url)
            Haptics.success()
            phase = .done(summary)
            onImported()
        } catch let failure as SyncService.Failure {
            Haptics.warning()
            phase = .failed(failure == .notFriend
                ? String(localized: "soundmap.import.notFriend",
                         defaultValue: "This file is from someone who isn't your friend. Add each other nearby via QR code first.")
                : failure.errorDescription ?? "")
        } catch let failure as SoundmapFile.Failure {
            Haptics.warning()
            phase = .failed(failure.errorDescription ?? "")
        } catch {
            Haptics.warning()
            phase = .failed(String(localized: "soundmap.import.unreadable",
                                   defaultValue: "The file couldn't be opened. Ask your friend to send it again."))
        }
    }
}

extension SyncSummary {
    var title: String {
        switch kind {
        case .planet:
            String(localized: "sync.summary.planet", defaultValue: "\(senderName)'s planet updated")
        case .shared:
            String(localized: "sync.summary.shared", defaultValue: "Shared map with \(senderName) updated")
        }
    }

    var details: String {
        if planetHidden {
            return String(localized: "sync.summary.hidden",
                          defaultValue: "\(senderName) hid their planet – it's been removed from your screen.")
        }
        if added + updated + removed == 0 {
            return String(localized: "sync.summary.nothing", defaultValue: "Nothing new.")
        }
        return String(localized: "sync.summary.counts",
                      defaultValue: "New places: \(added) · changed: \(updated) · removed: \(removed)")
    }
}

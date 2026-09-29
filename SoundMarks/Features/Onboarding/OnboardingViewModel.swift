import Foundation
import Observation

/// Onboarding steps. Connecting a source and photo access can be skipped
/// and revisited later from settings.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case intro
    case source
    case photos
    case period
    case scanning
    case candidates

    var id: Int { rawValue }
}

@MainActor
@Observable
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .intro

    private(set) var historySummary: PlayHistoryStore.Summary = .empty
    private(set) var photoAuthorization: PhotoAuthorization = .notDetermined
    private(set) var availableYears: [Int] = []
    var selectedYears: Set<Int> = []

    private(set) var isImporting = false
    private(set) var importResult: StreamingHistoryImportSummary?
    var errorMessage: String?

    var lastFmUsername = ""
    private(set) var isConnectingLastFm = false
    private(set) var isLastFmConnected = false

    let scanner: MemoryScanner

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        scanner = environment.makeScanner()
    }

    var isLastFmAvailable: Bool { LastFmConfiguration.isConfigured }

    /// Whether there is anything to scan: history is connected and photos are accessible.
    var canScan: Bool {
        historySummary.playCount > 0 && photoAuthorization.allowsReading
    }

    var hasHistory: Bool { historySummary.playCount > 0 }

    // MARK: - Navigation

    func refresh() async {
        historySummary = await PlayHistoryStore.shared.summary()
        photoAuthorization = await environment.photos.authorization
        isLastFmConnected = await environment.lastFm.isConnected
    }

    func advance() {
        switch step {
        case .intro:
            step = .source
        case .source:
            step = .photos
        case .photos:
            step = canScan ? .period : .candidates
        case .period:
            startScan()
        case .scanning:
            step = .candidates
        case .candidates:
            break
        }
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func finish() {
        scanner.cancel()
        environment.settings.hasCompletedOnboarding = true
    }

    // MARK: - Sources

    func importArchive(at url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let summary = try await environment.spotifyImporter.importArchive(at: url)
            importResult = summary
            await refresh()
            await loadAvailableYears()
        } catch let error as AppError {
            errorMessage = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: "\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectLastFm() async {
        isConnectingLastFm = true
        defer { isConnectingLastFm = false }

        do {
            try await environment.lastFm.connect(username: lastFmUsername)
            isLastFmConnected = true

            // Last.fm history is available right away — fetch everything there is.
            let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date())
            _ = try await environment.lastFm.syncHistory(in: interval) { _ in }
            await refresh()
            await loadAvailableYears()
        } catch let error as AppError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectLastFm() async {
        await environment.lastFm.disconnect()
        isLastFmConnected = false
    }

    // MARK: - Photos

    func requestPhotoAccess() async {
        photoAuthorization = await environment.photos.requestAuthorization()
        await loadAvailableYears()
    }

    /// Years that have both plays and geotagged photos.
    func loadAvailableYears() async {
        let historyYears = Set(await PlayHistoryStore.shared.yearsWithPlays())
        guard photoAuthorization.allowsReading else {
            availableYears = historyYears.sorted(by: >)
            return
        }

        let photoYears = Set((try? await environment.photos.yearsWithGeotaggedAssets()) ?? [])
        let overlap = historyYears.intersection(photoYears)
        availableYears = (overlap.isEmpty ? historyYears : overlap).sorted(by: >)

        if selectedYears.isEmpty, let latest = availableYears.first {
            // By default we suggest one year — scanning everything is secondary.
            selectedYears = [latest]
        }
    }

    // MARK: - Scanning

    func startScan() {
        guard !selectedYears.isEmpty else { return }
        step = .scanning
        scanner.start(years: Array(selectedYears), options: environment.settings.matcherOptions)
    }

    func selectAllYears() {
        selectedYears = Set(availableYears)
    }

    func cancelScan() {
        scanner.cancel()
        step = .period
    }
}

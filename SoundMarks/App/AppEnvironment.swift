import CoreData
import Foundation
import Observation
import UserNotifications

/// Dependency composition. All services live behind protocols,
/// so implementations can be swapped per phase and in tests.
///
/// Services are created lazily: app launch does the bare minimum,
/// the map shows up immediately, and Core Location, PhotoKit and the network start
/// on first real use.
@MainActor
@Observable
final class AppEnvironment {
    let persistence: PersistenceController
    let settings: AppSettings

    @ObservationIgnored private let metadataService: LazyService<any MetadataService>
    @ObservationIgnored private let locationService: LazyService<any LocationService>
    @ObservationIgnored private let photoService: LazyService<any PhotoService>
    @ObservationIgnored private let notificationService: LazyService<any NotificationService>
    @ObservationIgnored private let spotifyImporterService: LazyService<SpotifyExportImporter>
    @ObservationIgnored private let lastFmService: LazyService<LastFmSource>
    @ObservationIgnored private let mediaLoaderService: LazyService<MediaLoader>
    @ObservationIgnored private let geofenceService: LazyService<GeofenceManager>
    @ObservationIgnored private let additionalSources: @MainActor () -> [any MusicSource]

    var metadata: any MetadataService { metadataService.value }
    var location: any LocationService { locationService.value }
    var photos: any PhotoService { photoService.value }
    var notifications: any NotificationService { notificationService.value }

    /// Spotify history import — works without the API, from the export file.
    var spotifyImporter: SpotifyExportImporter { spotifyImporterService.value }
    /// Last.fm — quick start, history is available right away.
    var lastFm: LastFmSource { lastFmService.value }
    var mediaLoader: MediaLoader { mediaLoaderService.value }
    /// Geofences: the 20 nearest places and reminders when you come back.
    var geofences: GeofenceManager { geofenceService.value }

    let notificationRouter = NotificationRouter()

    /// My profile and friends.
    let profiles: ProfileStore
    @ObservationIgnored private let syncService: LazyService<SyncService>
    @ObservationIgnored private let nearbyService: LazyService<NearbyService>
    /// Map exchange: snapshots, `.soundmap` files, merging.
    var sync: SyncService { syncService.value }
    /// Nearby friends via MultipeerConnectivity.
    var nearby: NearbyService { nearbyService.value }

    /// Travel mode: route recording and trip history.
    let trips: TripTracker

    /// Day or night — light or dark planet and map.
    let dayCycle = DayCycle()

    /// Map file from a friend, opened from Files, AirDrop or a messenger.
    private(set) var pendingSoundmapURL: URL?

    @ObservationIgnored private var hasPreparedNotifications = false

    /// History file opened from Files or the share sheet. The map shows the import.
    private(set) var pendingImportURL: URL?

    init(persistence: PersistenceController,
         settings: AppSettings,
         metadata: @escaping @MainActor () -> any MetadataService,
         location: @escaping @MainActor () -> any LocationService,
         photos: @escaping @MainActor () -> any PhotoService,
         notifications: @escaping @MainActor () -> any NotificationService,
         spotifyImporter: @escaping @MainActor () -> SpotifyExportImporter,
         lastFm: @escaping @MainActor () -> LastFmSource,
         additionalSources: @escaping @MainActor () -> [any MusicSource]) {
        self.persistence = persistence
        self.settings = settings
        self.additionalSources = additionalSources

        metadataService = LazyService(metadata)
        locationService = LazyService(location)
        photoService = LazyService(photos)
        notificationService = LazyService(notifications)
        spotifyImporterService = LazyService(spotifyImporter)
        lastFmService = LazyService(lastFm)

        let photoServiceRef = photoService
        mediaLoaderService = LazyService {
            MediaLoader(photos: photoServiceRef.value, persistence: persistence)
        }

        let profileStore = ProfileStore(persistence: persistence)
        profiles = profileStore
        let syncRef = LazyService { SyncService(persistence: persistence, profiles: profileStore,
                                               photos: photoServiceRef.value) }
        syncService = syncRef
        nearbyService = LazyService { NearbyService(profiles: profileStore, sync: syncRef.value) }

        let locationServiceRef = locationService
        trips = TripTracker(persistence: persistence, location: { locationServiceRef.value })
        let notificationServiceRef = notificationService
        geofenceService = LazyService {
            GeofenceManager(persistence: persistence,
                            location: locationServiceRef.value,
                            notifications: notificationServiceRef.value,
                            settings: settings)
        }
    }

    /// All music sources registered in this build.
    var musicSources: [any MusicSource] {
        var sources: [any MusicSource] = [spotifyImporter, lastFm]
        sources.append(contentsOf: additionalSources())
        return sources
    }

    /// A fresh memory scanner. Created for every pass
    /// so progress and results never carry over from a previous run.
    func makeScanner() -> MemoryScanner {
        MemoryScanner(photos: photos, syncingSources: [lastFm])
    }

    /// Production build.
    static func live() -> AppEnvironment {
        let settings = AppSettings()

        let environment = AppEnvironment(
            persistence: .shared,
            settings: settings,
            metadata: { ITunesSearchService() },
            location: { CoreLocationService() },
            photos: { PhotoKitService() },
            notifications: { LocalNotificationService() },
            spotifyImporter: { SpotifyExportImporter() },
            lastFm: { LastFmSource() },
            additionalSources: {
                var sources: [any MusicSource] = [AppleMusicSource()]
                if settings.spotifyWebAPIEnabled { sources.append(SpotifyWebAPISource()) }
                return sources
            }
        )
        // A trip may have been running when the app was closed: keep recording the route.
        environment.trips.resumeIfNeeded()
        return environment
    }

    /// Environment for previews and tests: in-memory store, stub services.
    static func ephemeral(defaults: UserDefaults = .standard) -> AppEnvironment {
        AppEnvironment(
            persistence: PersistenceController(mode: .inMemory),
            settings: AppSettings(defaults: defaults),
            metadata: { UnavailableMetadataService() },
            location: { UnavailableLocationService() },
            photos: { UnavailablePhotoService() },
            notifications: { UnavailableNotificationService() },
            spotifyImporter: { SpotifyExportImporter() },
            lastFm: { LastFmSource() },
            additionalSources: { [AppleMusicSource()] }
        )
    }

    /// The source the user picked for detecting the current track.
    var activeMusicSource: (any MusicSource)? {
        guard let kind = settings.activeMusicSource else { return nil }
        return musicSources.first { $0.kind == kind }
    }

    // MARK: - Importing an external file

    /// The app is registered as a zip/json handler — this is where a file
    /// opened from Files or passed via "Share" arrives.
    func requestImport(of url: URL) {
        if url.pathExtension.lowercased() == SoundmapFile.fileExtension {
            pendingSoundmapURL = url
        } else {
            pendingImportURL = url
        }
    }

    func clearPendingSoundmap() {
        pendingSoundmapURL = nil
    }

    func clearPendingImport() {
        pendingImportURL = nil
    }

    // MARK: - Notifications

    /// Subscribes the router to notification taps. Permission is not requested here.
    func prepareNotifications() async {
        guard !hasPreparedNotifications else { return }
        hasPreparedNotifications = true
        UNUserNotificationCenter.current().delegate = notificationRouter
    }

    /// Rebuilds the "on this day" schedule.
    ///
    /// - Parameter places: snapshots that are already loaded. Pass them so
    ///   launch does not run a second full store query.
    func refreshOnThisDaySchedule(places: [PlaceSnapshot]? = nil) async {
        guard settings.onThisDayEnabled else {
            try? await notifications.replaceOnThisDaySchedule(with: [])
            return
        }

        let snapshots = places ?? placeSnapshots()
        let schedule = OnThisDayScheduler.schedule(for: snapshots, hour: settings.onThisDayHour)
        guard !schedule.isEmpty else { return }

        // Permission is requested in context: only when there is something to remind about.
        if await !notifications.isAuthorized {
            guard (try? await notifications.requestAuthorization()) == true else { return }
        }

        do {
            try await notifications.replaceOnThisDaySchedule(with: schedule)
        } catch let error as AppError {
            Log.notifications.info("Schedule not updated: \(error.errorDescription ?? "", privacy: .public)")
        } catch {
            Log.notifications.error("Schedule not updated: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func placeSnapshots() -> [PlaceSnapshot] {
        let request = Place.fetchRequest(scope: .remindable)
        request.relationshipKeyPathsForPrefetching = ["track"]
        let context = persistence.viewContext
        return PlaceQueries.snapshots(of: (try? context.fetch(request)) ?? [], in: context)
    }
}

import SwiftUI

@main
struct SoundMarksApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(\.managedObjectContext, environment.persistence.viewContext)
                .onOpenURL { url in
                    // History file opened from Files or passed via "Share".
                    environment.requestImport(of: url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS's limit of 64 notifications requires rebuilding the schedule on every launch.
            guard phase == .active else { return }
            Task { await environment.refreshOnThisDaySchedule() }
        }
    }
}

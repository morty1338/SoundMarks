import SwiftUI
import UniformTypeIdentifiers

/// Settings: cards in the app style — profile, appearance, reminders, music,
/// memories and trips. Closes with a swipe.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Tells the map that new places appeared.
    let onPlacesChanged: () -> Void

    @State private var scheduledCount = 0
    @State private var notificationsDenied = false
    @State private var historySummary: PlayHistoryStore.Summary = .empty
    @State private var isLastFmConnected = false
    @State private var isShowingFileImporter = false
    @State private var importRequest: ImportRequest?
    @State private var isShowingScan = false
    @State private var isTogglingGeofences = false
    @State private var openedTrip: TripRequest?
    @State private var promoCode = ""
    @State private var promoMessage: PromoMessage?

    private enum PromoMessage: Equatable {
        case applied
        case unknown
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    profileCard
                    appearanceCard
                    remindersCard
                    musicCard
                    memoriesCard
                    TripsSection { openedTrip = TripRequest(id: $0) }
                    promoCard
                    privacyNote
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .background(SettingsStyle.background.ignoresSafeArea())
            .navigationTitle(Text("settings.title", comment: "Settings title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $isShowingFileImporter,
                          allowedContentTypes: [.zip, .json],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importRequest = ImportRequest(url: url)
                }
            }
            .sheet(item: $importRequest, onDismiss: { Task { await reloadHistory() } }) { request in
                HistoryImportSheet(url: request.url)
            }
            .sheet(isPresented: $isShowingScan) {
                OnboardingView(onFinish: onPlacesChanged)
            }
            .sheet(item: $openedTrip) { request in
                TripSummaryView(tripID: request.id, onSaved: onPlacesChanged)
            }
            .task { await reload() }
        }
        .tint(SettingsStyle.tint)
        .preferredColorScheme(.dark)
    }

    // MARK: - Profile

    /// A big profile card on top; planet visibility next to it, since that is about me too.
    @ViewBuilder
    private var profileCard: some View {
        if let me = environment.profiles.me {
            SettingsCard(footer: Text("settings.planetVisible.footer", comment: "What planet visibility means")) {
                NavigationLink {
                    ProfileEditView(profile: me)
                } label: {
                    HStack(spacing: DS.Spacing.m) {
                        AvatarView(profile: me, size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: me.nickname ?? "")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(DS.Colors.onDarkText)
                            Text("settings.profile.code \(me.uniqueCode ?? "")", comment: "My code in settings")
                                .font(.caption.monospaced())
                                .foregroundStyle(DS.Colors.onDarkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Colors.onDarkSecondary)
                    }
                    .padding(DS.Spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                SettingsStyle.divider.frame(height: 1)

                SettingsToggleRow(icon: "globe.europe.africa.fill", color: Color(red: 0.25, green: 0.55, blue: 0.98),
                                  title: Text("settings.planetVisible", comment: "My planet is visible to friends"),
                                  showsDivider: false,
                                  isOn: Binding(get: { me.planetVisible }, set: { setPlanetVisible($0) }))
            }
        } else {
            SettingsCard {
                SettingsRow(icon: "person.crop.circle", color: Color(red: 0.45, green: 0.5, blue: 0.62),
                            title: Text("settings.section.profile", comment: "Section: profile"),
                            subtitle: Text("settings.profile.none", comment: "The profile is created on the friends screen"),
                            showsDivider: false)
            }
        }
    }

    /// Turned off — nearby friends immediately get "planet hidden" and delete its snapshot.
    /// Those far away — on the next exchange.
    private func setPlanetVisible(_ isVisible: Bool) {
        try? environment.profiles.updateMe(planetVisible: isVisible)
        Haptics.select()
        environment.nearby.resyncAll()
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        @Bindable var settings = environment.settings

        return SettingsCard(Text("settings.section.appearance", comment: "Section: appearance")) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text("settings.markers", comment: "Markers on the planet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Colors.onDarkText)
                HStack(spacing: DS.Spacing.s) {
                    ForEach(PlanetMarkerStyle.allCases) { style in
                        SettingsChoiceTile(title: style.localizedName,
                                           isSelected: settings.planetMarker == style,
                                           action: { settings.planetMarker = style }) {
                            MarkerPreview(style: style)
                        }
                    }
                }

                Text("settings.pinStyle", comment: "Records on the map")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Colors.onDarkText)
                    .padding(.top, DS.Spacing.s)
                HStack(spacing: DS.Spacing.s) {
                    ForEach(PinStyle.allCases) { style in
                        SettingsChoiceTile(title: style.localizedName,
                                           isSelected: settings.pinStyle == style,
                                           action: { settings.pinStyle = style }) {
                            PinStylePreview(style: style)
                        }
                    }
                }
            }
            .padding(DS.Spacing.m)

            SettingsStyle.divider.frame(height: 1)

            SettingsToggleRow(icon: "slider.vertical.3", color: Color(red: 0.95, green: 0.6, blue: 0.2),
                              title: Text("settings.timeline", comment: "Timeline"),
                              subtitle: Text("settings.timeline.footer", comment: "What the timeline does"),
                              showsDivider: false,
                              isOn: $settings.timelineEnabled)
        }
    }

    // MARK: - Reminders

    private var remindersCard: some View {
        @Bindable var settings = environment.settings

        return SettingsCard(Text("settings.section.notifications", comment: "Section: notifications"),
                            footer: Text("settings.onThisDay.footer", comment: "Explanation of reminders")) {
            SettingsToggleRow(icon: "calendar", color: DS.Colors.accent,
                              title: Text("settings.onThisDay", comment: "\"On this day\" notifications"),
                              isOn: $settings.onThisDayEnabled)

            if settings.onThisDayEnabled {
                SettingsRow(icon: "clock", color: Color(red: 0.72, green: 0.42, blue: 0.95),
                            title: Text("settings.onThisDayHour", comment: "Notification time")) {
                    Menu {
                        Picker(selection: $settings.onThisDayHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(verbatim: String(format: "%02d:00", hour)).tag(hour)
                            }
                        } label: {
                            EmptyView()
                        }
                    } label: {
                        Text(verbatim: String(format: "%02d:00", settings.onThisDayHour))
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SettingsStyle.tint)
                    }
                }
            }

            if notificationsDenied {
                Text("settings.notificationsDenied", comment: "Notifications are disabled in the system")
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.onDarkSecondary)
                    .padding(DS.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsToggleRow(icon: "location.fill", color: Color(red: 0.45, green: 0.85, blue: 0.38),
                              title: Text("settings.geofences", comment: "Reminders on location"),
                              subtitle: Text("settings.geofences.footer", comment: "How on-location reminders work"),
                              showsDivider: settings.geofencesEnabled || isTogglingGeofences
                                  || environment.geofences.lastError != nil,
                              isOn: $settings.geofencesEnabled)

            if isTogglingGeofences {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("settings.geofences.enabling", comment: "Turning on reminders")
                        .font(.footnote)
                        .foregroundStyle(DS.Colors.onDarkSecondary)
                }
                .padding(DS.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if settings.geofencesEnabled {
                SettingsRow(icon: "hourglass", color: Color(red: 0.45, green: 0.5, blue: 0.62),
                            title: Text("settings.geofenceCooldown", comment: "Reminder cooldown"),
                            showsDivider: environment.geofences.lastError != nil) {
                    Stepper(value: $settings.geofenceCooldownDays, in: 0...90) {
                        Text(String(localized: "settings.geofenceCooldown.value",
                                    defaultValue: "\(settings.geofenceCooldownDays) d"))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(DS.Colors.onDarkSecondary)
                    }
                    .fixedSize()
                }
            }

            // The reason is shown also when the toggle turned itself off — otherwise
            // a denied permission would look like "the button doesn't work".
            if let error = environment.geofences.lastError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(DS.Colors.onDarkSecondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: url) {
                            Text("settings.geofences.openSystemSettings", comment: "Open system settings")
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                .padding(DS.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: settings.onThisDayEnabled) { _, _ in Task { await refreshSchedule() } }
        .onChange(of: settings.onThisDayHour) { _, _ in Task { await refreshSchedule() } }
        .onChange(of: settings.geofencesEnabled) { _, newValue in
            Task { await applyGeofenceToggle(newValue) }
        }
    }

    // MARK: - Music

    private var musicCard: some View {
        SettingsCard(Text("settings.section.sources", comment: "Section: music sources"),
                     footer: historySummary.playCount > 0
                        ? Text(verbatim: historyDescription)
                        : Text("settings.sources.footer", comment: "History stays on the device")) {
            Button {
                isShowingFileImporter = true
            } label: {
                SettingsRow(icon: "square.and.arrow.down.fill", color: Color(red: 0.2, green: 0.8, blue: 0.45),
                            title: Text("settings.history.import", comment: "Import Spotify history")) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Colors.onDarkSecondary)
                }
            }
            .buttonStyle(.plain)

            SettingsRow(icon: "waveform", color: Color(red: 0.85, green: 0.15, blue: 0.2),
                        title: Text(verbatim: MusicSourceKind.lastFm.localizedName),
                        showsDivider: historySummary.playCount > 0) {
                Group {
                    if isLastFmConnected {
                        Text("settings.source.connected", comment: "Connected")
                            .foregroundStyle(SettingsStyle.tint)
                    } else {
                        Text("settings.source.notConnected", comment: "Not connected")
                            .foregroundStyle(DS.Colors.onDarkSecondary)
                    }
                }
                .font(.subheadline)
            }

            if historySummary.playCount > 0 {
                Button(role: .destructive) {
                    Task { await clearHistory() }
                } label: {
                    SettingsRow(icon: "trash.fill", color: Color(red: 0.78, green: 0.1, blue: 0.14),
                                title: Text("settings.history.clear", comment: "Delete imported history"),
                                showsDivider: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Memories

    private var memoriesCard: some View {
        @Bindable var settings = environment.settings

        return SettingsCard(Text("settings.section.memories", comment: "Section: memory recovery"),
                            footer: Text("settings.matchWindow.footer", comment: "Explanation of the ± window")) {
            Button {
                isShowingScan = true
            } label: {
                SettingsRow(icon: "sparkle.magnifyingglass", color: Color(red: 0.95, green: 0.6, blue: 0.2),
                            title: Text("settings.rescan", comment: "Find memories"),
                            subtitle: Text("settings.rescan.footer", comment: "Explanation of rescanning")) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Colors.onDarkSecondary)
                }
            }
            .buttonStyle(.plain)

            SettingsRow(icon: "timer", color: Color(red: 0.25, green: 0.55, blue: 0.98),
                        title: Text("settings.matchWindow", comment: "Matching window"),
                        showsDivider: false) {
                Stepper(value: $settings.photoMatchWindowMinutes, in: 5...180, step: 5) {
                    Text(String(localized: "settings.matchWindow.value",
                                defaultValue: "±\(settings.photoMatchWindowMinutes) min"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(DS.Colors.onDarkSecondary)
                }
                .fixedSize()
            }
        }
    }

    // MARK: - Promo code

    private var promoCard: some View {
        SettingsCard(Text("settings.section.promo", comment: "Section: promo code"),
                     footer: promoFooter) {
            HStack(spacing: DS.Spacing.m) {
                SettingsIcon(systemName: "ticket.fill", color: Color(red: 0.93, green: 0.35, blue: 0.6))
                TextField(text: $promoCode) {
                    Text("settings.promo.placeholder", comment: "Enter a promo code")
                }
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .foregroundStyle(DS.Colors.onDarkText)
                .submitLabel(.done)
                .onSubmit(redeemPromo)

                Button(action: redeemPromo) {
                    Text("settings.promo.apply", comment: "Apply")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, DS.Spacing.m)
                        .frame(minHeight: 34)
                        .background(promoCode.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.white.opacity(0.2) : SettingsStyle.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(promoCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, 12)
        }
        .animation(.smooth(duration: 0.25), value: promoMessage)
    }

    private var promoFooter: Text? {
        switch promoMessage {
        case .applied: Text("settings.promo.applied", comment: "Promo code applied — all skins unlocked")
        case .unknown: Text("settings.promo.unknown", comment: "No such promo code")
        case nil: environment.settings.allSkinsUnlocked
            ? Text("settings.promo.applied", comment: "Promo code applied — all skins unlocked")
            : nil
        }
    }

    private func redeemPromo() {
        guard !promoCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if environment.settings.redeem(promoCode) != nil {
            Haptics.success()
            promoMessage = .applied
            promoCode = ""
        } else {
            Haptics.warning()
            promoMessage = .unknown
        }
    }

    private var privacyNote: some View {
        Label {
            Text("settings.privacy", comment: "Data stays on the phone")
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(SettingsStyle.tint)
        }
        .font(.footnote)
        .foregroundStyle(DS.Colors.onDarkSecondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    /// "From your history: 1,234 songs, 2016–2024" — clearer than a bare play count.
    private var historyDescription: String {
        let count = historySummary.playCount
        if let interval = historySummary.coveredInterval {
            return String(localized: "settings.history.summary",
                          defaultValue: "Plays in your history: \(count) (\(yearRange(interval))). We use them to find your memories.")
        }
        return String(localized: "settings.history.summaryNoPeriod",
                      defaultValue: "Plays in your history: \(count). We use them to find your memories.")
    }

    private func yearRange(_ interval: DateInterval) -> String {
        "\(interval.start.formatted(.dateTime.year())) – \(interval.end.formatted(.dateTime.year()))"
    }

    private func reload() async {
        scheduledCount = await environment.notifications.scheduledOnThisDayCount()
        notificationsDenied = await !environment.notifications.isAuthorized
        await reloadHistory()
    }

    private func reloadHistory() async {
        historySummary = await PlayHistoryStore.shared.summary()
        isLastFmConnected = await environment.lastFm.isConnected
    }

    /// Turning on geofences requests "always" access in context — only here.
    private func applyGeofenceToggle(_ isOn: Bool) async {
        isTogglingGeofences = true
        defer { isTogglingGeofences = false }

        if isOn {
            _ = await environment.geofences.enable()
        } else {
            await environment.geofences.disable()
        }
    }

    private func clearHistory() async {
        try? await environment.spotifyImporter.discardImportedHistory()
        await reloadHistory()
    }

    private func refreshSchedule() async {
        await environment.refreshOnThisDaySchedule()
        scheduledCount = await environment.notifications.scheduledOnThisDayCount()
        notificationsDenied = await !environment.notifications.isAuthorized
    }
}

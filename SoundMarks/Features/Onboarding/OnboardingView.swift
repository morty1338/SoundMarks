import SwiftUI
import UniformTypeIdentifiers

/// First screen after install: explanation, connecting history,
/// photo access, choosing a period and scanning.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var model: OnboardingViewModel?
    @State private var isShowingSpotifyPage = false
    @State private var isShowingFileImporter = false

    /// Called when the user confirmed candidates — the map re-reads places.
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model?.finish()
                        onFinish()
                        dismiss()
                    } label: {
                        Text(model?.step == .candidates
                             ? "common.done"
                             : "onboarding.skip")
                    }
                }
            }
        }
        .task {
            guard model == nil else { return }
            let created = OnboardingViewModel(environment: environment)
            model = created
            await created.refresh()
            await created.loadAvailableYears()
        }
        .sheet(isPresented: $isShowingSpotifyPage) {
            if let url = URL(string: "https://www.spotify.com/account/privacy/") {
                SafariView(url: url).ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $isShowingFileImporter,
                      allowedContentTypes: [.zip, .json],
                      allowsMultipleSelection: false) { result in
            guard let model else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.importArchive(at: url) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
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

    // MARK: - Steps

    @ViewBuilder
    private func content(_ model: OnboardingViewModel) -> some View {
        switch model.step {
        case .intro: intro(model)
        case .source: source(model)
        case .photos: photos(model)
        case .period: period(model)
        case .scanning: scanning(model)
        case .candidates: candidates(model)
        }
    }

    private func intro(_ model: OnboardingViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "map")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("onboarding.intro.title", comment: "First screen title")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("onboarding.intro.body", comment: "Explanation on the first screen")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Label {
                Text("onboarding.intro.privacy", comment: "Everything is processed on the phone")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .multilineTextAlignment(.center)

            Spacer()

            primaryButton(titleKey: "onboarding.intro.start") { model.advance() }
        }
        .padding(.bottom, 24)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func source(_ model: OnboardingViewModel) -> some View {
        Form {
            Section {
                Text("onboarding.source.spotify.steps", comment: "Spotify export instructions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    isShowingSpotifyPage = true
                } label: {
                    Label {
                        Text("onboarding.source.spotify.open", comment: "Open the Spotify privacy page")
                    } icon: {
                        Image(systemName: "safari")
                    }
                }

                Button {
                    isShowingFileImporter = true
                } label: {
                    Label {
                        Text("onboarding.source.spotify.import", comment: "Import the archive")
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(model.isImporting)

                if model.isImporting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("onboarding.source.importing", comment: "Parsing the archive")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("onboarding.source.spotify", comment: "Spotify section")
            } footer: {
                Text("onboarding.source.spotify.warning", comment: "The archive can take up to several weeks")
            }

            Section {
                if model.isLastFmAvailable {
                    if model.isLastFmConnected {
                        Button(role: .destructive) {
                            Task { await model.disconnectLastFm() }
                        } label: {
                            Text("onboarding.source.lastFm.disconnect", comment: "Disconnect Last.fm")
                        }
                    } else {
                        TextField(text: Binding(get: { model.lastFmUsername },
                                                set: { model.lastFmUsername = $0 })) {
                            Text("onboarding.source.lastFm.username", comment: "Last.fm username")
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            Task { await model.connectLastFm() }
                        } label: {
                            if model.isConnectingLastFm {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("onboarding.source.lastFm.connecting", comment: "Fetching history")
                                }
                            } else {
                                Text("onboarding.source.lastFm.connect", comment: "Connect Last.fm")
                            }
                        }
                        .disabled(model.lastFmUsername.isEmpty || model.isConnectingLastFm)
                    }
                } else {
                    Text("onboarding.source.lastFm.unavailable", comment: "Last.fm is not configured in this build")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("onboarding.source.lastFm", comment: "Last.fm section")
            } footer: {
                Text("onboarding.source.lastFm.hint", comment: "Last.fm — quick start")
            }

            if model.hasHistory {
                Section {
                    LabeledContent {
                        Text(model.historySummary.playCount, format: .number)
                    } label: {
                        Text("onboarding.source.playCount", comment: "Plays in history")
                    }
                    if let interval = model.historySummary.coveredInterval {
                        LabeledContent {
                            Text(interval.start.formatted(.dateTime.year())
                                 + " – "
                                 + interval.end.formatted(.dateTime.year()))
                        } label: {
                            Text("onboarding.source.period", comment: "History period")
                        }
                    }
                }
            }

            Section {
                primaryButton(titleKey: model.hasHistory ? "common.continue" : "onboarding.source.later") {
                    model.advance()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text("onboarding.source.title", comment: "Source step title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func photos(_ model: OnboardingViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("onboarding.photos.title", comment: "Photos step title")
                    .font(.title2.weight(.semibold))
                Text("onboarding.photos.body", comment: "Why photo access is needed")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            if model.photoAuthorization == .limited {
                Text("onboarding.photos.limited", comment: "Limited access is supported")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            if model.photoAuthorization.allowsReading {
                primaryButton(titleKey: "common.continue") { model.advance() }
            } else {
                primaryButton(titleKey: "onboarding.photos.allow") {
                    Task { await model.requestPhotoAccess() }
                }
                Button {
                    model.advance()
                } label: {
                    Text("onboarding.photos.later", comment: "Not now")
                }
                .font(.footnote)
            }
        }
        .padding(.bottom, 24)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func period(_ model: OnboardingViewModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text("onboarding.period.title", comment: "Period selection title")
                    .font(.title2.weight(.semibold))
                Text("onboarding.period.body", comment: "Why it is better to start with one year")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ScrollView {
                YearChips(years: model.availableYears, selection: $model.selectedYears)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 10) {
                primaryButton(titleKey: "onboarding.period.scan") { model.startScan() }
                    .disabled(model.selectedYears.isEmpty)

                // "Scan everything" is deliberately secondary: a full pass takes long.
                Button {
                    model.selectAllYears()
                    model.startScan()
                } label: {
                    Text("onboarding.period.scanAll", comment: "Scan all years")
                }
                .font(.footnote)
                .disabled(model.availableYears.isEmpty)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle(Text("onboarding.period.navTitle", comment: "Period"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scanning(_ model: OnboardingViewModel) -> some View {
        VStack(spacing: 22) {
            Spacer()

            ProgressView(value: model.scanner.progress) {
                Text(scanPhaseTitle(model.scanner.phase))
                    .font(.headline)
            } currentValueLabel: {
                Text(model.scanner.inspectedPhotoCount, format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .progressViewStyle(.linear)
            .padding(.horizontal, 32)

            if case .failed(let message) = model.scanner.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            if model.scanner.isRunning {
                Button(role: .destructive) {
                    model.cancelScan()
                } label: {
                    Text("common.cancel", comment: "Cancel")
                }
            } else {
                primaryButton(titleKey: "onboarding.scan.showResults") { model.advance() }
            }
        }
        .padding(.bottom, 24)
        .navigationTitle(Text("onboarding.scan.navTitle", comment: "Scanning"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.scanner.phase) { _, phase in
            // As soon as scanning is finished — show the feed right away.
            if phase == .finished { model.advance() }
        }
    }

    private func candidates(_ model: OnboardingViewModel) -> some View {
        CandidateFeedView(scanner: model.scanner) {
            model.finish()
            onFinish()
            dismiss()
        }
    }

    // MARK: - Shared

    private func primaryButton(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 24)
    }

    private func scanPhaseTitle(_ phase: MemoryScanner.Phase) -> LocalizedStringKey {
        switch phase {
        case .syncingHistory: "onboarding.scan.history"
        case .readingPhotos: "onboarding.scan.photos"
        case .matching: "onboarding.scan.matching"
        case .finished: "onboarding.scan.finished"
        case .cancelled: "onboarding.scan.cancelled"
        case .failed: "onboarding.scan.failed"
        case .idle: "onboarding.scan.idle"
        }
    }
}

/// Year chips — the main way to set the period.
struct YearChips: View {
    let years: [Int]
    @Binding var selection: Set<Int>

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 10)]

    var body: some View {
        if years.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("onboarding.period.noYears", comment: "No years to scan")
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                }
            } description: {
                Text("onboarding.period.noYears.body", comment: "Why there are no years")
            }
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(years, id: \.self) { year in
                    let isSelected = selection.contains(year)
                    Button {
                        if isSelected { selection.remove(year) } else { selection.insert(year) }
                    } label: {
                        Text(String(year))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                in: Capsule())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }
}

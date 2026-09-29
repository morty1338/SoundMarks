import CoreData
import SwiftUI

/// Friends screen (the "F" button on the planet) — in the strict profile style.
///
/// My code and QR, adding a nearby friend (QR scan or typing the code),
/// incoming requests, the friends list and sending an update as a file.
struct FriendsScreen: View {
    @Environment(AppEnvironment.self) private var environment

    /// Show the planet on the home screen.
    let onShowPlanet: (PlanetPage) -> Void
    let onDataChanged: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ProfileStyle.background.ignoresSafeArea()
                if environment.profiles.me != nil {
                    FriendsListView(onShowPlanet: onShowPlanet, onDataChanged: onDataChanged)
                } else {
                    ProfileSetupView()
                }
            }
            .navigationTitle(Text("friends.title", comment: "Friends screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(DS.Colors.marks)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
    }
}

/// File for the share sheet.
struct ExportedFile: Identifiable {
    let id = UUID()
    let urls: [URL]

    init(url: URL) { urls = [url] }
    init(urls: [URL]) { self.urls = urls }
}

private struct FriendsListView: View {
    @Environment(AppEnvironment.self) private var environment

    let onShowPlanet: (PlanetPage) -> Void
    let onDataChanged: () -> Void

    @State private var manualCode = ""
    @State private var isShowingScanner = false
    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let me = environment.profiles.me {
                    myCard(me)
                }
                if let request = environment.nearby.incomingRequest {
                    incomingSection(request)
                }
                addFriendSection
                friendsSection
                if let summary = environment.nearby.lastSyncSummary {
                    VStack(spacing: 10) {
                        ProfileStyle.caption(Text("friends.lastSync", comment: "Last nearby exchange"))
                        ProfilePanel {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: summary.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text(verbatim: summary.details)
                                    .font(.caption)
                                    .foregroundStyle(ProfileStyle.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.vertical, DS.Spacing.m)
        }
        .scrollIndicators(.hidden)
        .onAppear { environment.nearby.start() }
        .onChange(of: environment.nearby.lastSyncSummary) { _, _ in onDataChanged() }
        .sheet(isPresented: $isShowingScanner) {
            QRScannerSheet { code in
                isShowingScanner = false
                environment.nearby.requestFriend(code: code)
            }
        }
        .sheet(item: $exportedFile) { file in
            ActivityView(items: file.urls)
        }
        .alert(Text("root.error.title", comment: "Error title"),
               isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(role: .cancel) { exportError = nil } label: { Text("common.ok", comment: "OK") }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - My code

    private func myCard(_ me: Profile) -> some View {
        VStack(spacing: 10) {
            ProfileStyle.caption(Text("friends.myCode", comment: "My code"))
            ProfilePanel {
                VStack(spacing: 16) {
                    QRCodeImage(payload: FriendCode.qrPayload(for: me.uniqueCode ?? ""))
                        .frame(width: 170, height: 170)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(Text("friends.qr.accessibility", comment: "QR code with my code"))

                    Text(verbatim: formattedCode(me.uniqueCode ?? ""))
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .accessibilityLabel(Text(verbatim: (me.uniqueCode ?? "").map(String.init).joined(separator: " ")))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                ProfileStyle.hairline.frame(height: 1)

                Button(action: exportPlanet) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 22)
                        Text("friends.sendUpdate", comment: "Send my planet update as a file")
                            .font(.subheadline)
                        Spacer()
                        if isExporting { ProgressView() }
                    }
                    .foregroundStyle(me.planetVisible ? .white : ProfileStyle.tertiary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isExporting || !me.planetVisible)
            }
            Text(me.planetVisible
                 ? String(localized: "friends.sendUpdate.footer",
                          defaultValue: "Send the file with your planet via AirDrop or a messenger. Your friend opens it in SoundMarks.")
                 : String(localized: "friends.planetHidden.footer",
                          defaultValue: "Your planet is hidden from friends. You can turn it on in Settings."))
                .font(.caption)
                .foregroundStyle(ProfileStyle.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formattedCode(_ code: String) -> String {
        guard code.count == FriendCode.length else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }

    // MARK: - Add friend

    private var addFriendSection: some View {
        VStack(spacing: 10) {
            ProfileStyle.caption(Text("friends.add", comment: "Add friend"))
            ProfilePanel {
                if QRScannerView.isAvailable {
                    ProfileActionRow(icon: "qrcode.viewfinder",
                                     title: Text("friends.scan", comment: "Scan friend's QR")) {
                        Haptics.tap()
                        isShowingScanner = true
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "number")
                        .frame(width: 22)
                        .foregroundStyle(.white)
                    TextField(text: $manualCode) {
                        Text("friends.code.placeholder", comment: "Friend's code")
                    }
                    .font(.body.monospaced())
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(addByCode)

                    Button(action: addByCode) {
                        Text("friends.code.add", comment: "Add by code")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FriendCode.isValid(manualCode) ? DS.Colors.marks : ProfileStyle.tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!FriendCode.isValid(manualCode))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)

                addStateRow
            }
            Text("friends.add.footer", comment: "How to add a nearby friend")
                .font(.caption)
                .foregroundStyle(ProfileStyle.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var addStateRow: some View {
        let state = environment.nearby.addState
        if state != .idle {
            ProfileStyle.hairline.frame(height: 1)
            HStack(spacing: 12) {
                switch state {
                case .idle:
                    EmptyView()
                case .searching(let code):
                    ProgressView()
                    Text("friends.state.searching \(code)", comment: "Looking for the friend's device nearby")
                    Spacer()
                    cancelButton
                case .waitingForConfirmation(_, let nickname):
                    ProgressView()
                    Text("friends.state.waiting \(nickname)", comment: "Waiting for the friend to confirm")
                    Spacer()
                    cancelButton
                case .added(let nickname):
                    Image(systemName: "checkmark.circle").foregroundStyle(DS.Colors.marks)
                    Text("friends.state.added \(nickname)", comment: "Friend added")
                case .failed(let message):
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
                    Text(verbatim: message)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cancelButton: some View {
        Button {
            environment.nearby.cancelAdding()
        } label: {
            Text("common.cancel", comment: "Cancel")
                .foregroundStyle(ProfileStyle.secondary)
        }
        .buttonStyle(.plain)
    }

    private func addByCode() {
        guard FriendCode.isValid(manualCode) else { return }
        Haptics.tap()
        environment.nearby.requestFriend(code: manualCode)
        manualCode = ""
    }

    // MARK: - Incoming

    private func incomingSection(_ request: NearbyService.IncomingRequest) -> some View {
        VStack(spacing: 10) {
            ProfileStyle.caption(Text("friends.requests", comment: "Incoming requests"))
            ProfilePanel {
                HStack(spacing: 12) {
                    AvatarView(nickname: request.profile.nickname, colorHex: request.profile.avatarColorHex,
                               imageData: nil, size: 40)
                    Text(verbatim: request.profile.nickname)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        environment.nearby.respond(accept: false)
                    } label: {
                        Text("friends.request.decline", comment: "Decline")
                            .font(.subheadline)
                            .foregroundStyle(ProfileStyle.secondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.success()
                        environment.nearby.respond(accept: true)
                    } label: {
                        Text("friends.request.accept", comment: "Accept")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(DS.Colors.marks, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(spacing: 10) {
            ProfileStyle.caption(Text("friends.list", comment: "Friends list"))
            ProfilePanel {
                if environment.profiles.friends.isEmpty {
                    Text("friends.empty", comment: "No friends yet")
                        .font(.subheadline)
                        .foregroundStyle(ProfileStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(Array(environment.profiles.friends.enumerated()), id: \.element.id) { index, friend in
                    if index > 0 {
                        ProfileStyle.hairline.frame(height: 1).padding(.leading, 66)
                    }
                    NavigationLink {
                        FriendProfileView(friend: friend, onShowPlanet: onShowPlanet, onDataChanged: onDataChanged)
                    } label: {
                        friendRow(friend)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func friendRow(_ friend: Profile) -> some View {
        let rank = RankLadder.rank(forPlaceCount: placeCount(of: friend))
        return HStack(spacing: 12) {
            AvatarView(profile: friend, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: friend.nickname ?? "")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(verbatim: rank.title)
                        .font(.system(size: 11, weight: .semibold, design: .serif).smallCaps())
                        .tracking(1)
                        .foregroundStyle(DS.Colors.marks)
                    Text(verbatim: "·")
                    Text(verbatim: friend.lastSyncedAt.map(SyncText.synced) ?? SyncText.neverSynced)
                }
                .font(.caption)
                .foregroundStyle(ProfileStyle.tertiary)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProfileStyle.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// How many places a friend has on their planets that I have.
    private func placeCount(of friend: Profile) -> Int {
        guard let id = friend.id else { return 0 }
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "isTombstoned == NO AND map.kindRaw == %@ AND map.ownerProfileId == %@",
                                        MemoryMapKind.friend.rawValue, id as CVarArg)
        return (try? environment.persistence.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Export

    private func exportPlanet() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                // Each of my planets as a separate file.
                let snapshots = try await environment.sync.planetSnapshots()
                exportedFile = ExportedFile(urls: try snapshots.map(environment.sync.exportFile))
            } catch let error as SyncService.Failure {
                exportError = error.errorDescription
            } catch {
                exportError = String(localized: "friends.export.failed",
                                     defaultValue: "Couldn't create the file. Please try again.")
            }
        }
    }
}

/// "Synced 3 days ago".
enum SyncText {
    static func synced(_ date: Date) -> String {
        let relative = date.formatted(.relative(presentation: .named))
        return String(localized: "friends.syncedAgo", defaultValue: "Updated \(relative)")
    }

    static var neverSynced: String {
        String(localized: "friends.neverSynced", defaultValue: "No maps exchanged yet")
    }
}

/// Sheet with the QR scanner.
private struct QRScannerSheet: View {
    let onCode: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            QRScannerView(onCode: onCode)
                .ignoresSafeArea()
            Text("friends.scan.hint", comment: "Point the camera at the friend's QR code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule())
                .padding(.bottom, DS.Spacing.xl)
        }
        .presentationDragIndicator(.visible)
    }
}

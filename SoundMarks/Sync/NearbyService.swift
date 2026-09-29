import Foundation
import MultipeerConnectivity
import Observation

/// Wrapper for passing non-Sendable MultipeerConnectivity objects to the main actor.
/// MC callbacks arrive on their own queues; we touch the objects themselves only on the main one.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}

/// Nearby friends: MultipeerConnectivity without a server.
///
/// - Adding: I scan a friend's QR (or type the code) → find their device →
///   send a request → they confirm on their side → both save each other.
/// - Sync: when friends are nearby and the app is open, the sides exchange
///   changes of their planets (if visibility is on) and shared maps.
@MainActor
@Observable
final class NearbyService: NSObject {
    enum AddState: Equatable {
        case idle
        /// Looking for a device with this code nearby.
        case searching(code: String)
        /// Request sent, waiting for the friend to confirm.
        case waitingForConfirmation(code: String, nickname: String)
        case added(nickname: String)
        case failed(String)
    }

    /// Incoming friend request — shown to the user for confirmation.
    struct IncomingRequest: Identifiable, Equatable {
        let id = UUID()
        let profile: ProfileDTO
    }

    private(set) var addState: AddState = .idle
    private(set) var incomingRequest: IncomingRequest?
    /// The last sync result — for a short notice in the interface.
    private(set) var lastSyncSummary: SyncSummary?

    static let serviceType = "soundmap"

    @ObservationIgnored private let profiles: ProfileStore
    @ObservationIgnored private let sync: SyncService

    @ObservationIgnored private var peerID: MCPeerID?
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var pendingInvitation: ((Bool, MCSession?) -> Void)?
    /// Who we're currently talking to and why.
    @ObservationIgnored private var purposeByPeer: [MCPeerID: Purpose] = [:]
    @ObservationIgnored private var lastAutoSync: [String: Date] = [:]
    /// Friend codes per device: from the nearby advertisement or from an invitation.
    @ObservationIgnored private var codeByPeer: [MCPeerID: String] = [:]

    private enum Purpose: String, Codable {
        case friend
        case sync
    }

    private struct InvitationContext: Codable {
        let purpose: Purpose
        let profile: ProfileDTO
    }

    private enum Message: Codable {
        case friendAccepted(ProfileDTO)
        case friendDeclined
        /// We're already connected — send our own changes in reply.
        case syncRequest
        case snapshot(Data)
        case done
    }

    /// How long to wait for the friend to confirm the request on their side.
    private static let invitationTimeout: TimeInterval = 120

    init(profiles: ProfileStore, sync: SyncService) {
        self.profiles = profiles
        self.sync = sync
        super.init()
    }

    // MARK: - Lifecycle

    /// Turns on visibility for nearby friends. Does nothing without a profile.
    func start() {
        guard advertiser == nil, let me = profiles.me, let code = me.uniqueCode else { return }

        let peer = MCPeerID(displayName: me.nickname?.nilIfEmpty ?? code)
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        let advertiser = MCNearbyServiceAdvertiser(peer: peer,
                                                   discoveryInfo: ["code": code],
                                                   serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()

        self.peerID = peer
        self.session = session
        self.advertiser = advertiser
        self.browser = browser
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        peerID = nil
        purposeByPeer.removeAll()
        codeByPeer.removeAll()
        discoveredPeers.removeAll()
    }

    // MARK: - Adding a friend

    /// A code from the QR or typed by hand. Then we wait for the friend's device to show up nearby.
    func requestFriend(code: String) {
        let normalized = FriendCode.normalized(code)
        guard FriendCode.isValid(normalized) else {
            addState = .failed(String(localized: "friends.error.badCode", defaultValue: "This doesn't look like a friend code."))
            return
        }
        guard normalized != profiles.me?.uniqueCode else {
            addState = .failed(String(localized: "friends.error.ownCode", defaultValue: "That's your own code."))
            return
        }
        // The friend already sent a request while I was scanning their code — just accept.
        if incomingRequest?.profile.uniqueCode == normalized {
            respond(accept: true)
            return
        }
        start()
        addState = .searching(code: normalized)
        // The friend's device may have been found before scanning — the system won't
        // report "found" again, so we invite right away.
        if let peer = discoveredPeers[normalized] {
            sendFriendRequest(to: peer, code: normalized)
        }
    }

    private func sendFriendRequest(to peer: MCPeerID, code: String) {
        addState = .waitingForConfirmation(code: code, nickname: peer.displayName)
        invite(peer, purpose: .friend)
    }



    func cancelAdding() {
        addState = .idle
    }

    /// Answer to an incoming friend request.
    func respond(accept: Bool) {
        guard let request = incomingRequest else { return }
        incomingRequest = nil

        if accept {
            try? profiles.upsert(request.profile, status: .friend)
            addState = .added(nickname: request.profile.nickname)
            pendingInvitation?(true, session)
        } else {
            pendingInvitation?(false, nil)
        }
        pendingInvitation = nil
    }

    // MARK: - Sync

    /// Exchange with a friend if they're nearby.
    /// - Returns: `false` if the friend's device isn't visible right now.
    @discardableResult
    func syncNow(with friend: Profile) -> Bool {
        guard let code = friend.uniqueCode else { return false }
        start()
        guard let peer = discoveredPeers[code] else { return false }
        lastAutoSync[code] = Date()
        invite(peer, purpose: .sync)
        return true
    }

    /// Planet visibility changed — tell all nearby friends right away.
    func resyncAll() {
        for friend in profiles.friends {
            syncNow(with: friend)
        }
    }

    @ObservationIgnored private var discoveredPeers: [String: MCPeerID] = [:]

    private func invite(_ peer: MCPeerID, purpose: Purpose) {
        guard let browser, let session, let me = profiles.me, let dto = profiles.dto(for: me),
              let context = try? JSONEncoder.soundmap.encode(InvitationContext(purpose: purpose, profile: dto))
        else { return }
        purposeByPeer[peer] = purpose

        // Already connected (e.g. right after becoming friends) — another invitation
        // won't help: just exchange changes over the open session.
        if purpose == .sync, session.connectedPeers.contains(peer) {
            send(.syncRequest, to: peer)
            Task { await sendSnapshots(to: peer) }
            return
        }
        browser.invitePeer(peer, to: session, withContext: context, timeout: Self.invitationTimeout)
    }

    private func handleFound(peer: MCPeerID, code: String) {
        discoveredPeers[code] = peer
        codeByPeer[peer] = code

        // Looking for a specific person to befriend.
        if case .searching(let wanted) = addState, wanted == code {
            sendFriendRequest(to: peer, code: code)
            return
        }

        // A known friend nearby — sync, but no more than once every five minutes.
        guard let friend = profiles.profile(code: code), let friendID = friend.id,
              profiles.trustedFriend(id: friendID) != nil,
              let myCode = profiles.me?.uniqueCode
        else { return }
        if let last = lastAutoSync[code], Date().timeIntervalSince(last) < 300 { return }
        lastAutoSync[code] = Date()
        // Only one side invites — the one with the smaller code, otherwise there are two crossing invitations.
        if myCode < code { invite(peer, purpose: .sync) }
    }

    private func handleInvitation(from peer: MCPeerID, context: Data?,
                                  handler: @escaping (Bool, MCSession?) -> Void) {
        guard let context,
              let invitation = try? JSONDecoder.soundmap.decode(InvitationContext.self, from: context)
        else {
            handler(false, nil)
            return
        }
        let sender = invitation.profile
        codeByPeer[peer] = sender.uniqueCode

        switch invitation.purpose {
        case .friend:
            let existing = profiles.profile(id: sender.id)
            let decision = FriendHandshake.decide(senderCode: sender.uniqueCode,
                                                  myCode: profiles.me?.uniqueCode ?? "",
                                                  state: addState,
                                                  isBlocked: existing?.isBlocked == true,
                                                  isFriend: existing?.status == .friend)
            switch decision {
            case .decline:
                handler(false, nil)
            case .accept:
                try? profiles.upsert(sender, status: .friend)
                purposeByPeer[peer] = .friend
                addState = .added(nickname: sender.nickname)
                Haptics.success()
                handler(true, session)
            case .ask:
                // Show the request and wait for the user's decision.
                pendingInvitation?(false, nil)
                pendingInvitation = handler
                purposeByPeer[peer] = .friend
                incomingRequest = IncomingRequest(profile: sender)
            }

        case .sync:
            guard profiles.trustedFriend(id: sender.id) != nil else {
                handler(false, nil)
                return
            }
            purposeByPeer[peer] = .sync
            handler(true, session)
        }
    }

    private func handleConnected(peer: MCPeerID) {
        switch purposeByPeer[peer] {
        case .friend:
            // The inviting side waits for the answer — the accepting side sends the consent message.
            if let code = codeByPeer[peer], case .waitingForConfirmation(let wanted, _) = addState,
               wanted == code {
                return
            }
            if let me = profiles.me, let dto = profiles.dto(for: me) {
                send(.friendAccepted(dto), to: peer)
            }
            // Right after becoming friends we exchange planets.
            if let code = codeByPeer[peer] { lastAutoSync[code] = Date() }
            Task { await sendSnapshots(to: peer) }
        case .sync:
            Task { await sendSnapshots(to: peer) }
        case nil:
            break
        }
    }

    /// My planet (or a notice that it's hidden) and shared maps with this friend.
    private func sendSnapshots(to peer: MCPeerID) async {
        guard let code = codeByPeer[peer], let friend = profiles.profile(code: code), let friendID = friend.id,
              profiles.trustedFriend(id: friendID) != nil
        else { return }
        // Send changes since the last sync — with a margin in case a send was lost.
        let since = friend.lastSyncedAt?.addingTimeInterval(-3600)

        var snapshots: [(SoundmapManifest, [String: Data])] = []
        if profiles.me?.planetVisible == true {
            if let planets = try? await sync.planetSnapshots(since: since) { snapshots.append(contentsOf: planets) }
        } else if let notice = try? sync.hiddenPlanetNotice() {
            snapshots.append(notice)
        }
        for map in sync.sharedMaps() where map.participantIDs.contains(friendID) {
            guard let id = map.id, let shared = try? await sync.sharedMapSnapshot(mapID: id, since: since) else { continue }
            snapshots.append(shared)
        }

        for snapshot in snapshots {
            if let data = try? SoundmapFile.write(manifest: snapshot.0, files: snapshot.1) {
                send(.snapshot(data), to: peer)
            }
        }
        send(.done, to: peer)
    }

    private func handle(_ message: Message, from peer: MCPeerID) {
        switch message {
        case .friendAccepted(let profile):
            try? profiles.upsert(profile, status: .friend)
            addState = .added(nickname: profile.nickname)
            Haptics.success()
            lastAutoSync[profile.uniqueCode] = Date()
            Task { await sendSnapshots(to: peer) }

        case .friendDeclined:
            addState = .failed(String(localized: "friends.error.declined", defaultValue: "Request declined."))

        case .snapshot(let data):
            guard let (manifest, files) = try? SoundmapFile.read(data) else { return }
            if let summary = try? sync.apply(manifest, files: files) {
                lastSyncSummary = summary
            }

        case .syncRequest:
            Task { await sendSnapshots(to: peer) }

        case .done:
            break
        }
    }

    private func send(_ message: Message, to peer: MCPeerID) {
        guard let session, let data = try? JSONEncoder.soundmap.encode(message) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    private func handleLost(peer: MCPeerID) {
        guard let code = codeByPeer[peer], discoveredPeers[code] == peer else { return }
        discoveredPeers[code] = nil
    }

    private func handleDisconnected(peer: MCPeerID) {
        // A declined crossing invitation also arrives as "not connected" —
        // the live connection to the same device isn't touched.
        if session?.connectedPeers.contains(peer) == true { return }
        purposeByPeer[peer] = nil
        if let code = codeByPeer[peer], case .waitingForConfirmation(let wanted, _) = addState, wanted == code {
            addState = .failed(String(localized: "friends.error.lost",
                                      defaultValue: "Your friend didn't confirm, or the connection dropped."))
        }
    }
}

/// What to do with an incoming friend request. Separate from MultipeerConnectivity so it can be tested.
enum FriendHandshake {
    enum Decision: Equatable {
        case decline
        /// Accept without asking: I'm adding this person myself or they're already a friend.
        case accept
        /// Show the request to the user.
        case ask
    }

    static func decide(senderCode: String, myCode: String, state: NearbyService.AddState,
                       isBlocked: Bool, isFriend: Bool) -> Decision {
        if isBlocked { return .decline }

        switch state {
        case .waitingForConfirmation(let wanted, _) where wanted == senderCode:
            // Both scanned each other and the invitations cross.
            // The invitation from the smaller code wins, the other is declined —
            // otherwise both sides wait forever for each other to confirm.
            return myCode < senderCode ? .decline : .accept
        case .searching(let wanted) where wanted == senderCode:
            return .accept
        default:
            return isFriend ? .accept : .ask
        }
    }
}

// MARK: - MultipeerConnectivity delegates

extension NearbyService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let transfer = Unchecked(value: (peerID, invitationHandler))
        Task { @MainActor in
            self.handleInvitation(from: transfer.value.0, context: context, handler: transfer.value.1)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: any Error) {
        Log.ui.error("Visibility for nearby friends did not turn on: \(error.localizedDescription, privacy: .public)")
    }
}

extension NearbyService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        guard let code = info?["code"] else { return }
        let transfer = Unchecked(value: peerID)
        Task { @MainActor in self.handleFound(peer: transfer.value, code: code) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let transfer = Unchecked(value: peerID)
        Task { @MainActor in self.handleLost(peer: transfer.value) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        Log.ui.error("Nearby friend discovery did not start: \(error.localizedDescription, privacy: .public)")
    }
}

extension NearbyService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let transfer = Unchecked(value: peerID)
        Task { @MainActor in
            switch state {
            case .connected: self.handleConnected(peer: transfer.value)
            case .notConnected: self.handleDisconnected(peer: transfer.value)
            default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder.soundmap.decode(Message.self, from: data) else { return }
        let transfer = Unchecked(value: (peerID, message))
        Task { @MainActor in self.handle(transfer.value.1, from: transfer.value.0) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

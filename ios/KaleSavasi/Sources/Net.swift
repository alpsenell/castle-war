import Foundation
import GameKit
import MultipeerConnectivity
import UIKit

/// One message of the match protocol. Launch vectors travel as raw bit patterns so both
/// devices simulate from exactly the same doubles.
struct NetMessage: Codable {
    var t: String
    var nonce: UInt32? = nil
    var seed: UInt32? = nil
    var round: Int? = nil
    var first: Int? = nil
    var k: Int? = nil
    var p: [UInt64]? = nil
    var v: [UInt64]? = nil
    var yaw: Double? = nil
    var power: Double? = nil
    var mega: Bool? = nil
    // Sent with "hello": who the opponent is and how they rank.
    var name: String? = nil
    var trophies: Int? = nil
    var level: Int? = nil
    /// The sender's castle, in the flat form of `BrickDesign.encoded` (about 3.5 KB of JSON at 260 bricks).
    var design: [Int]? = nil
    /// Special shot used, as `Ammo.rawValue`.
    var ammo: Int? = nil
    /// Sent with "hello": the sender's `K.rulesVersion`. Missing means an older build.
    var rules: Int? = nil
    /// Four-castle matches: the seat a shot, aim or skip belongs to.
    var seat: Int? = nil
    /// Four-castle "start": who sits where. A nonce of 0 is a computer player run by the host.
    var seats: [SeatInfo]? = nil
    /// "settle": per castle, base64 of `CastleSnapshot.delta` from the poses before the shot.
    var data: [String]? = nil
    // Sent with "hello" from 2.1: the sender's shop cosmetics, by raw value. Older builds leave
    // them out and ignore them; unknown values fall back to the default look.
    var skin: String? = nil
    var trail: String? = nil
    var impact: String? = nil
    var gem: String? = nil
    var banner: String? = nil
    var supporter: Bool? = nil
}

struct SeatInfo: Codable, Equatable {
    var nonce: UInt32
    var name: String
    var level: Int
    var design: [Int]
    /// The player's shop cosmetics; missing from older builds.
    var look: Cosmetics? = nil
}

/// A two-player connection. All callbacks arrive on the main queue.
protocol MatchTransport: AnyObject {
    var onConnected: (() -> Void)? { get set }
    var onMessage: ((NetMessage) -> Void)? { get set }
    /// Everyone else has gone.
    var onDisconnected: (() -> Void)? { get set }
    /// Four-castle matches: how many other devices are connected now.
    var onPeers: ((Int) -> Void)? { get set }
    var peerCount: Int { get }
    /// Text for the lobby and whether work is still in progress.
    var onStatus: ((String, Bool) -> Void)? { get set }
    func start()
    func send(_ m: NetMessage, reliable: Bool)
    func stop()
}

private func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
}

// MARK: - Game Center (internet)

final class GameCenterTransport: NSObject, MatchTransport, GKMatchDelegate, GKMatchmakerViewControllerDelegate, GKLocalPlayerListener {
    var onConnected: (() -> Void)?
    var onMessage: ((NetMessage) -> Void)?
    var onDisconnected: (() -> Void)?
    var onPeers: ((Int) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    var peerCount: Int { match?.players.count ?? 0 }
    /// Most players in one match: 2 for a duel, 4 for a four-castle match.
    private let players: Int
    private var match: GKMatch?

    init(players: Int = 2) {
        self.players = players
        super.init()
    }
    private var live = false
    private var stopped = false

    func start() {
        let lp = GKLocalPlayer.local
        if lp.isAuthenticated { lp.register(self); findMatch(invite: nil); return }
        onStatus?(Tx.signingIn, true)
        lp.authenticateHandler = { [weak self] vc, error in
            guard let self, !self.stopped else { return }
            if let vc { Self.present(vc); return }
            if lp.isAuthenticated { lp.register(self); self.findMatch(invite: nil) }
            else { self.onStatus?(Tx.gameCenterUnavailable(error?.localizedDescription), false) }
        }
    }

    private func findMatch(invite: GKInvite?) {
        let vc: GKMatchmakerViewController?
        if let invite { vc = GKMatchmakerViewController(invite: invite) } else {
            let req = GKMatchRequest()
            req.minPlayers = 2
            req.maxPlayers = players
            vc = GKMatchmakerViewController(matchRequest: req)
        }
        guard let vc else { onStatus?(Tx.matchScreenFailed, false); return }
        vc.matchmakerDelegate = self
        onStatus?(Tx.searching, true)
        Self.present(vc)
    }

    static func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        top.present(vc, animated: true)
    }

    private func goLive() {
        guard !live else { return }
        live = true
        onMain { self.onConnected?() }
    }

    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true)
        onStatus?(Tx.matchCancelled, false)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        viewController.dismiss(animated: true)
        onStatus?(Tx.matchFailed(error.localizedDescription), false)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        viewController.dismiss(animated: true)
        self.match = match
        match.delegate = self
        if match.expectedPlayerCount == 0 { goLive() }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let left = match.players.count
        if state == .connected { if match.expectedPlayerCount == 0 { goLive() } }
        else if state == .disconnected {
            onMain {
                self.onPeers?(left)
                if left == 0 || self.players == 2 { self.onDisconnected?() }
            }
        }
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let m = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        onMain { self.onMessage?(m) }
    }

    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        onMain { self.findMatch(invite: invite) }
    }

    func send(_ m: NetMessage, reliable: Bool) {
        guard let match, let data = try? JSONEncoder().encode(m) else { return }
        try? match.sendData(toAllPlayers: data, with: reliable ? .reliable : .unreliable)
    }

    func stop() {
        stopped = true
        match?.delegate = nil
        match?.disconnect()
        match = nil
        GKLocalPlayer.local.unregisterListener(self)
    }
}

// MARK: - Nearby (same Wi-Fi or Bluetooth, no account)

final class NearbyTransport: NSObject, MatchTransport, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    /// A duel pairs two equal devices. In a four-castle match one device hosts and up to three join it;
    /// the joiners only talk to the host, which passes their messages on to everyone else.
    enum Role { case duel, host, join }

    var onConnected: (() -> Void)?
    var onMessage: ((NetMessage) -> Void)?
    var onDisconnected: (() -> Void)?
    var onPeers: ((Int) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    var peerCount: Int { session.connectedPeers.count }
    private static let service = "kale-savasi"
    private static let partyService = "kale-savasi4"
    private let role: Role
    private let me = MCPeerID(displayName: String(UUID().uuidString.prefix(8)))
    private lazy var session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
    private lazy var advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: role == .duel ? Self.service : Self.partyService)
    private lazy var browser = MCNearbyServiceBrowser(peer: me, serviceType: role == .duel ? Self.service : Self.partyService)
    private var live = false
    private var stopped = false
    /// A host stops letting players in once the match has started.
    private var open = true

    init(role: Role = .duel) {
        self.role = role
        super.init()
    }

    func start() {
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        if role != .join { advertiser.startAdvertisingPeer() }
        if role != .host { browser.startBrowsingForPeers() }
        onStatus?(role == .host ? Tx.hostWaiting : role == .join ? Tx.joinSearching : Tx.nearbySearching, true)
    }

    /// The host closes the door when the match starts.
    func close() {
        open = false
        advertiser.stopAdvertisingPeer()
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        if role == .join {
            guard session.connectedPeers.isEmpty else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
            return
        }
        // Only one side sends the invitation, so two devices never invite each other at once.
        guard session.connectedPeers.isEmpty, me.displayName < peerID.displayName else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onMain { self.onStatus?(Tx.localNetworkFailed(error.localizedDescription), false) }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let room = role == .host ? open && session.connectedPeers.count < 3 : session.connectedPeers.isEmpty
        invitationHandler(room, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onMain { self.onStatus?(Tx.localNetworkFailed(error.localizedDescription), false) }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onMain {
            guard !self.stopped else { return }
            let count = session.connectedPeers.count
            if self.role != .duel { self.onPeers?(count) }
            if state == .connected, !self.live {
                self.live = true
                if self.role != .host { self.advertiser.stopAdvertisingPeer() }
                self.browser.stopBrowsingForPeers()
                self.onConnected?()
            } else if state == .notConnected, self.live, count == 0 || self.role != .host {
                self.live = false
                self.onDisconnected?()
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let m = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        if role == .host {
            let others = session.connectedPeers.filter { $0 != peerID }
            if !others.isEmpty { try? session.send(data, toPeers: others, with: .reliable) }
        }
        onMain { if !self.stopped { self.onMessage?(m) } }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    func send(_ m: NetMessage, reliable: Bool) {
        guard !session.connectedPeers.isEmpty, let data = try? JSONEncoder().encode(m) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
    }

    func stop() {
        stopped = true
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }
}

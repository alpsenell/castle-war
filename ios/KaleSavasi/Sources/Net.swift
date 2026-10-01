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
    /// The sender's castle, in the flat form of `CastleDesign.encoded`.
    var design: [Int]? = nil
    /// Special shot used, as `Ammo.rawValue`.
    var ammo: Int? = nil
}

/// A two-player connection. All callbacks arrive on the main queue.
protocol MatchTransport: AnyObject {
    var onConnected: (() -> Void)? { get set }
    var onMessage: ((NetMessage) -> Void)? { get set }
    var onDisconnected: (() -> Void)? { get set }
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
    var onStatus: ((String, Bool) -> Void)?
    private var match: GKMatch?
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
            req.maxPlayers = 2
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
        if state == .connected { if match.expectedPlayerCount == 0 { goLive() } }
        else if state == .disconnected { onMain { self.onDisconnected?() } }
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
    var onConnected: (() -> Void)?
    var onMessage: ((NetMessage) -> Void)?
    var onDisconnected: (() -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    private static let service = "kale-savasi"
    private let me = MCPeerID(displayName: String(UUID().uuidString.prefix(8)))
    private lazy var session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
    private lazy var advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: Self.service)
    private lazy var browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.service)
    private var live = false
    private var stopped = false

    func start() {
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        onStatus?(Tx.nearbySearching, true)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Only one side sends the invitation, so two devices never invite each other at once.
        guard session.connectedPeers.isEmpty, me.displayName < peerID.displayName else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onMain { self.onStatus?(Tx.localNetworkFailed(error.localizedDescription), false) }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(session.connectedPeers.isEmpty, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onMain { self.onStatus?(Tx.localNetworkFailed(error.localizedDescription), false) }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onMain {
            guard !self.stopped else { return }
            if state == .connected, !self.live {
                self.live = true
                self.advertiser.stopAdvertisingPeer()
                self.browser.stopBrowsingForPeers()
                self.onConnected?()
            } else if state == .notConnected, self.live {
                self.live = false
                self.onDisconnected?()
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let m = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
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

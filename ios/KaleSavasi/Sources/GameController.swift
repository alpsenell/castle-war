import SwiftUI
import SceneKit
import QuartzCore

enum Screen { case menu, lobby, playing, over }
enum Mode { case ai, local, online }
enum OnlineKind { case gameCenter, nearby }

struct HUD: Equatable {
    var names = ["", ""]
    var pct = [1.0, 1.0]
    var turnText = ""
    var turnSide = 0
    var finished = false
    var windAngle = 0.0
    var windPower = 0
    var canAim = false
    var canInspect = false
    var inspecting = false
}

/// A pull-back gesture in progress, in screen points.
struct Pull: Equatable {
    var start: CGPoint
    var current: CGPoint
    var yaw: Double
    var power: Double
    var armed: Bool
}

struct OverInfo: Equatable {
    var title: String
    var detail: String
    var waiting = false
}

struct Lobby: Equatable {
    var kind = OnlineKind.nearby
    var status = ""
    var busy = true
}

/// Runs the match: whose turn it is, shots, the cameras and what the HUD shows.
final class GameController: NSObject, ObservableObject {
    let world = World()
    private let sfx = Sfx()

    @Published var screen = Screen.menu
    @Published var hud = HUD()
    @Published var pull: Pull?
    @Published var ghost: CGSize?
    @Published var toast: String?
    @Published var over: OverInfo?
    @Published var lobby = Lobby()
    @Published var difficulty = Difficulty.orta
    @Published var soundOn = true { didSet { sfx.enabled = soundOn } }
    var viewSize = CGSize(width: 844, height: 390)

    private enum Phase { case menu, aim, flight, impact, over }
    private enum Driver { case human, computer, remote }
    private enum Cam { case menu, aim, target, follow, impact }
    private struct Flight { var side: Int; var res: ShotResult; var path: [Vec3]; var i = 0.0 }

    private var mode = Mode.ai
    private var me = 0
    private var battle = Battle(seed: UInt32.random(in: 0...UInt32.max), first: 0)
    private var aims = [Aim(), Aim()]
    private var lastPull: [CGSize?] = [nil, nil]
    private var phase = Phase.menu
    private var driver = Driver.human
    private var wind = (x: 0.0, z: 0.0)
    private var flight: Flight?
    private var plan: (t: Double, from: Aim, to: Aim)?
    private var remoteAim: Aim?
    private var impactT = 0.0, slowT = 0.0, ts = 1.0
    private var toastWork: DispatchWorkItem?

    private var cam = Cam.menu
    private var camSide = 0
    private var menuA = 0.7, orbitA = 0.0, orbitH = 28.0, orbitR = 56.0, orbitR0 = 56.0, impactA = 0.0, shake = 0.0
    private var lastDrag: CGPoint?
    private var impactP = SIMD3<Float>(0, 0, 0), impactDir = SIMD3<Float>(1, 0, 0), ballDir = SIMD3<Float>(1, 0, 0)
    private var camPos = SIMD3<Float>(100, 46, 100), camLook = SIMD3<Float>(0, 7, 0)
    private var fov: Float = 50
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0

    private var net: MatchTransport?
    private var myNonce: UInt32 = 0
    private var isHost = false
    private var round = 0
    private var wantAgain = false, oppAgain = false, oppGone = false
    private var pendingShot: NetMessage?
    private var aimDirty = false
    private var aimSendT = 0.0

    // Test hooks (debug builds only): "-autoPlay" lets the computer take this device's turns,
    // "-autoNearby" opens the nearby lobby at launch. Used to run a whole online match unattended.
    #if DEBUG
    private let autoPlay = ProcessInfo.processInfo.arguments.contains("-autoPlay")
    #else
    private let autoPlay = false
    #endif

    override init() {
        super.init()
        world.load(battle)
        world.onSplash = { [weak self] in self?.sfx.play(.splash) }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-autoNearby") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.playOnline(.nearby) }
        }
        #endif
    }

    // MARK: Menu actions

    func playComputer() { sfx.play(.tick); startGame(.ai) }
    func playLocal() { sfx.play(.tick); startGame(.local) }

    func playOnline(_ kind: OnlineKind) {
        sfx.play(.tick)
        stopNet()
        lobby = Lobby(kind: kind, status: "")
        screen = .lobby
        let t: MatchTransport = kind == .gameCenter ? GameCenterTransport() : NearbyTransport()
        net = t
        t.onStatus = { [weak self] s, busy in self?.lobby.status = s; self?.lobby.busy = busy }
        t.onConnected = { [weak self] in self?.netConnected() }
        t.onMessage = { [weak self] m in self?.netMessage(m) }
        t.onDisconnected = { [weak self] in self?.netLost() }
        t.start()
    }

    func showMenu() {
        stopNet()
        phase = .menu
        cam = .menu
        menuA = Double(atan2(camPos.x, camPos.z))
        pull = nil; ghost = nil; over = nil
        world.hidePreview()
        world.endBall()
        screen = .menu
    }

    func rematch() {
        if mode == .online {
            guard net != nil, !oppGone else { over?.detail = "Rakip ayrıldı. Ana menüden yeni bir eşleşme başlat."; return }
            wantAgain = true
            net?.send(NetMessage(t: "again", round: round), reliable: true)
            if isHost && oppAgain { hostNewRound() } else { over?.waiting = true }
        } else {
            startGame(mode, first: mode == .local ? 1 - battle.first : 0)
        }
    }

    func toggleInspect() {
        guard phase == .aim else { return }
        if cam == .aim {
            cam = .target
            orbitA = camSide == 0 ? Double.pi - 0.55 : 0.55
            orbitH = 28; orbitR = 56
            world.hidePreview()
        } else { cam = .aim }
        refreshHUD()
    }

    // MARK: Turn flow

    private func startGame(_ m: Mode, seed: UInt32? = nil, me: Int = 0, first: Int = 0, round: Int = 1) {
        mode = m
        self.me = me
        self.round = round
        oppGone = false; wantAgain = false; oppAgain = false; pendingShot = nil
        flight = nil; plan = nil; remoteAim = nil; ts = 1; slowT = 0
        battle = Battle(seed: seed ?? UInt32.random(in: 0...UInt32.max), first: first)
        world.load(battle)
        aims = [Aim(), Aim()]
        lastPull = [nil, nil]
        pull = nil; over = nil; toast = nil
        screen = .playing
        beginTurn()
    }

    private func names() -> [String] {
        switch mode {
        case .ai: return ["Sen", "Yapay zekâ"]
        case .online: return me == 0 ? ["Sen", "Rakip"] : ["Rakip", "Sen"]
        case .local: return ["Kırmızı", "Mavi"]
        }
    }

    private func driverOf(_ side: Int) -> Driver {
        switch mode {
        case .ai: return side == 0 ? .human : .computer
        case .local: return .human
        case .online: return side == me ? .human : .remote
        }
    }

    private func beginTurn() {
        let s = battle.turn
        phase = .aim
        driver = driverOf(s)
        wind = battle.wind()
        plan = nil; remoteAim = nil; pull = nil
        cam = .aim; camSide = s
        ghost = driver == .human ? lastPull[s] : nil
        refreshHUD()
        switch driver {
        case .computer: plan = (0, aims[s], Computer.choose(battle: battle, side: s, difficulty: difficulty, wind: wind))
        case .remote: checkRemote()
        case .human:
            if autoPlay { plan = (0, aims[s], Computer.choose(battle: battle, side: s, difficulty: .orta, wind: wind)) }
        }
    }

    private func fire() {
        guard phase == .aim, !oppGone else { return }
        let s = battle.turn, l = Ballistics.launch(side: s, aim: aims[s])
        if mode == .online && driver == .human {
            net?.send(NetMessage(t: "shot", round: round, k: battle.shot, p: bits(l.p0), v: bits(l.v0), yaw: aims[s].yaw, power: aims[s].power), reliable: true)
        }
        launch(side: s, p0: l.p0, v0: l.v0, d: l.d)
    }

    private func launch(side: Int, p0: Vec3, v0: Vec3, d: Vec3) {
        let res = battle.simulate(p0: p0, v0: v0, wind: wind)
        flight = Flight(side: side, res: res, path: battle.trace(p0: p0, v0: v0, wind: wind, steps: res.steps))
        phase = .flight
        ts = 1
        cam = .follow
        let h = SIMD3<Float>(Float(v0.x), 0, Float(v0.z))
        ballDir = simd_length_squared(h) > 1e-8 ? simd_normalize(h) : SIMD3(side == 0 ? 1 : -1, 0, 0)
        world.hidePreview()
        world.fireBall(from: p0, dir: d, side: side)
        sfx.play(.fire)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        pull = nil
        refreshHUD()
    }

    private func impact() {
        guard let f = flight else { return }
        let res = f.res
        world.endBall()
        let dmg = battle.apply(res)
        world.showImpact(res, damage: dmg)
        let any = dmg.contains { $0.cells > 0 }
        let enemy = 1 - f.side
        var msg = "Iska!"
        switch res.kind {
        case .out: break
        case .water: msg = "Gülle suya düştü"
        case .ground, .castle:
            sfx.play(any ? .hit : .thud)
            shake = any ? 0.9 : 0.3
            if any { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
            if dmg[enemy].cells > 0 {
                msg = "İsabet! −%\(max(1, Int((Double(dmg[enemy].cells) / Double(battle.castles[enemy].total) * 100).rounded())))"
            } else if dmg[f.side].cells > 0 { msg = "Kendi kaleni vurdun!" }
        }
        show(toast: msg)
        impactP = res.pos.f
        let h = SIMD3<Float>(Float(res.vel.x), 0, Float(res.vel.z))
        impactDir = simd_length_squared(h) > 1e-8 ? simd_normalize(h) : SIMD3(f.side == 0 ? 1 : -1, 0, 0)
        impactA = 0
        cam = res.kind == .out ? .aim : .impact
        phase = .impact
        impactT = any ? 3.8 : 1.9
        slowT = any ? 0.8 : 0
        flight = nil
        refreshHUD()
    }

    private func endTurn() {
        if let loser = battle.loser() { gameOver(winner: 1 - loser); return }
        battle.shot += 1
        beginTurn()
    }

    private func gameOver(winner: Int) {
        phase = .over
        cam = .target
        camSide = winner
        orbitA = winner == 0 ? Double.pi - 0.55 : 0.55
        orbitH = 30; orbitR = 60
        let nm = names()
        let title: String
        if mode == .local { title = "\(nm[winner]) kazandı!"; sfx.play(.win) } else {
            let won = (mode == .ai ? 0 : me) == winner
            title = won ? "Kazandın!" : "Kaybettin"
            sfx.play(won ? .win : .lose)
        }
        let p = battle.castles.map { Int(($0.pct * 100 + 1e-9).rounded(.down)) }
        let info = OverInfo(title: title, detail: "Ayakta kalan yapı: \(nm[0]) %\(p[0]), \(nm[1]) %\(p[1]).")
        refreshHUD()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.phase == .over else { return }
            self.over = info
            if self.oppAgain { self.over?.detail = "Rakip tekrar oynamak istiyor." }
            self.screen = .over
        }
    }

    private func show(toast msg: String) {
        toastWork?.cancel()
        toast = msg
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3, execute: w)
    }

    private func refreshHUD() {
        var h = HUD()
        h.names = names()
        h.pct = battle.castles.map { $0.pct }
        let s = battle.turn
        h.turnSide = s
        h.finished = phase == .over
        if oppGone { h.turnText = "Rakip ayrıldı" } else {
            switch phase {
            case .flight, .impact: h.turnText = "Gülle havada"
            case .over: h.turnText = "Oyun bitti"
            default:
                switch driver {
                case .human: h.turnText = mode == .local ? "Sıra: \(h.names[s])" : "Sıra sende"
                case .computer: h.turnText = "Yapay zekâ nişan alıyor"
                case .remote: h.turnText = "Rakip nişan alıyor"
                }
            }
        }
        let sg: Double = s == 0 ? 1 : -1, f = wind.x * sg, r = wind.z * sg
        h.windAngle = atan2(r, f) * 180 / .pi
        h.windPower = Int(((f * f + r * r).squareRoot() / (K.wind * 1.414) * 10).rounded())
        h.canInspect = phase == .aim
        h.inspecting = cam == .target && phase == .aim
        h.canAim = phase == .aim && driver == .human && !oppGone && cam == .aim
        if h != hud { hud = h }
    }

    // MARK: Touch input

    /// Pull back anywhere on the scene and release: sideways sets the direction, length sets the power.
    func drag(start: CGPoint, location: CGPoint) {
        if cam == .target {
            if let last = lastDrag {
                orbitA += Double(location.x - last.x) * 0.008 * (camSide == 0 ? 1 : -1) * -1
                orbitH = min(70, max(6, orbitH + Double(location.y - last.y) * 0.14))
            }
            lastDrag = location
            return
        }
        guard phase == .aim, driver == .human, cam == .aim, !oppGone else { return }
        let maxPull = min(260, Double(viewSize.height) * 0.62)
        let dx = Double(location.x - start.x), dy = Double(location.y - start.y)
        let power = min(1, max(0, dy / maxPull)) * 100
        let yaw = min(K.maxYaw, max(-K.maxYaw, -dx * 0.14))
        let armed = power >= 6
        let s = battle.turn
        if armed { aims[s] = Aim(yaw: yaw, power: power); aimDirty = true; showPreview(side: s) } else { world.hidePreview() }
        pull = Pull(start: start, current: location, yaw: yaw, power: power, armed: armed)
    }

    func dragEnded() {
        lastDrag = nil
        guard let p = pull else { return }
        pull = nil
        world.hidePreview()
        guard phase == .aim, driver == .human, p.armed else { return }
        lastPull[battle.turn] = CGSize(width: p.current.x - p.start.x, height: p.current.y - p.start.y)
        fire()
    }

    func pinch(_ scale: CGFloat) {
        guard cam == .target else { return }
        orbitR = min(110, max(24, orbitR0 / Double(scale)))
    }

    func pinchEnded() { orbitR0 = orbitR }

    private func showPreview(side s: Int) {
        let l = Ballistics.launch(side: s, aim: aims[s])
        var x = l.p0.x, y = l.p0.y, z = l.p0.z, vx = l.v0.x, vy = l.v0.y, vz = l.v0.z
        var pts: [SIMD3<Float>] = []
        for i in 1...(20 * 9) {
            vx += wind.x * K.dt; vy -= K.grav * K.dt; vz += wind.z * K.dt
            x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
            if i % 9 == 0 { pts.append(SIMD3(Float(x), Float(y), Float(z))) }
        }
        world.showPreview(pts)
    }

    // MARK: Online

    private func bits(_ v: Vec3) -> [UInt64] { [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern] }

    private func stopNet() {
        net?.stop()
        net = nil
        round = 0; isHost = false; wantAgain = false; oppAgain = false; pendingShot = nil; oppGone = false
    }

    private func netConnected() {
        oppGone = false
        round = 0
        myNonce = UInt32.random(in: 1...UInt32.max)
        lobby.busy = true
        lobby.status = "Rakip bulundu, oyun başlıyor…"
        net?.send(NetMessage(t: "hello", nonce: myNonce), reliable: true)
    }

    private func netLost() {
        oppGone = true
        if screen == .lobby { lobby.status = "Bağlantı koptu."; lobby.busy = false } else { show(toast: "Rakip ayrıldı"); refreshHUD() }
    }

    private func hostNewRound() {
        round += 1
        let seed = UInt32.random(in: 0...UInt32.max), first = (round + 1) % 2
        net?.send(NetMessage(t: "start", seed: seed, round: round, first: first), reliable: true)
        startGame(.online, seed: seed, me: 0, first: first, round: round)
    }

    private func netMessage(_ m: NetMessage) {
        switch m.t {
        case "hello":
            guard let n = m.nonce else { return }
            if n == myNonce { netConnected(); return }
            isHost = myNonce > n
            if isHost && round == 0 { hostNewRound() }
        case "start":
            guard !isHost, let seed = m.seed, let r = m.round, let first = m.first, first == 0 || first == 1 else { return }
            startGame(.online, seed: seed, me: 1, first: first, round: r)
        case "aim":
            guard phase == .aim, driver == .remote, let y = m.yaw, let p = m.power, y.isFinite, p.isFinite else { return }
            remoteAim = Aim(yaw: min(K.maxYaw, max(-K.maxYaw, y)), power: min(100, max(0, p)))
        case "shot":
            pendingShot = m
            checkRemote()
        case "again":
            guard m.round == round else { return }
            oppAgain = true
            if isHost && wantAgain { hostNewRound() } else if !wantAgain, over != nil { over?.detail = "Rakip tekrar oynamak istiyor." }
        default: break
        }
    }

    /// Plays the opponent's shot once it has arrived and it is their turn here too.
    private func checkRemote() {
        guard mode == .online, phase == .aim, driver == .remote, let m = pendingShot,
              m.round == round, m.k == battle.shot, let pb = m.p, let vb = m.v, pb.count == 3, vb.count == 3 else { return }
        let p0 = Vec3(x: Double(bitPattern: pb[0]), y: Double(bitPattern: pb[1]), z: Double(bitPattern: pb[2]))
        let v0 = Vec3(x: Double(bitPattern: vb[0]), y: Double(bitPattern: vb[1]), z: Double(bitPattern: vb[2]))
        let sp = v0.length
        guard [p0.x, p0.y, p0.z, sp].allSatisfy({ $0.isFinite }), sp >= 1, sp <= K.vMax + 1 else { return }
        pendingShot = nil
        let s = battle.turn
        if let y = m.yaw, let p = m.power, y.isFinite, p.isFinite { aims[s] = Aim(yaw: min(K.maxYaw, max(-K.maxYaw, y)), power: min(100, max(0, p))) }
        launch(side: s, p0: p0, v0: v0, d: Vec3(x: v0.x / sp, y: v0.y / sp, z: v0.z / sp))
    }

    // MARK: Frame update

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, max(0, now - lastTime))
        lastTime = now
        update(dt)
    }

    private func update(_ dt: Double) {
        for s in 0..<2 { world.cannons[s].pose(yaw: aims[s].yaw, dt: Float(dt)) }
        if phase == .aim {
            let s = battle.turn
            if var p = plan {
                p.t += dt
                let k = min(1, p.t / 1.5), e = k * k * (3 - 2 * k)
                aims[s] = Aim(yaw: p.from.yaw + (p.to.yaw - p.from.yaw) * e, power: p.from.power + (p.to.power - p.from.power) * e)
                plan = p
                if p.t > 1.9 { plan = nil; fire() }
            } else if driver == .remote, let r = remoteAim {
                let k = 1 - exp(-10 * dt)
                aims[s].yaw += (r.yaw - aims[s].yaw) * k
                aims[s].power += (r.power - aims[s].power) * k
            } else if driver == .human, mode == .online {
                aimSendT -= dt
                if aimDirty && aimSendT <= 0 {
                    aimDirty = false; aimSendT = 0.14
                    net?.send(NetMessage(t: "aim", yaw: aims[s].yaw, power: aims[s].power), reliable: false)
                }
            }
        }
        if phase == .flight, var f = flight {
            let n = f.res.steps
            ts = (Double(n) - f.i < 34 && f.res.kind != .out) ? 0.4 : 1
            f.i = min(Double(n), f.i + dt * 120 * ts)
            let i0 = min(n - 1, Int(f.i)), fr = Float(f.i - Double(i0))
            let a = f.path[i0].f, b = f.path[i0 + 1].f
            world.ball.simdPosition = a + (b - a) * fr
            let d = SIMD3<Float>(b.x - a.x, 0, b.z - a.z)
            if simd_length_squared(d) > 1e-10 { ballDir = simd_normalize(simd_mix(ballDir, simd_normalize(d), SIMD3(repeating: Float(1 - exp(-6 * dt))))) }
            flight = f
            if f.i >= Double(n) { impact() }
        } else if phase == .impact {
            if slowT > 0 { slowT -= dt; ts = 0.4 } else { ts = min(1, ts + dt * 2.5) }
            impactT -= dt
            if impactT <= 0 { ts = 1; endTurn() }
        } else { ts = 1 }
        world.scene.physicsWorld.speed = CGFloat(ts)
        world.update(dt: dt)
        updateCamera(dt)
    }

    private func updateCamera(_ dt: Double) {
        var tPos = SIMD3<Float>(0, 0, 0), tLook = SIMD3<Float>(0, 0, 0)
        var k = 3.0
        var wantFov: Float = 50
        switch cam {
        case .menu:
            menuA += dt * 0.06
            tPos = SIMD3(Float(sin(menuA)) * 125, 46, Float(cos(menuA)) * 125)
            tLook = SIMD3(0, 7, 0)
            k = 1.6
        case .aim:
            let sg: Float = camSide == 0 ? 1 : -1, y = Float(aims[camSide].yaw * .pi / 180)
            let h = SIMD3<Float>(sg * cos(y), 0, sg * sin(y)), pv = Ballistics.pivot(camSide).f
            tPos = pv - h * 7.5 + SIMD3(0, 3.6, 0)
            tLook = pv + h * 40
            tLook.y = 4.2
            k = 4.5
            wantFov = 46
        case .target:
            if phase == .over { orbitA += dt * 0.12 }
            let ex = (camSide == 0 ? 1 : -1) * Float(K.front + Double(K.gw) / 2)
            tPos = SIMD3(ex + Float(cos(orbitA) * orbitR), Float(orbitH), Float(sin(orbitA) * orbitR))
            tLook = SIMD3(ex, 7, 0)
            k = 4
        case .follow:
            let b = world.ball.simdPosition, d = ballDir
            tPos = b - d * 13 + SIMD3(0, 5, 0) + SIMD3(-d.z, 0, d.x) * 3
            tLook = b + d * 6
            // stay above the walls instead of flying through them
            if abs(tPos.x) > Float(K.front) - 5 && abs(tPos.x) < Float(K.xEdge) + 3 && abs(tPos.z) < Float(K.gd) / 2 + 3 { tPos.y = max(tPos.y, 25) }
            k = 7
        case .impact:
            impactA += dt * 0.13
            let d = impactDir, c = Float(cos(impactA + 0.45)), s = Float(sin(impactA + 0.45))
            tPos = SIMD3(impactP.x - (d.x * c - d.z * s) * 32, impactP.y + 16, impactP.z - (d.x * s + d.z * c) * 32)
            tLook = impactP
            tLook.y = max(3, tLook.y)
            k = 2.6
        }
        tPos.y = max(tPos.y, 2.5)
        camPos = simd_mix(camPos, tPos, SIMD3(repeating: Float(1 - exp(-k * dt))))
        camLook = simd_mix(camLook, tLook, SIMD3(repeating: Float(1 - exp(-(k + 1.5) * dt))))
        var p = camPos
        if shake > 0.01 {
            p += SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * Float(shake)
            shake *= exp(-6 * dt)
        }
        fov += (wantFov - fov) * Float(1 - exp(-5 * dt))
        // Build the orientation by hand so the horizon always stays level.
        let f = simd_normalize(camLook - p)
        let r = simd_normalize(simd_cross(f, SIMD3<Float>(0, 1, 0)))
        let u = simd_cross(r, f)
        world.cameraNode.simdPosition = p
        world.cameraNode.simdOrientation = simd_quatf(simd_float3x3(columns: (r, u, -f)))
        world.camera.fieldOfView = CGFloat(fov)
    }
}

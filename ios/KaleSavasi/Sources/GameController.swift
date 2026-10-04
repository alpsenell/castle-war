import SwiftUI
import SceneKit
import QuartzCore

enum Screen { case menu, lobby, playing, over, builder }
enum Mode { case ai, local, online, challenge, campaign, gauntlet, party }
enum OnlineKind { case gameCenter, nearby, partyGameCenter, partyHost, partyJoin }
/// Which card the menu screen shows.
enum Panel { case home, profile, settings, howTo, campaign, achievements, party }

struct HUD: Equatable {
    var names = ["", ""]
    var pct = [1.0, 1.0]
    var heart = [1.0, 1.0]
    var charge = [0.0, 0.0]
    var streak = [0, 0]
    var shield = [false, false]
    var turnText = ""
    var turnSide = 0
    var finished = false
    var windAngle = 0.0
    var windPower = 0
    var canAim = false
    var canInspect = false
    var inspecting = false
    var megaVisible = false
    var megaReady = false
    var megaCharge = 0.0
    var hasTarget = false
    /// Special shots left for the player who is aiming, indexed by `Ammo.rawValue`.
    var stock = [0, 0, 0, 0]
    var pickup: PickupKind?
    var modifier = Modifier.none
    /// Daily siege only: running score and how many shots have been taken.
    var score: Int?
    var shotsTaken = 0
    /// Four-castle matches: which seats are out, which one is this device, and the castles the
    /// player can aim at with the one picked.
    var out: [Bool] = [false, false]
    var me: Int?
    var targets: [Int] = []
    var target = -1
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
    var stats: MatchStats?
    var reward: Reward?
    /// Head-to-head: the other side's numbers, both names, and which side is "mine".
    var rivalStats: MatchStats?
    var names: [String] = []
    var side = 0
    var isSiege = false
    /// Campaign: the win opened another stage to move on to.
    var hasNextStage = false
    /// Gauntlet: the run goes on with the next castle, or it is over.
    var isGauntlet = false
    var gauntletNext = false
}

struct MissionRow: Identifiable {
    let id: String
    let title: String
    let progress: Int
    let target: Int
    let done: Bool
}

struct Lobby: Equatable {
    var kind = OnlineKind.nearby
    var status = ""
    var busy = true
    /// Four-castle lobbies: players here so far, this device included, and whether this device may start.
    var players = 1
    var canStart = false
    var isParty: Bool { kind == .partyGameCenter || kind == .partyHost || kind == .partyJoin }
}

/// Runs the match: whose turn it is, shots, the cameras and what the HUD shows.
final class GameController: NSObject, ObservableObject {
    let world = World()
    private let sfx = Sfx()

    @Published var screen = Screen.menu
    @Published var panel = Panel.home
    @Published var hud = HUD()
    @Published var pull: Pull?
    @Published var ghost: CGSize?
    @Published var toast: String?
    @Published var over: OverInfo?
    @Published var lobby = Lobby()
    @Published var difficulty = Difficulty.orta
    @Published var soundOn = true { didSet { sfx.enabled = soundOn } }
    @Published var megaArmed = false
    /// The special shot picked for the next pull.
    @Published var ammo = Ammo.standard
    /// Seconds left on the shot clock, or nil when the turn is not timed.
    @Published var timeLeft: Int?
    @Published var profile = Profile.load()
    @Published var language = Tx.lang { didSet { Tx.set(language); refreshHUD() } }
    @Published var confirmQuit = false
    // Castle builder
    @Published var draft = CastleDesign()
    @Published var tool: PieceKind? = .wallLow
    @Published var erasing = false
    @Published var builderNote: String?
    /// The final, heart-breaking shot is playing out in slow motion.
    @Published var finale = false
    var viewSize = CGSize(width: 844, height: 390)

    private enum Phase { case menu, aim, flight, impact, over }
    private enum Driver { case human, computer, remote }
    private enum Cam { case menu, aim, target, follow, impact, finale }
    private struct Flight { var side: Int; var res: ShotResult; var path: [Vec3]; var i = 0.0; var popped = false; var final = false }

    private var mode = Mode.ai
    private var me = 0
    private var battle = Battle(seed: 1, first: 0)
    private var stage: Stage?
    private var aiLevel = Difficulty.orta
    private var aims = [Aim(), Aim()]
    private var lastPull: [CGSize?] = [nil, nil]
    private var stats = [MatchStats(), MatchStats()]
    private var phase = Phase.menu
    private var driver = Driver.human
    private var wind = (x: 0.0, z: 0.0)
    private var flight: Flight?
    private var plan: (t: Double, from: Aim, to: Aim)?
    private var remoteAim: Aim?
    private var impactT = 0.0, slowT = 0.0, ts = 1.0, turnT = 0.0
    private var skipped = false
    private var score = 0, shotsTaken = 0, clearBonus = 0
    /// Who the online opponent says they are, and the castle they brought.
    private var rival: (name: String, trophies: Int, level: Int, design: CastleDesign)?
    private var toastWork: DispatchWorkItem?
    private var lastTile: (Int, Int)?
    // Gauntlet run
    private var gauntletRound = 1
    private var gauntletSeed: UInt32 = 0
    private var gauntletCarry: Castle?
    /// The castle loaded from a friend's code, while playing against it.
    private var friendDesign: CastleDesign?
    // Four-castle match
    private var seats: [SeatInfo] = []
    /// Online players who left; a computer run by the host plays their castle from then on.
    private var seatGone: [Bool] = []
    /// Seats in the order their hearts broke.
    private var outOrder: [Int] = []
    /// The reward booked when this device's heart broke, shown again on the final card.
    private var partyReward: Reward?
    /// Players who said hello in a four-castle lobby, by nonce.
    private var partyPeers: [UInt32: SeatInfo] = [:]
    private var hostNonce: UInt32 = 0
    private var lastSeen: [UInt32: Double] = [:]
    private var pingT = 0.0, clock = 0.0
    /// The castle the inspect and end-of-match cameras circle.
    private var viewSeat = 1

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
        #if DEBUG
        // "-preset N" plays with ready-made castle N instead of the saved one (not stored).
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-preset"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let n = Int(ProcessInfo.processInfo.arguments[i + 1]), Presets.all.indices.contains(n) {
            profile.design = Presets.all[n].encoded
        }
        #endif
        resetBackdrop()
        world.onSplash = { [weak self] in self?.sfx.play(.splash) }
        if !profile.seenHowTo { panel = .howTo }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-autoNearby") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.playOnline(.nearby) }
        }
        #endif
    }

    /// The side whose results count for this device's profile; nil in pass-and-play.
    private var mySide: Int? { mode == .local ? nil : mode == .online || mode == .party ? me : 0 }

    /// A four-castle match played over the network.
    private var partyOnline: Bool { mode == .party && net != nil }
    /// This device runs the computer seats: always offline, the host online.
    private var runsComputers: Bool { mode != .party || net == nil || isHost }

    var missions: [MissionRow] {
        profile.missionRows().map { MissionRow(id: $0.mission.id, title: Tx.mission($0.mission), progress: $0.progress, target: $0.mission.target, done: $0.done) }
    }

    /// The scene behind the menu: the player's own castle facing a random one.
    private func resetBackdrop() {
        let seed = UInt32.random(in: 0...UInt32.max)
        battle = Battle(seed: seed, first: 0, designs: [profile.castle, Presets.pick(seed)])
        world.load(battle)
    }

    private func thump(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        if profile.haptics { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }

    // MARK: Menu actions

    func playComputer() {
        sfx.play(.tick)
        let seed = UInt32.random(in: 0...UInt32.max)
        aiLevel = difficulty
        startGame(.ai, seed: seed, designs: [profile.castle, Presets.pick(seed)])
    }

    func playGauntlet() {
        sfx.play(.tick)
        gauntletRound = 1
        gauntletSeed = UInt32.random(in: 0...UInt32.max)
        gauntletCarry = nil
        startGauntletRound()
    }

    private func startGauntletRound() {
        let foe = Gauntlet.foe(round: gauntletRound, seed: gauntletSeed)
        aiLevel = foe.difficulty
        startGame(.gauntlet, seed: gauntletSeed &+ UInt32(gauntletRound), designs: [profile.castle, foe.design], rules: MatchRules(foe.modifier), carry: gauntletCarry)
        if foe.modifier == .none { show(toast: Tx.gauntletRound(gauntletRound)) }
    }

    /// Attacks a castle pasted as a code, at the chosen difficulty.
    func playFriend(code: String) {
        guard let d = CastleCode.decode(code) else { show(toast: Tx.codeInvalid); sfx.play(.thud); return }
        sfx.play(.tick)
        aiLevel = difficulty
        startGame(.ai, designs: [profile.castle, d], friend: d)
    }

    /// Four castles: the player against three computers.
    func playParty() {
        sfx.play(.tick)
        stopNet()
        aiLevel = difficulty
        var picks = Presets.all.shuffled()
        seats = [SeatInfo(nonce: 0, name: Tx.you, level: profile.level, design: profile.castle.encoded)]
        for i in 1..<4 { seats.append(SeatInfo(nonce: 0, name: Tx.seatName(i), level: 1, design: picks.removeFirst().encoded)) }
        startParty(seed: UInt32.random(in: 0...UInt32.max), me: 0, first: Int.random(in: 0..<4), round: 1)
    }

    private func startParty(seed: UInt32, me seat: Int, first: Int, round r: Int) {
        let designs = seats.map { CastleDesign(encoded: $0.design) ?? .classic }
        outOrder = []
        partyReward = nil
        seatGone = Array(repeating: false, count: seats.count)
        startGame(.party, seed: seed, me: seat, first: first, round: r, designs: designs, arena: .party)
        show(toast: Tx.partyTitle)
    }

    func playLocal() { sfx.play(.tick); startGame(.local, designs: [profile.castle, profile.castle]) }

    func playSiege() {
        sfx.play(.tick)
        let seed = Challenge.seed(day: Profile.dayString())
        let twist = Modifier.allCases[Int((seed / 7) % UInt32(Modifier.allCases.count))]
        startGame(.challenge, seed: seed, designs: [profile.castle, Presets.pick(seed)], rules: MatchRules(twist, pickups: false))
    }

    func playStage(_ s: Stage) {
        guard profile.isOpen(s) else { return }
        sfx.play(.tick)
        aiLevel = s.difficulty
        startGame(.campaign, designs: [profile.castle, s.design], rules: MatchRules(s.modifier), stage: s)
    }

    func playOnline(_ kind: OnlineKind) {
        sfx.play(.tick)
        stopNet()
        lobby = Lobby(kind: kind, status: "")
        screen = .lobby
        let t: MatchTransport
        switch kind {
        case .gameCenter: t = GameCenterTransport()
        case .nearby: t = NearbyTransport()
        case .partyGameCenter: t = GameCenterTransport(players: 4)
        case .partyHost: t = NearbyTransport(role: .host)
        case .partyJoin: t = NearbyTransport(role: .join)
        }
        partyPeers = [:]
        lastSeen = [:]
        myNonce = UInt32.random(in: 1...UInt32.max)
        if kind == .partyHost { isHost = true; lobby.canStart = false }
        net = t
        t.onStatus = { [weak self] s, busy in self?.lobby.status = s; self?.lobby.busy = busy }
        t.onConnected = { [weak self] in self?.netConnected() }
        t.onMessage = { [weak self] m in self?.netMessage(m) }
        t.onDisconnected = { [weak self] in self?.netLost() }
        t.onPeers = { [weak self] _ in self?.partyLobbyChanged() }
        t.start()
    }

    var quitWarning: String { mode == .online || partyOnline ? Tx.quitOnline : Tx.quitPlain }

    /// The home button during a match: ask first, since leaving can cost a loss.
    func askToQuit() {
        if screen == .playing && phase != .over { confirmQuit = true } else { showMenu() }
    }

    func showMenu() {
        // Walking out of an online match that is under way counts as a loss.
        if mode == .online, screen == .playing, phase != .over, phase != .menu, battle.shot >= 2, !oppGone {
            var p = profile
            _ = p.record(won: false, mode: .online(opponent: rival?.trophies), stats: stats[me], forfeit: true)
            p.save()
            profile = p
        }
        if partyOnline, screen == .playing, phase != .over, phase != .menu, !outOrder.contains(me) {
            var p = profile
            _ = p.record(won: false, mode: .party(place: battle.standing.count, online: true), stats: stats[me], forfeit: true)
            p.save()
            profile = p
        }
        let wasPlaying = screen != .menu
        stopNet()
        phase = .menu
        cam = .menu
        menuA = Double(atan2(camPos.x, camPos.z))
        pull = nil; ghost = nil; over = nil; timeLeft = nil; megaArmed = false; ammo = .standard; confirmQuit = false; finale = false
        world.hidePreview()
        world.endBall()
        screen = .menu
        panel = .home
        if wasPlaying { resetBackdrop() }
    }

    func rematch() {
        switch mode {
        case .online:
            guard net != nil, !oppGone else { over?.detail = Tx.rematchGone; return }
            wantAgain = true
            net?.send(NetMessage(t: "again", round: round), reliable: true)
            if isHost && oppAgain { hostNewRound() } else { over?.waiting = true }
        case .challenge: playSiege()
        case .campaign:
            if over?.hasNextStage == true { playStage(profile.nextStage) } else if let s = stage { playStage(s) }
        case .ai:
            if let d = friendDesign { aiLevel = difficulty; startGame(.ai, designs: [profile.castle, d], friend: d) } else { playComputer() }
        case .gauntlet:
            if over?.gauntletNext == true { gauntletRound += 1; startGauntletRound() } else { playGauntlet() }
        case .local: startGame(.local, first: 1 - battle.first, designs: [profile.castle, profile.castle])
        case .party:
            if net == nil { playParty() }
            else if isHost { hostParty() }
            else if hostNonce == 0 { showMenu() }
            else { over?.waiting = true }
        }
    }

    func toggleInspect() {
        guard phase == .aim else { return }
        if cam == .aim {
            cam = .target
            viewSeat = aimedSeat(camSide)
            orbitA = battle.arena.facing(viewSeat) + (viewSeat == 0 ? 0.55 : -0.55)
            orbitH = 28; orbitR = 56
            world.hidePreview()
        } else { cam = .aim }
        refreshHUD()
    }

    /// Four castles: aims at another castle. The cannon swings round to face it.
    func selectTarget(_ seat: Int) {
        let s = battle.turn
        guard mode == .party, phase == .aim, driver == .human, battle.enemies.contains(seat), seat != aims[s].target else { return }
        aims[s].target = seat
        aims[s].yaw = 0
        aimDirty = true
        world.hidePreview()
        sfx.play(.tick)
        refreshHUD()
    }

    func toggleMega() {
        guard phase == .aim, driver == .human, hud.megaReady else { return }
        megaArmed.toggle()
        if megaArmed { ammo = .standard }
        sfx.play(megaArmed ? .charged : .tick)
    }

    /// Picks a special shot for the next pull; tapping the same one again puts it back.
    func select(_ a: Ammo) {
        guard phase == .aim, driver == .human, hud.stock[a.rawValue] > 0 else { return }
        ammo = ammo == a ? .standard : a
        if ammo != .standard { megaArmed = false }
        sfx.play(.tick)
    }

    func selectBall(_ id: Int) {
        guard let style = BallStyle.all.first(where: { $0.id == id }), profile.owns(style) else { return }
        profile.ballStyle = id
        profile.save()
        sfx.play(.tick)
    }

    func setName(_ raw: String) {
        let clean = Profile.cleanName(raw)
        guard clean != profile.name else { return }
        profile.name = clean
        if !clean.isEmpty { profile.save() }
    }

    func setHaptics(_ on: Bool) { profile.haptics = on; profile.save(); if on { thump(.light) } }

    func closeHowTo() {
        if !profile.seenHowTo { profile.seenHowTo = true; profile.save() }
        panel = .home
    }

    // MARK: Castle builder

    func openBuilder() {
        sfx.play(.tick)
        draft = profile.castle
        tool = .wallLow; erasing = false; builderNote = nil; lastTile = nil
        screen = .builder
        cam = .target
        viewSeat = 0
        orbitA = 0.75; orbitH = 30; orbitR = 54; orbitR0 = 54
        world.preview(draft)
    }

    func pick(tool kind: PieceKind?) {
        guard kind == nil || profile.owns(kind!) else { builderNote = Tx.needStars(Profile.starsNeeded(kind!)); return }
        tool = kind
        erasing = kind == nil
        builderNote = nil
        sfx.play(.tick)
    }

    /// A touch on the builder grid. `fresh` is the first touch of a stroke; dragging on only lays walls or erases.
    func paint(row: Int, col: Int, fresh: Bool) {
        guard screen == .builder, row >= 0, row < CastleDesign.rows, col >= 0, col < CastleDesign.cols else { return }
        if !fresh, let t = lastTile, t == (row, col) { return }
        lastTile = (row, col)
        if erasing {
            if let i = draft.piece(atRow: row, col: col) { draft.pieces.remove(at: i); draftChanged() }
            return
        }
        guard let kind = tool else { return }
        if !fresh && kind.span > 1 { return }
        let n = kind.span
        let tx = min(max(row - (n - 1) / 2, 0), CastleDesign.rows - n), tz = min(max(col - (n - 1) / 2, 0), CastleDesign.cols - n)
        var next = draft
        if n == 1, let i = next.piece(atRow: row, col: col) {
            let old = next.pieces[i]
            if old.kind == kind { if fresh { next.pieces.remove(at: i); draft = next; draftChanged() }; return }   // tap again to take it away
            guard old.kind.span == 1 else { if fresh { builderNote = Tx.noRoom }; return }
            next.pieces.remove(at: i)                                                                              // swap one wall for the other
        }
        if kind == .keep || kind == .heart { next.pieces.removeAll { $0.kind == kind } }      // only one of each: placing it again moves it
        guard next.fits(kind, row: tx, col: tz) else { if fresh { builderNote = Tx.noRoom }; return }
        next.pieces.append(Piece(kind: kind, tx: tx, tz: tz))
        guard next.cost <= CastleDesign.budget else { builderNote = Tx.noStone; return }
        guard next.decoys <= CastleDesign.maxDecoys else { builderNote = Tx.problem(.manyDecoys); return }
        draft = next
        draftChanged()
    }

    func strokeEnded() { lastTile = nil }

    private func draftChanged() {
        builderNote = nil
        world.preview(draft)
    }

    func loadDraft(_ d: CastleDesign) { draft = d; draftChanged(); sfx.play(.tick) }

    func pick(heart h: HeartKind) {
        guard profile.owns(h) else { builderNote = Tx.heartLocked(h.level); return }
        var next = draft
        next.heart = h
        guard next.cost <= CastleDesign.budget else { builderNote = Tx.noStone; return }
        draft = next
        draftChanged()
        builderNote = Tx.heart(h) + ": " + Tx.heartInfo(h)
        sfx.play(.tick)
    }

    /// The draft as a code to send, once it is a castle that can be played.
    var draftCode: String? { draft.problem == nil ? CastleCode.encode(draft) : nil }

    func pasteCastle(_ text: String) {
        guard let d = CastleCode.decode(text) else { builderNote = Tx.codeInvalid; sfx.play(.thud); return }
        loadDraft(d)
        builderNote = Tx.codeLoaded
    }

    func saveCastle() {
        if let pr = draft.problem { builderNote = Tx.problem(pr); return }
        profile.design = draft.encoded
        profile.castlesSaved += 1
        let fresh = profile.unlockAchievements()
        profile.save()
        sfx.play(.charged)
        closeBuilder()
        show(toast: fresh.first.map(Tx.achievementDone) ?? Tx.saved)
    }

    func closeBuilder() {
        screen = .menu
        panel = .home
        cam = .menu
        menuA = Double(atan2(camPos.x, camPos.z))
        resetBackdrop()
    }

    // MARK: Turn flow

    private func startGame(_ m: Mode, seed: UInt32? = nil, me: Int = 0, first: Int = 0, round: Int = 1,
                           designs: [CastleDesign], rules: MatchRules = MatchRules(), stage: Stage? = nil,
                           carry: Castle? = nil, friend: CastleDesign? = nil, arena: Arena = .duel) {
        mode = m
        friendDesign = friend
        finale = false
        self.me = me
        self.round = round
        self.stage = stage
        oppGone = false; wantAgain = false; oppAgain = false; pendingShot = nil
        flight = nil; plan = nil; remoteAim = nil; ts = 1; slowT = 0
        battle = Battle(seed: seed ?? UInt32.random(in: 0...UInt32.max), first: first, designs: designs, rules: rules, arena: arena)
        if let c = carry { battle.castles[0].adopt(c) }
        world.load(battle)
        let n = arena.seats
        aims = Array(repeating: Aim(), count: n)
        lastPull = Array(repeating: nil, count: n)
        stats = Array(repeating: MatchStats(), count: n)
        score = 0; shotsTaken = 0; clearBonus = 0
        pull = nil; over = nil; toast = nil; confirmQuit = false
        screen = .playing
        panel = .home
        beginTurn()
        if rules.modifier != .none { show(toast: Tx.modifier(rules.modifier) + ": " + Tx.modifierHint(rules.modifier)) }
    }

    private func names() -> [String] {
        switch mode {
        case .ai, .campaign, .gauntlet: return [Tx.you, friendDesign == nil ? Tx.computer : Tx.friendName]
        case .online:
            let them = (rival?.name).flatMap { $0.isEmpty ? nil : $0 } ?? Tx.opponent
            return me == 0 ? [Tx.you, them] : [them, Tx.you]
        case .local: return [Tx.red, Tx.blue]
        case .challenge: return [Tx.you, Tx.targetCastle]
        case .party:
            return seats.indices.map { i in
                if i == me { return Tx.you }
                let name = seats[i].name.isEmpty ? Tx.seatName(i) : seats[i].name
                return seatGone.indices.contains(i) && seatGone[i] ? "\(name) (\(Tx.botTag))" : name
            }
        }
    }

    private func driverOf(_ side: Int) -> Driver {
        switch mode {
        case .ai, .campaign, .gauntlet: return side == 0 ? .human : .computer
        case .local, .challenge: return .human
        case .online: return side == me ? .human : .remote
        case .party:
            if side == me { return .human }
            let computer = !seats.indices.contains(side) || seats[side].nonce == 0 || (seatGone.indices.contains(side) && seatGone[side])
            return computer && runsComputers ? .computer : .remote
        }
    }

    /// The castle a seat is aiming at now.
    private func aimedSeat(_ side: Int) -> Int {
        let t = aims.indices.contains(side) ? aims[side].target : -1
        return t < 0 ? battle.arena.across(side) : t
    }

    private func ballStyle(for side: Int) -> BallStyle {
        let own = mode == .local || side == mySide
        return BallStyle.all.first { $0.id == (own ? profile.ballStyle : 0) } ?? BallStyle.all[0]
    }

    private func beginTurn() {
        let s = battle.turn
        phase = .aim
        driver = driverOf(s)
        wind = battle.wind()
        plan = nil; remoteAim = nil; pull = nil
        megaArmed = false; ammo = .standard; skipped = false
        cam = .aim; camSide = s
        if mode == .party, !battle.enemies.contains(aimedSeat(s)) {
            let across = battle.arena.across(s)
            aims[s].target = battle.enemies.contains(across) ? across : battle.enemies.first ?? across
            aims[s].yaw = 0
        }
        ghost = driver == .human ? lastPull[s] : nil
        world.showTarget(battle.goldTarget())
        world.showPickup(battle.pickup)
        turnT = K.turnSeconds
        // Shot clock: only where a person on the other side is waiting.
        timeLeft = driver == .human && (mode == .online || mode == .local || partyOnline) && !autoPlay ? Int(K.turnSeconds) : nil
        refreshHUD()
        switch driver {
        case .computer: planComputerShot(side: s, difficulty: aiLevel)
        case .remote: checkRemote()
        case .human: if autoPlay { planComputerShot(side: s, difficulty: .orta) }
        }
    }

    private func planComputerShot(side s: Int, difficulty: Difficulty) {
        let c = Computer.choose(battle: battle, side: s, difficulty: difficulty, wind: wind)
        megaArmed = c.mega
        ammo = c.ammo
        plan = (0, aims[s], c.aim)
    }

    private func fire() {
        guard phase == .aim, !oppGone else { return }
        let s = battle.turn, l = Ballistics.launch(battle.arena, side: s, aim: aims[s])
        let mega = megaArmed && battle.charge[s] >= 1
        let special = !mega && battle.stock[s][ammo.rawValue] > 0 ? ammo : Ammo.standard
        if (mode == .online && driver == .human) || (partyOnline && driver != .remote) {
            var m = NetMessage(t: "shot", round: round, k: battle.shot, p: bits(l.p0), v: bits(l.v0), yaw: aims[s].yaw, power: aims[s].power, mega: mega, ammo: special.rawValue)
            if mode == .party { m.seat = s; m.first = aims[s].target }
            net?.send(m, reliable: true)
        }
        launch(side: s, p0: l.p0, v0: l.v0, d: l.d, ammo: special, mega: mega)
    }

    private func launch(side: Int, p0: Vec3, v0: Vec3, d: Vec3, ammo shot: Ammo, mega: Bool) {
        let f = battle.fly(p0: p0, v0: v0, wind: wind, ammo: shot, mega: mega)
        flight = Flight(side: side, res: f.res, path: f.path, final: battle.wouldBreakHeart(f.res) != nil)
        phase = .flight
        ts = 1
        cam = .follow
        let h = SIMD3<Float>(Float(v0.x), 0, Float(v0.z))
        let fw = battle.arena.forward(side)
        ballDir = simd_length_squared(h) > 1e-8 ? simd_normalize(h) : SIMD3(Float(fw.x), 0, Float(fw.z))
        world.hidePreview()
        world.fireBall(from: p0, dir: d, side: side, style: ballStyle(for: side), ammo: f.res.ammo, mega: f.res.mega)
        sfx.play(.fire)
        thump(.heavy)
        pull = nil; timeLeft = nil; megaArmed = false; ammo = .standard
        refreshHUD()
    }

    private func impact() {
        guard let f = flight else { return }
        let res = f.res
        world.endBall()
        let chargeBefore = battle.charge
        let out = battle.apply(res)
        world.showImpact(res, outcome: out)
        world.showTarget(nil)
        for i in battle.castles.indices { world.setShield(i, on: battle.shield[i]) }
        if out.pickup != nil && !f.popped { world.popPickup() }
        let any = out.damage.contains { $0.cells > 0 }
        // The enemy this shot hurt most, hearts first; with none hurt, the one it was aimed at.
        let foes = battle.castles.indices.filter { $0 != f.side }
        let enemy = foes.max { (out.damage[$0].heart, out.damage[$0].cells) < (out.damage[$1].heart, out.damage[$1].cells) }
            .flatMap { out.damage[$0].cells > 0 || !out.damage[$0].crack.isEmpty ? $0 : nil } ?? aimedSeat(f.side)
        let dealt = out.damage[enemy].cells > 0 ? max(1, Int((Double(out.damage[enemy].cells) / Double(battle.castles[enemy].total) * 100).rounded())) : 0
        stats[f.side].shots += 1
        if dealt > 0 { stats[f.side].hits += 1; stats[f.side].bestHit = max(stats[f.side].bestHit, dealt) }
        if res.crit { stats[f.side].crits += 1 }
        if res.mega { stats[f.side].megas += 1 }
        if res.ammo != .standard { stats[f.side].specials += 1 }
        if out.pickup != nil { stats[f.side].pickups += 1 }
        stats[f.side].topStreak = max(stats[f.side].topStreak, battle.streak[f.side])
        let earned = mode == .challenge ? Challenge.points(dealt: dealt, crit: res.crit, streak: battle.streak[f.side]) : 0
        score += earned

        var msg = Tx.miss
        switch res.kind {
        case .out: break
        case .water: msg = battle.arena.isWater(res.pos.x, res.pos.z) ? Tx.water : Tx.moat
        case .ground, .castle:
            sfx.play(any ? .hit : .thud)
            shake = any ? (res.mega ? 1.4 : 0.9) : 0.3
            if any { thump(.rigid) }
            if dealt > 0 {
                msg = res.mega ? Tx.megaHit(dealt) : res.crit ? Tx.crit(dealt) : Tx.hit(dealt)
                if mode == .challenge { msg += "  ·  " + Tx.points(earned) }
                else if battle.streak[f.side] >= 2 { msg += "  ·  " + Tx.streak(battle.streak[f.side]) }
            } else if out.damage[f.side].cells > 0 { msg = Tx.ownCastle }
            if dealt == 0, !out.damage[enemy].crack.isEmpty { msg = Tx.stoneCracked }
            if !out.damage[enemy].decoys.isEmpty { msg = Tx.decoyFound + "  ·  " + msg }
            if out.damage[enemy].heart > 0 { msg = (battle.castles[enemy].heartLost ? Tx.heartBroken : Tx.heartHit) + "  ·  " + msg }
            else if out.damage[f.side].heart > 0 { msg = Tx.ownHeart }
            if out.shieldBroken != nil { msg = Tx.shieldBroken + "  ·  " + msg }
            if out.aegis != nil { msg = Tx.aegisUp + "  ·  " + msg }
        }
        if dealt == 0, out.damage[f.side].cells == 0, let k = out.pickup { msg = Tx.grabbed(k) }
        if res.crit { sfx.play(.crit) }
        for s in battle.castles.indices where chargeBefore[s] < 1 && battle.charge[s] >= 1 && driverOf(s) == .human && (mode != .challenge || s == 0) { sfx.play(.charged) }
        show(toast: msg)
        impactP = res.pos.f
        let h = SIMD3<Float>(Float(res.vel.x), 0, Float(res.vel.z))
        let fwd = battle.arena.forward(f.side)
        impactDir = simd_length_squared(h) > 1e-8 ? simd_normalize(h) : SIMD3(Float(fwd.x), 0, Float(fwd.z))
        impactA = 0
        cam = res.kind == .out ? .aim : .impact
        phase = .impact
        impactT = any ? (res.mega || res.ammo == .cluster ? 4.4 : 3.8) : 1.9
        slowT = any ? 0.8 : 0
        if f.final { impactT += 1.6; slowT = 2.2 }
        flight = nil
        refreshHUD()
    }

    /// The shot clock ran out: the turn passes without a shot.
    private func skipTurn(send: Bool) {
        guard phase == .aim else { return }
        if send && (mode == .online || partyOnline) {
            var m = NetMessage(t: "skip", round: round, k: battle.shot)
            if mode == .party { m.seat = battle.turn }
            net?.send(m, reliable: true)
        }
        battle.forfeitTurn()
        pull = nil; timeLeft = nil; megaArmed = false; ammo = .standard; skipped = true
        world.hidePreview()
        world.showTarget(nil)
        show(toast: Tx.timeUp)
        sfx.play(.thud)
        phase = .impact
        impactT = 1.4; slowT = 0
        refreshHUD()
    }

    private func endTurn() {
        if mode == .challenge {
            shotsTaken += 1
            let cleared = battle.castles[1].heartLost
            if cleared || shotsTaken >= Challenge.shots { finishSiege(cleared: cleared); return }
            battle.advance(by: 2)     // the target castle never shoots back, so the turn stays with the player
            beginTurn()
            return
        }
        if mode == .party { noteEliminations() }
        if let w = battle.winner() { gameOver(winner: w); return }
        finale = false
        battle.advance()
        beginTurn()
        if let g = battle.regrown {
            world.restoreBlocks(side: g.side, ids: [g.block])
            show(toast: Tx.heartRegrew)
            refreshHUD()
        }
    }

    /// Four castles: announces every heart that broke this turn and books the player's place if theirs did.
    private func noteEliminations() {
        let nm = names()
        for i in battle.castles.indices where battle.castles[i].heartLost && !outOrder.contains(i) {
            outOrder.append(i)
            let place = battle.castles.count - outOrder.count + 1
            if i == me {
                show(toast: Tx.youOut(place))
                sfx.play(.lose)
                bookParty(place: place)
            } else {
                show(toast: Tx.seatOut(nm[i], place))
            }
        }
    }

    private func bookParty(place: Int) {
        guard partyReward == nil, me < battle.castles.count else { return }
        var updated = profile
        let own = battle.castles[me]
        let facts = MatchFacts(heartPct: own.heartPct, castlePct: own.pct, decoysFooled: own.decoyRevealed.filter { $0 }.count)
        partyReward = updated.record(won: place == 1, mode: .party(place: place, online: net != nil), stats: stats[me], facts: facts)
        updated.save()
        profile = updated
    }

    private func enterOverState(lookingAt winner: Int) {
        phase = .over
        cam = .target
        camSide = winner
        viewSeat = mode == .party ? outOrder.last ?? battle.arena.across(winner) : battle.arena.across(winner)
        orbitA = battle.arena.facing(viewSeat) + (viewSeat == 0 ? 0.55 : -0.55)
        orbitH = 30; orbitR = 60
        pull = nil; timeLeft = nil; megaArmed = false; ammo = .standard; flight = nil; confirmQuit = false
        world.hidePreview()
        world.showTarget(nil)
        world.showPickup(nil)
        world.endBall()
    }

    private func present(_ info: OverInfo) {
        refreshHUD()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.phase == .over else { return }
            self.finale = false
            self.over = info
            if self.oppAgain { self.over?.detail = Tx.rematchWanted }
            self.screen = .over
        }
    }

    private func finishSiege(cleared: Bool) {
        if cleared {
            clearBonus = Challenge.clearBonus(unusedShots: Challenge.shots - shotsTaken)
            score += clearBonus
        }
        enterOverState(lookingAt: 0)
        var updated = profile
        let reward = updated.recordSiege(score: score, stats: stats[0])
        updated.save()
        profile = updated
        sfx.play(.win)
        var info = OverInfo(title: cleared ? Tx.siegeCleared : Tx.siegeOver, detail: Tx.siegeScore(score) + (cleared ? "  ·  " + Tx.clearBonus(clearBonus) : ""))
        info.stats = stats[0]
        info.reward = reward
        info.isSiege = true
        present(info)
    }

    private func gameOver(winner: Int, forfeit: Bool = false) {
        enterOverState(lookingAt: winner)
        let nm = names()
        if mode == .party {
            if winner == me { bookParty(place: 1) }
            let order = ([winner] + outOrder.reversed()).filter { $0 >= 0 && $0 < nm.count }
            var info = OverInfo(title: winner == me ? Tx.won : Tx.sideWon(nm[winner]), detail: Tx.placements(order.map { nm[$0] }))
            info.reward = partyReward
            info.stats = stats[me]
            sfx.play(winner == me ? .win : .lose)
            present(info)
            return
        }
        let p = battle.castles.map { Int(($0.pct * 100 + 1e-9).rounded(.down)) }
        var info = OverInfo(title: "", detail: forfeit ? Tx.forfeitWin : Tx.heartFell(nm[1 - winner]) + " " + Tx.standing(nm[0], p[0], nm[1], p[1]))
        if let mine = mySide {
            let won = winner == mine
            info.title = won ? Tx.won : Tx.lost
            sfx.play(won ? .win : .lose)
            var updated = profile
            let own = battle.castles[mine]
            let facts = MatchFacts(heartPct: own.heartPct, castlePct: own.pct, decoysFooled: own.decoyRevealed.filter { $0 }.count,
                                   friend: friendDesign != nil)
            if mode == .gauntlet && !forfeit {
                presentGauntlet(won: won, facts: facts, info: &info, profile: &updated)
                return
            }
            let rewardMode: RewardMode = mode == .online ? .online(opponent: rival?.trophies) : .computer(aiLevel)
            info.reward = updated.record(won: won, mode: rewardMode, stats: stats[mine], facts: facts, stage: stage,
                                         stageStars: won ? Stage.stars(ownPct: battle.castles[mine].pct) : 0)
            info.stats = stats[mine]
            info.rivalStats = stats[1 - mine]
            info.side = mine
            if let s = stage, won {
                info.title = Tx.stageWon(s.id)
                info.hasNextStage = s.id < Stage.all.count
                if s.id == Stage.all.count { info.detail = Tx.campaignDone }
            }
            updated.save()
            profile = updated
        } else {
            info.title = Tx.sideWon(nm[winner])
            info.stats = stats[0]
            info.rivalStats = stats[1]
            sfx.play(.win)
        }
        info.names = nm
        present(info)
    }

    private func presentGauntlet(won: Bool, facts: MatchFacts, info: inout OverInfo, profile updated: inout Profile) {
        let toppled = won ? gauntletRound : gauntletRound - 1
        info.isGauntlet = true
        info.gauntletNext = won
        info.reward = updated.recordGauntlet(won: won, toppled: toppled, stats: stats[0], facts: facts)
        info.stats = stats[0]
        info.rivalStats = stats[1]
        info.side = 0
        info.names = names()
        if won {
            let carry = battle.castles[0]
            let fixed = carry.repair(cells: Gauntlet.repairCells).reduce(0) { $0 + carry.blocks[$1].len }
            gauntletCarry = carry
            info.title = Tx.gauntletWon(gauntletRound)
            info.detail = Tx.gauntletCarry(fixed)
        } else {
            gauntletCarry = nil
            info.title = Tx.gauntletOver
            info.detail = Tx.gauntletToppled(toppled)
        }
        updated.save()
        profile = updated
        present(info)
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
        h.heart = battle.castles.map { $0.heartPct }
        h.charge = battle.charge
        h.streak = battle.streak
        h.shield = battle.shield
        h.pickup = battle.pickup?.kind
        h.modifier = battle.rules.modifier
        let s = battle.turn
        h.turnSide = s
        h.finished = phase == .over
        if oppGone { h.turnText = Tx.opponentLeft } else {
            switch phase {
            case .flight: h.turnText = Tx.inFlight
            case .impact: h.turnText = skipped ? Tx.timeUp : Tx.inFlight
            case .over: h.turnText = Tx.gameOver
            default:
                switch driver {
                case .human: h.turnText = mode == .local ? Tx.turnOf(h.names[s]) : mode == .challenge ? Tx.dailySiege : Tx.yourTurn
                case .computer: h.turnText = mode == .party ? Tx.turnOf(h.names[s]) : Tx.computerAiming
                case .remote: h.turnText = mode == .party ? Tx.turnOf(h.names[s]) : Tx.opponentAiming
                }
            }
        }
        let hd = Ballistics.heading(battle.arena, side: s, aim: aims[s]), f = wind.x * cos(hd) + wind.z * sin(hd), r = wind.z * cos(hd) - wind.x * sin(hd)
        h.windAngle = atan2(r, f) * 180 / .pi
        h.windPower = Int(((f * f + r * r).squareRoot() / (K.wind * 1.414) * 10).rounded())
        let humanAiming = phase == .aim && driver == .human && !oppGone && !autoPlay
        h.canInspect = phase == .aim
        h.inspecting = cam == .target && phase == .aim
        h.canAim = humanAiming && cam == .aim
        h.megaVisible = humanAiming
        h.megaCharge = battle.charge[s]
        h.megaReady = humanAiming && battle.charge[s] >= 1
        h.stock = humanAiming ? battle.stock[s] : [0, 0, 0, 0]
        h.hasTarget = phase == .aim && battle.goldTarget() != nil
        h.out = battle.castles.map { $0.heartLost }
        if mode == .party {
            h.me = me
            h.targets = humanAiming ? battle.enemies : []
            h.target = aimedSeat(s)
        }
        if mode == .challenge {
            h.score = score
            h.shotsTaken = min(Challenge.shots, shotsTaken + (phase == .flight || phase == .impact ? 1 : 0))
            h.charge[1] = 0; h.streak[1] = 0      // the target castle has no cannon to charge
        }
        if h != hud { hud = h }
    }

    // MARK: Touch input

    /// Pull back anywhere on the scene and release: sideways sets the direction, length sets the power.
    func drag(start: CGPoint, location: CGPoint) {
        if cam == .target {
            if let last = lastDrag {
                orbitA += Double(location.x - last.x) * 0.008 * (viewSeat == 0 ? 1 : -1)
                orbitH = min(70, max(6, orbitH + Double(location.y - last.y) * 0.14))
            }
            lastDrag = location
            return
        }
        guard phase == .aim, driver == .human, cam == .aim, !oppGone, plan == nil else { return }
        let maxPull = min(260, Double(viewSize.height) * 0.62)
        let dx = Double(location.x - start.x), dy = Double(location.y - start.y)
        let power = min(1, max(0, dy / maxPull)) * 100
        let yaw = min(K.maxYaw, max(-K.maxYaw, -dx * 0.14))
        let armed = power >= 6
        let s = battle.turn
        if armed { aims[s] = Aim(yaw: yaw, power: power, target: aims[s].target); aimDirty = true; showPreview(side: s) } else { world.hidePreview() }
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

    /// Dotted start of the flight. Beginners playing an easy computer see more of it.
    private func showPreview(side s: Int) {
        let l = Ballistics.launch(battle.arena, side: s, aim: aims[s])
        let dots = (mode == .ai || mode == .campaign || mode == .gauntlet || mode == .party) && aiLevel == .kolay ? 36 : 20
        var x = l.p0.x, y = l.p0.y, z = l.p0.z, vx = l.v0.x, vy = l.v0.y, vz = l.v0.z
        var pts: [SIMD3<Float>] = []
        for i in 1...(dots * 9) {
            vx += wind.x * K.dt; vy -= battle.rules.gravity * K.dt; vz += wind.z * K.dt
            x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
            if y < 0.5 { break }
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
        rival = nil
        partyPeers = [:]; hostNonce = 0
    }

    private func netConnected() {
        oppGone = false
        round = 0
        lobby.busy = true
        if lobby.isParty {
            partyLobbyChanged()
        } else {
            myNonce = UInt32.random(in: 1...UInt32.max)
            lobby.status = Tx.opponentFound
        }
        sendHello()
    }

    private func sendHello() {
        net?.send(NetMessage(t: "hello", nonce: myNonce, name: profile.name, trophies: profile.trophies, level: profile.level, design: profile.castle.encoded,
                             rules: K.rulesVersion), reliable: true)
    }

    /// Four-castle lobby: someone joined or left. The nearby host starts by hand; on Game Center the
    /// host (highest nonce) starts once everyone matched has said hello.
    private func partyLobbyChanged() {
        guard lobby.isParty, screen == .lobby, let net else { return }
        if lobby.kind == .partyJoin {
            lobby.status = Tx.waitingHost
            return
        }
        lobby.players = partyPeers.count + 1
        lobby.status = Tx.partyPlayers(lobby.players)
        if lobby.kind == .partyHost {
            lobby.canStart = !partyPeers.isEmpty
            lobby.busy = partyPeers.isEmpty
        } else if net.peerCount > 0, partyPeers.count >= net.peerCount {
            isHost = partyPeers.keys.allSatisfy { $0 < myNonce }
            if isHost && round == 0 { hostParty() }
        }
    }

    /// The nearby host's Start button.
    func startPartyNow() {
        guard lobby.kind == .partyHost, !partyPeers.isEmpty else { return }
        (net as? NearbyTransport)?.close()
        hostParty()
    }

    /// The host seats everyone (itself first, computers in the empty seats) and starts a round.
    private func hostParty() {
        isHost = true
        round += 1
        if round == 1 {
            seats = [SeatInfo(nonce: myNonce, name: profile.name, level: profile.level, design: profile.castle.encoded)]
            seats += partyPeers.values.sorted { $0.nonce < $1.nonce }.prefix(3)
            var picks = Presets.all.shuffled()
            while seats.count < 4 { seats.append(SeatInfo(nonce: 0, name: Tx.seatName(seats.count), level: 1, design: picks.removeFirst().encoded)) }
        }
        let seed = UInt32.random(in: 0...UInt32.max), first = Int.random(in: 0..<4)
        var m = NetMessage(t: "start", nonce: myNonce, seed: seed, round: round, first: first)
        m.seats = seats
        net?.send(m, reliable: true)
        let gone = seatGone
        startParty(seed: seed, me: 0, first: first, round: round)
        if gone.count == seats.count { seatGone = gone }
    }

    /// Every device says it is still there; the host takes over the seats of players who go quiet,
    /// and the others end the match if the host does.
    private func heartbeat(_ dt: Double) {
        clock += dt
        pingT -= dt
        if pingT <= 0 {
            pingT = 1.5
            net?.send(NetMessage(t: "ping", nonce: myNonce), reliable: false)
        }
        guard phase != .over, phase != .menu else { return }
        if isHost {
            for i in seats.indices where i != me && seats[i].nonce != 0 && !seatGone[i] && clock - (lastSeen[seats[i].nonce] ?? clock) > 7 {
                seatLeft(i)
            }
        } else if hostNonce != 0, clock - (lastSeen[hostNonce] ?? clock) > 7 {
            hostGone()
        }
    }

    private func seatLeft(_ i: Int) {
        guard seats.indices.contains(i), !seatGone[i] else { return }
        seatGone[i] = true
        var m = NetMessage(t: "bot")
        m.seat = i
        net?.send(m, reliable: true)
        show(toast: Tx.playerLeft(seats[i].name.isEmpty ? Tx.seatName(i) : seats[i].name))
        if phase == .aim, battle.turn == i, isHost {
            pendingShot = nil
            beginTurn()
        } else { refreshHUD() }
    }

    private func hostGone() {
        guard mode == .party, phase != .over else { return }
        hostNonce = 0
        enterOverState(lookingAt: me)
        var info = OverInfo(title: Tx.gameOver, detail: Tx.hostLeft)
        info.reward = partyReward
        present(info)
    }

    private func netLost() {
        if lobby.isParty {
            if screen == .lobby {
                if lobby.kind == .partyJoin || net?.peerCount == 0 { lobby.status = Tx.connectionLost; lobby.busy = false }
                return
            }
            // Online four-castle match: a joiner has lost the host; the host plays on against computers.
            if !isHost { hostGone() } else { for i in seats.indices where i != me && seats[i].nonce != 0 { seatLeft(i) } }
            return
        }
        oppGone = true
        if screen == .lobby {
            lobby.status = Tx.connectionLost
            lobby.busy = false
        } else if screen == .playing, phase != .over, phase != .menu {
            // The opponent walked out mid-match: the win goes to the player who stayed.
            show(toast: Tx.opponentLeft)
            gameOver(winner: me, forfeit: true)
        } else {
            refreshHUD()
        }
    }

    private func hostNewRound() {
        round += 1
        let seed = UInt32.random(in: 0...UInt32.max), first = (round + 1) % 2
        net?.send(NetMessage(t: "start", seed: seed, round: round, first: first), reliable: true)
        startGame(.online, seed: seed, me: 0, first: first, round: round, designs: [profile.castle, rival?.design ?? .classic])
        announceRival()
    }

    private func announceRival() {
        guard let r = rival, !r.name.isEmpty else { return }
        show(toast: Tx.versus(r.name, Tx.league(League.of(r.trophies)), r.level))
    }

    private func netMessage(_ m: NetMessage) {
        if let n = m.nonce { lastSeen[n] = clock }
        if lobby.isParty { partyMessage(m); return }
        switch m.t {
        case "hello":
            guard let n = m.nonce else { return }
            if n == myNonce { netConnected(); return }
            guard m.rules == K.rulesVersion else {
                // The other device plays by different rules; a match between them would not stay in step.
                stopNet()
                lobby.status = Tx.versionMismatch
                lobby.busy = false
                return
            }
            // What the opponent tells us about themselves is shown, never trusted for anything else.
            // Their castle is checked against the building rules; anything else becomes the classic layout.
            rival = (Profile.cleanName(m.name ?? ""), min(100_000, max(0, m.trophies ?? 0)), min(999, max(1, m.level ?? 1)),
                     CastleDesign(encoded: m.design ?? []) ?? .classic)
            isHost = myNonce > n
            if isHost && round == 0 { hostNewRound() }
        case "start":
            guard !isHost, let seed = m.seed, let r = m.round, let first = m.first, first == 0 || first == 1 else { return }
            startGame(.online, seed: seed, me: 1, first: first, round: r, designs: [rival?.design ?? .classic, profile.castle])
            announceRival()
        case "aim":
            guard phase == .aim, driver == .remote, let y = m.yaw, let p = m.power, y.isFinite, p.isFinite else { return }
            remoteAim = Aim(yaw: min(K.maxYaw, max(-K.maxYaw, y)), power: min(100, max(0, p)))
        case "shot", "skip":
            pendingShot = m
            checkRemote()
        case "again":
            guard m.round == round else { return }
            oppAgain = true
            if isHost && wantAgain { hostNewRound() } else if !wantAgain, over != nil { over?.detail = Tx.rematchWanted }
        default: break
        }
    }

    private func partyMessage(_ m: NetMessage) {
        switch m.t {
        case "hello":
            guard let n = m.nonce, n != myNonce else { return }
            guard m.rules == K.rulesVersion else { return }
            if partyPeers[n] == nil && partyPeers.count < 3 && round == 0 {
                partyPeers[n] = SeatInfo(nonce: n, name: Profile.cleanName(m.name ?? ""), level: min(999, max(1, m.level ?? 1)),
                                         design: (CastleDesign(encoded: m.design ?? []) ?? .classic).encoded)
                sendHello()
            }
            partyLobbyChanged()
        case "start":
            guard !isHost, let seed = m.seed, let r = m.round, let first = m.first, let list = m.seats, list.count == 4, first >= 0, first < 4,
                  let mine = list.firstIndex(where: { $0.nonce == myNonce }) else { return }
            hostNonce = m.nonce ?? 0
            seats = list.map { SeatInfo(nonce: $0.nonce, name: Profile.cleanName($0.name), level: min(999, max(1, $0.level)),
                                        design: (CastleDesign(encoded: $0.design) ?? .classic).encoded) }
            let gone = seatGone
            startParty(seed: seed, me: mine, first: first, round: r)
            if gone.count == seats.count { seatGone = gone }
        case "aim":
            guard mode == .party, phase == .aim, driver == .remote, m.seat == battle.turn, let y = m.yaw, let p = m.power, y.isFinite, p.isFinite else { return }
            remoteAim = Aim(yaw: min(K.maxYaw, max(-K.maxYaw, y)), power: min(100, max(0, p)), target: m.first ?? -1)
            if let t = m.first, battle.enemies.contains(t) { aims[battle.turn].target = t }
        case "shot", "skip":
            guard mode == .party else { return }
            pendingShot = m
            checkRemote()
        case "bot":
            guard let i = m.seat, seatGone.indices.contains(i), !seatGone[i] else { return }
            seatGone[i] = true
            show(toast: Tx.playerLeft(seats[i].name.isEmpty ? Tx.seatName(i) : seats[i].name))
            refreshHUD()
        default: break
        }
    }

    /// Plays the opponent's move (a shot or a timed-out turn) once it has arrived and it is their turn here too.
    private func checkRemote() {
        guard mode == .online || partyOnline, phase == .aim, driver == .remote, let m = pendingShot, m.round == round, m.k == battle.shot else { return }
        if mode == .party, m.seat != battle.turn { return }
        if m.t == "skip" { pendingShot = nil; skipTurn(send: false); return }
        guard let pb = m.p, let vb = m.v, pb.count == 3, vb.count == 3 else { return }
        let p0 = Vec3(x: Double(bitPattern: pb[0]), y: Double(bitPattern: pb[1]), z: Double(bitPattern: pb[2]))
        let v0 = Vec3(x: Double(bitPattern: vb[0]), y: Double(bitPattern: vb[1]), z: Double(bitPattern: vb[2]))
        let sp = v0.length
        guard [p0.x, p0.y, p0.z, sp].allSatisfy({ $0.isFinite }), sp >= 1, sp <= K.vMax + 1 else { return }
        pendingShot = nil
        let s = battle.turn
        if let y = m.yaw, let p = m.power, y.isFinite, p.isFinite {
            let t = mode == .party && battle.enemies.contains(m.first ?? -1) ? m.first! : aims[s].target
            aims[s] = Aim(yaw: min(K.maxYaw, max(-K.maxYaw, y)), power: min(100, max(0, p)), target: t)
        }
        launch(side: s, p0: p0, v0: v0, d: Vec3(x: v0.x / sp, y: v0.y / sp, z: v0.z / sp), ammo: Ammo(rawValue: m.ammo ?? 0) ?? .standard, mega: m.mega == true)
    }

    // MARK: Frame update

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, max(0, now - lastTime))
        lastTime = now
        update(dt)
    }

    private func update(_ dt: Double) {
        for s in aims.indices where s < world.cannons.count {
            world.cannons[s].pose(heading: Ballistics.heading(battle.arena, side: s, aim: aims[s]), yaw: aims[s].yaw, dt: Float(dt))
        }
        if partyOnline { heartbeat(dt) }
        if phase == .aim {
            let s = battle.turn
            if var p = plan {
                p.t += dt
                let k = min(1, p.t / 1.5), e = k * k * (3 - 2 * k)
                aims[s] = Aim(yaw: p.from.yaw + (p.to.yaw - p.from.yaw) * e, power: p.from.power + (p.to.power - p.from.power) * e, target: p.to.target)
                plan = p
                if p.t > 1.9 { plan = nil; fire() }
            } else if driver == .remote, let r = remoteAim {
                let k = 1 - exp(-10 * dt)
                aims[s].yaw += (r.yaw - aims[s].yaw) * k
                aims[s].power += (r.power - aims[s].power) * k
            } else if driver == .human {
                if mode == .online || partyOnline {
                    aimSendT -= dt
                    if aimDirty && aimSendT <= 0 {
                        aimDirty = false; aimSendT = 0.14
                        var m = NetMessage(t: "aim", yaw: aims[s].yaw, power: aims[s].power)
                        if mode == .party { m.seat = s; m.first = aims[s].target }
                        net?.send(m, reliable: false)
                    }
                }
                if timeLeft != nil && !confirmQuit { runShotClock(dt) }
            }
        }
        if phase == .flight, var f = flight {
            let n = f.res.steps
            ts = (Double(n) - f.i < 34 && f.res.kind != .out) ? 0.4 : 1
            if f.final && Double(n) - f.i < 120 {
                ts = 0.3
                if cam != .finale {
                    cam = .finale
                    finale = true
                    sfx.play(.charged)
                }
            }
            f.i = min(Double(n), f.i + dt * 120 * ts)
            let i0 = min(n - 1, Int(f.i)), fr = Float(f.i - Double(i0))
            let a = f.path[i0].f, b = f.path[i0 + 1].f
            world.ball.simdPosition = a + (b - a) * fr
            let d = SIMD3<Float>(b.x - a.x, 0, b.z - a.z)
            if simd_length_squared(d) > 1e-10 { ballDir = simd_normalize(simd_mix(ballDir, simd_normalize(d), SIMD3(repeating: Float(1 - exp(-6 * dt))))) }
            if let c = f.res.collectedAt, !f.popped, f.i >= Double(c) {
                f.popped = true
                world.popPickup()
                sfx.play(.charged)
                if let k = battle.pickup?.kind { show(toast: Tx.grabbed(k)) }
            }
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

    private func runShotClock(_ dt: Double) {
        turnT -= dt
        let left = max(0, Int(turnT.rounded(.up)))
        if left != timeLeft {
            timeLeft = left
            if left > 0 && left <= 5 { sfx.play(.tick) }
        }
        guard turnT <= 0 else { return }
        // A pull that is already drawn goes off; otherwise the turn is lost.
        if let p = pull, p.armed { dragEnded() } else { skipTurn(send: true) }
    }

    /// True when a point is above, or just beside, any castle.
    private func overCastle(_ p: SIMD3<Float>) -> Bool {
        battle.castles.contains { c in
            let l = c.local(Double(p.x), Double(p.z))
            return l.x > -5 && l.x < Double(K.gw) + 3 && l.z > -3 && l.z < Double(K.gd) + 3
        }
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
            let side = min(camSide, aims.count - 1)
            let y = Float(Ballistics.heading(battle.arena, side: side, aim: aims[side]) + aims[side].yaw * .pi / 180)
            let h = SIMD3<Float>(cos(y), 0, sin(y)), pv = battle.arena.pivot(side).f
            tPos = pv - h * 7.5 + SIMD3(0, 3.6, 0)
            tLook = pv + h * 40
            tLook.y = 4.2
            k = 4.5
            wantFov = 46
        case .target:
            if phase == .over { orbitA += dt * 0.12 }
            let c = battle.arena.castleCenter(min(viewSeat, battle.castles.count - 1)).f
            tPos = SIMD3(c.x + Float(cos(orbitA) * orbitR), Float(orbitH), c.z + Float(sin(orbitA) * orbitR))
            tLook = SIMD3(c.x, 7, c.z)
            if screen == .builder {
                // The grid covers the left of the screen, so frame the castle in the right half.
                let f = simd_normalize(SIMD3<Float>(tLook.x - tPos.x, 0, tLook.z - tPos.z))
                let left = SIMD3<Float>(f.z, 0, -f.x) * Float(orbitR) * 0.3
                tPos += left; tLook += left
            }
            k = 4
        case .follow:
            let b = world.ball.simdPosition, d = ballDir
            tPos = b - d * 13 + SIMD3(0, 5, 0) + SIMD3(-d.z, 0, d.x) * 3
            tLook = b + d * 6
            // stay above the walls instead of flying through them
            if overCastle(tPos) { tPos.y = max(tPos.y, 25) }
            k = 7
        case .finale:
            let b = world.ball.simdPosition, d = ballDir
            tPos = b + SIMD3(-d.z, 0, d.x) * 15 - d * 5 + SIMD3(0, 4, 0)
            tLook = b + d * 2
            if overCastle(tPos) { tPos.y = max(tPos.y, 22) }
            k = 5
            wantFov = 38
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

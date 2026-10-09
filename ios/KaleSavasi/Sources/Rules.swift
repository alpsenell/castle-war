import Foundation

// Game rules with no rendering: ballistics up to the first touch, what a settled castle is worth,
// power-ups and the computer player. The flight is deterministic so every device draws the same
// arc; what happens after the ball touches a brick is played by the physics world, and the rules
// read the castles back from its `SettleReport`.

enum K {
    static let gw = BK.depth * Int(BK.unit), gd = BK.width * Int(BK.unit)   // castle footprint in world units: depth, width
    static let grav = 12.0, dt = 1.0 / 120.0
    static let ballR = 0.7
    static let vMin = 20.0, vMax = 42.0, pitch = 32.0
    static let wind = 1.4
    static let front = 40.0                        // |x| of each castle's front face
    static let xEdge = front + Double(gw)          // |x| of the back face
    static let river = 8.0
    static let lake = 13.0                           // radius of the lake in the middle of a four-castle arena
    static let platX = 31.0, platHalf = 3.0, platTop = 2.4
    static let pivotY = platTop + 1.25, muzzle = 2.6
    static let maxYaw = 35.0
    static let critRange = 3.2, critBoost = 1.25     // gold target: how close counts, and the ball's extra mass
    static let megaBoost = 2.2                       // ball mass of a charged mega shot
    static let turnSeconds = 20.0                    // shot clock for timed modes
    static let homing = 7.0                          // steering pull of a homing shot
    static let pierce = 2                            // bricks a piercer goes straight through
    static let pickupRange = 2.8                     // how close a shot must pass to grab a balloon
    static let shieldFactor = 0.6                    // impulses against a shielded castle
    static let homeReach = 0.6                       // a brick further than this from home no longer counts as standing
    static let heartReach = 3.0                      // a heart or decoy knocked further than this is lost
    static let heartFloor = 1.0 / 3                  // a castle standing below this share loses its heart
    static let upright = 0.9                         // cosine of the tilt a standing brick may have
    static let repairShare = 0.12                    // share of a castle's mass a repair balloon puts back
    static let settleSeconds = 6.0                   // longest a shot's physics may run
    static let breakScale = 0.75                     // overall scale on `BrickMaterial.breakImpulse`
    static let ballMass: Float = 20                  // a cannonball's mass in the physics world
    static let maxChips = 90                         // fragments alive at once
    static let brickGravity = 20.0                  // the physics world's gravity, stronger than the flight's so bricks fall snappily
    static let rulesVersion = 6                      // bumped whenever an online match would play out differently
}

struct Mulberry32 {
    private var a: UInt32
    init(_ seed: UInt32) { a = seed }
    mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}

struct Vec3: Equatable {
    var x = 0.0, y = 0.0, z = 0.0
    var length: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Direction in degrees (positive = right of the shooter) and power 0...100, relative to the
/// castle aimed at. `target` -1 means the castle across the field.
struct Aim: Equatable {
    var yaw = 0.0
    var power = 50.0
    var target = -1
}

/// What one shot did to one castle, read from the settled bricks.
struct Damage {
    /// Share of the castle's mass that stood before the shot and no longer does.
    var lost = 0.0
    /// Bricks the shot broke, and bricks it knocked out of place without breaking.
    var broken: [Int] = []
    var moved = 0
    /// Share of the heart's health lost.
    var heart = 0.0
    /// Iron bricks that cracked and still stand.
    var crack: [Int] = []
    /// Decoy hearts this shot gave away, as indices into `Castle.decoys`.
    var decoys: [Int] = []
    /// So little of the castle stands that its heart fell with it.
    var crumbled = false
    var hit: Bool { lost > 0.002 || !broken.isEmpty || moved > 0 || !crack.isEmpty || heart > 0 }
}

enum HitKind { case out, water, ground, castle }

/// Special shots. Each side carries one of each per match.
enum Ammo: Int, CaseIterable, Identifiable {
    case standard = 0, cluster, piercer, homing
    var id: Int { rawValue }
    static let specials: [Ammo] = [.cluster, .piercer, .homing]
}

/// Balloons that drift over the river. A shot that passes close grabs the bonus and flies on.
enum PickupKind: Int, CaseIterable { case repair, shield, charge }

struct Pickup: Equatable {
    var kind: PickupKind
    var pos: Vec3
    var born: Int
}

/// Match-wide twists.
enum Modifier: Int, CaseIterable, Identifiable {
    case none = 0, storm, calm, lowGravity, megaRush, bigBlast
    var id: Int { rawValue }
}

struct MatchRules: Equatable {
    var gravity = K.grav
    var windScale = 1.0
    /// Ball weight: "big blast" matches fire heavier balls.
    var blastScale = 1.0
    var megaRate = 1.0
    var pickups = true
    var modifier = Modifier.none

    init(_ m: Modifier = .none, pickups: Bool = true) {
        modifier = m
        self.pickups = pickups
        switch m {
        case .none: break
        case .storm: windScale = 2.1
        case .calm: windScale = 0
        case .lowGravity: gravity = 9
        case .megaRush: megaRate = 2
        case .bigBlast: blastScale = 1.3
        }
    }
}

struct ShotResult {
    var steps: Int
    var pos: Vec3
    var vel: Vec3
    var kind: HitKind
    var side: Int
    /// The brick of castle `side` the ball touched first.
    var brick: Int?
    /// That brick is a heart or a decoy: the shot may be the last one.
    var crystal = false
    var shooter = 0
    var ammo = Ammo.standard
    var mega = false
    var crit = false
    /// Step at which the shot grabbed the balloon, if it did.
    var collectedAt: Int?
}

/// Everything one shot changed.
struct ShotOutcome {
    var damage: [Damage]
    /// Bricks of the shooter's castle the repair balloon put back.
    var repaired: [Int] = []
    var pickup: PickupKind?
    var shieldBroken: Int?
    /// Side whose aegis heart just threw up a shield.
    var aegis: Int?
}

// MARK: - Arena

/// Where the castles stand: two facing across the river, or four around a lake.
/// Seat 0 is always west of the middle; the others follow round the field.
struct Arena: Equatable {
    let seats: Int
    static let duel = Arena(seats: 2), party = Arena(seats: 4)

    /// Unit vector from a seat toward the middle of the field, kept exact so a duel plays out
    /// the same as it always has.
    func forward(_ seat: Int) -> (x: Double, z: Double) {
        let quarter = seats == 2 ? seat * 2 : seat
        return [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)][quarter % 4]
    }
    /// Unit vector to the right of a castle's front, seen from behind it.
    func right(_ seat: Int) -> (x: Double, z: Double) { let f = forward(seat); return (-f.z, f.x) }

    /// The world direction (radians, from +x toward +z) a seat faces.
    func facing(_ seat: Int) -> Double { let f = forward(seat); return atan2(f.z, f.x) }

    func pivot(_ seat: Int) -> Vec3 { let f = forward(seat); return Vec3(x: -K.platX * f.x, y: K.pivotY, z: -K.platX * f.z) }

    /// Centre of a seat's castle on the ground.
    func castleCenter(_ seat: Int) -> Vec3 {
        let f = forward(seat), d = K.front + Double(K.gw) / 2
        return Vec3(x: -d * f.x, y: 0, z: -d * f.z)
    }

    /// The direction a cannon points at aim zero when it targets another castle.
    func heading(from seat: Int, to target: Int) -> Double {
        guard target != seat, target >= 0, target < seats else { return facing(seat) }
        if seats == 2 { return facing(seat) }
        let p = pivot(seat), c = castleCenter(target)
        return atan2(c.z - p.z, c.x - p.x)
    }

    /// The castle a seat aims at before it picks one: the one across the field.
    func across(_ seat: Int) -> Int { seats == 2 ? 1 - seat : (seat + 2) % seats }

    func isWater(_ x: Double, _ z: Double) -> Bool {
        seats == 2 ? x > -K.river && x < K.river : x * x + z * z < K.lake * K.lake
    }
}

/// A castle's place on the field. Castle-local coordinates are those of `PlacedBrick.center`:
/// x from the back toward the enemy, y up, z from the owner's left, in world units.
struct CastleFrame {
    let corner: Vec3
    let fx, fz, rx, rz: Double

    init(seat: Int, arena: Arena) {
        let f = arena.forward(seat), r = arena.right(seat), half = Double(K.gd) / 2
        fx = f.x; fz = f.z; rx = r.x; rz = r.z
        corner = Vec3(x: -K.xEdge * f.x - half * r.x, y: 0, z: -K.xEdge * f.z - half * r.z)
    }

    func world(_ l: SIMD3<Double>) -> Vec3 {
        Vec3(x: corner.x + l.x * fx + l.z * rx, y: l.y, z: corner.z + l.x * fz + l.z * rz)
    }
    func local(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> {
        let dx = x - corner.x, dz = z - corner.z
        return SIMD3(dx * fx + dz * fz, y, dx * rx + dz * rz)
    }
    /// A world direction in the castle's frame.
    func localDir(_ v: Vec3) -> SIMD3<Double> { SIMD3(v.x * fx + v.z * fz, v.y, v.x * rx + v.z * rz) }
    /// Turn about y that takes castle-local axes to world axes.
    var yaw: Double { atan2(-fz, fx) }
}

// MARK: - Brick bodies

/// Rotates `v` by the unit quaternion `q` (x, y, z, w); `inverse` turns the other way.
@inline(__always) func rotate(_ v: SIMD3<Double>, by q: SIMD4<Float>, inverse: Bool = false) -> SIMD3<Double> {
    let s: Double = inverse ? -1 : 1
    let u = SIMD3(Double(q.x) * s, Double(q.y) * s, Double(q.z) * s), w = Double(q.w)
    func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> { SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
    let t = cross(u, v) * 2
    return v + t * w + cross(u, t)
}

extension BrickShape {
    /// The solid boxes of a brick at rotation 0, as centre and half size in world units about
    /// the brick's centre. Shots and bodies collide with these.
    var boxes: [(c: SIMD3<Double>, h: SIMD3<Double>)] {
        let s = size, k = BK.step
        let h = SIMD3(Double(s.x), Double(s.y), Double(s.z)) * (k / 2)
        switch self {
        case .arch:
            let leg = h.z / 3
            return [(SIMD3(0, -h.y / 4, -h.z + leg / 2), SIMD3(h.x, h.y * 0.75, leg / 2)),
                    (SIMD3(0, -h.y / 4, h.z - leg / 2), SIMD3(h.x, h.y * 0.75, leg / 2)),
                    (SIMD3(0, h.y * 0.75, 0), SIMD3(h.x, h.y / 4, h.z))]
        case .coneRoof: return [(SIMD3(0, -h.y * 0.3, 0), SIMD3(h.x * 0.62, h.y * 0.7, h.z * 0.62))]
        case .pyramidRoof: return [(SIMD3(0, -h.y * 0.3, 0), SIMD3(h.x * 0.7, h.y * 0.7, h.z * 0.7))]
        case .wedge: return [(SIMD3(-h.x * 0.25, -h.y * 0.25, 0), SIMD3(h.x * 0.75, h.y * 0.75, h.z))]
        case .moat: return []
        default: return [(SIMD3(0, 0, 0), h)]
        }
    }
    /// Radius of a sphere about the centre that holds the whole brick.
    var reach: Double { let s = size; return (Double(s.x * s.x + s.y * s.y + s.z * s.z)).squareRoot() * BK.step / 2 }
}

extension BrickPose {
    var pos: SIMD3<Double> { SIMD3(Double(p.x), Double(p.y), Double(p.z)) }
}

// MARK: - Castle state

/// What the heart can do besides being protected. Chosen in the builder, unlocked by level.
enum HeartKind: Int, CaseIterable, Identifiable {
    case crystal = 0, living, aegis, titan
    var id: Int { rawValue }
    /// Coins it costs on top of the free crystal heart.
    var cost: Int { [0, 80, 80, 100][rawValue] }
    var level: Int { [1, 4, 7, 10][rawValue] }
    /// Hits the heart crystal (and every decoy, so they still pass for it) takes before it breaks.
    var hp: Int { self == .titan ? 3 : 2 }
}

extension BrickDesign {
    /// Hit points a brick of this castle starts with: hearts and decoys take the heart type's.
    func hp(_ b: PlacedBrick) -> Int { b.material.isCrystal ? heart.hp : b.material.hp }

    /// Reads a castle in either flat form: bricks, or the piece layout from before bricks.
    static func decode(_ e: [Int]) -> BrickDesign? {
        if let d = BrickDesign(encoded: e) { return d }
        guard let old = CastleDesign(encoded: e) else { return nil }
        let d = BrickDesign(legacy: old)
        return d.problem == nil ? d : nil
    }
}

/// One castle in a match: the design as built and where every brick is now.
final class Castle {
    let side: Int
    let design: BrickDesign
    let frame: CastleFrame
    let heartKind: HeartKind
    /// Every brick at home, full health.
    let home: CastleSnapshot
    private(set) var snap: CastleSnapshot
    /// Mass of every brick that can stand or fall.
    let total: Double
    let heartIndex: Int?
    /// Decoy bricks, and which of them have been found out.
    let decoys: [Int]
    private(set) var decoyRevealed: [Bool]
    private(set) var heartGone = false
    /// Moat cells, as the minimum corner in snap steps.
    let moats: [(x: Int, z: Int)]
    /// Bricks each brick rests on, as built.
    let supporters: [[Int]]
    private(set) var pct = 1.0
    /// Bricks standing at home with nothing standing above them: where the gold target may go.
    private(set) var open: [Int] = []
    /// Local box around every brick still in one piece.
    private(set) var lo = SIMD3<Double>(0, 0, 0), hi = SIMD3<Double>(0, 0, 0)

    init(side: Int, design: BrickDesign, arena: Arena = .duel) {
        self.side = side
        self.design = design
        frame = CastleFrame(seat: side, arena: arena)
        heartKind = design.heart
        home = CastleSnapshot(design: design)
        snap = home
        let bricks = design.bricks
        total = max(0.001, bricks.reduce(0) { $0 + ($1.shape.isDecal ? 0 : $1.mass) })
        heartIndex = bricks.firstIndex { $0.material == .heart }
        decoys = bricks.indices.filter { bricks[$0].material == .decoy }
        decoyRevealed = Array(repeating: false, count: decoys.count)
        moats = bricks.filter { $0.shape.isDecal }.map { ($0.x, $0.z) }
        supporters = bricks.map { b in bricks.indices.filter { bricks[$0].supports(b) } }
        refresh()
    }

    var bricks: [PlacedBrick] { design.bricks }
    var heartLost: Bool { heartGone }

    /// The brick is in one piece, close to where it was built and the right way up.
    func isHome(_ i: Int) -> Bool {
        let p = snap.poses[i], h = home.poses[i]
        guard !p.broken else { return false }
        let d = p.pos - h.pos
        if (d * d).sum() > K.homeReach * K.homeReach { return false }
        let up = SIMD3<Double>(0, 1, 0)
        let a = rotate(up, by: p.q), b = rotate(up, by: h.q)
        return (a * b).sum() >= K.upright
    }

    /// A heart or decoy that is broken or knocked well away from its spot.
    func crystalGone(_ i: Int) -> Bool {
        let p = snap.poses[i]
        if p.broken { return true }
        let d = p.pos - home.poses[i].pos
        return (d * d).sum() > K.heartReach * K.heartReach
    }

    var heartPct: Double {
        guard let h = heartIndex, !heartGone, !crystalGone(h) else { return 0 }
        return Double(snap.poses[h].hp) / Double(max(1, design.hp(design.bricks[h])))
    }

    /// World centre of a brick where it is now.
    func center(_ i: Int) -> Vec3 { frame.world(snap.poses[i].pos) }

    /// Middle of the heart, if it still stands.
    var heartCenter: Vec3? { heartIndex.flatMap { heartGone ? nil : center($0) } }
    func decoyCenter(_ k: Int) -> Vec3? { crystalGone(decoys[k]) ? nil : center(decoys[k]) }

    /// Everything an attacker would take for the heart: the real one and the decoys not yet found out.
    var heartLookalikes: [Vec3] {
        var out: [Vec3] = []
        if let h = heartCenter { out.append(h) }
        for k in decoys.indices where !decoyRevealed[k] { if let c = decoyCenter(k) { out.append(c) } }
        return out
    }

    /// A world point in castle units: x from the back toward the front, z from the owner's left.
    func local(_ px: Double, _ pz: Double) -> (x: Double, z: Double) {
        let l = frame.local(px, 0, pz)
        return (l.x, l.z)
    }

    /// True when a castle's local x axis runs along the world x axis (seats west and east).
    var alongWorldX: Bool { frame.fx != 0 }

    func inMoat(_ px: Double, _ pz: Double) -> Bool {
        let (lx, lz) = local(px, pz), s = BK.step
        return moats.contains { lx >= Double($0.x) * s && lx <= Double($0.x + 2) * s && lz >= Double($0.z) * s && lz <= Double($0.z + 2) * s }
    }

    /// The brick a ball of radius `K.ballR` at this world point touches, if any.
    func hit(_ px: Double, _ py: Double, _ pz: Double) -> Int? {
        let r = K.ballR, l = frame.local(px, py, pz)
        if l.x < lo.x - r || l.y < lo.y - r || l.z < lo.z - r || l.x > hi.x + r || l.y > hi.y + r || l.z > hi.z + r { return nil }
        var best: Int?, bestD = r * r
        for (i, b) in design.bricks.enumerated() where !b.shape.isDecal {
            let p = snap.poses[i]
            if p.broken { continue }
            let d = l - p.pos, reach = b.shape.reach + r
            if (d * d).sum() > reach * reach { continue }
            let dl = rotate(d, by: p.q, inverse: true)
            for box in b.shape.boxes {
                let q = dl - box.c
                let c = SIMD3(min(max(q.x, -box.h.x), box.h.x), min(max(q.y, -box.h.y), box.h.y), min(max(q.z, -box.h.z), box.h.z))
                let e = q - c, dd = (e * e).sum()
                if dd <= bestD { bestD = dd; best = i }
            }
        }
        return best
    }

    /// Point on the ground-level box around the castle closest to a world point, and how far away it is.
    func distance(to w: Vec3) -> Double {
        let l = frame.local(w.x, w.y, w.z)
        let dx = max(lo.x - l.x, 0, l.x - hi.x), dz = max(lo.z - l.z, 0, l.z - hi.z), dy = max(0, l.y - hi.y)
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Reads a settled snapshot: what it cost the castle, which decoys it gave away.
    func settle(_ next: CastleSnapshot) -> Damage {
        guard next.poses.count == snap.poses.count else { return Damage() }
        var out = Damage()
        let beforePct = pct, beforeHeart = heartPct
        let wasHome = snap.poses.indices.map(isHome)
        let old = snap
        snap = next
        for i in snap.poses.indices where !design.bricks[i].shape.isDecal {
            let a = old.poses[i], b = snap.poses[i]
            if !a.broken && b.broken { out.broken.append(i) }
            else if !b.broken && b.hp < a.hp { out.crack.append(i) }
            else if wasHome[i] && !b.broken && !isHome(i) { out.moved += 1 }
        }
        refresh()
        // The heart is lost when it breaks, is knocked off its spot, or most of the castle is down.
        if let h = heartIndex, !heartGone {
            if crystalGone(h) { heartGone = true }
            else if pct < K.heartFloor {
                heartGone = true
                out.crumbled = true
                snap.poses[h].hp = 0
                refresh()
            }
        }
        for k in decoys.indices where !decoyRevealed[k] && crystalGone(decoys[k]) {
            decoyRevealed[k] = true
            out.decoys.append(k)
        }
        out.lost = max(0, beforePct - pct)
        out.heart = max(0, beforeHeart - heartPct)
        return out
    }

    /// Takes over the bricks of an earlier match against the same design: what fell stays down.
    func adopt(_ s: CastleSnapshot) {
        guard s.poses.count == snap.poses.count else { return }
        snap = s
        refresh()
    }

    /// A living heart mends one crack. Returns the heart brick if it did.
    func regrowHeart() -> Int? {
        guard heartKind == .living, let h = heartIndex, !heartGone, !crystalGone(h) else { return nil }
        let full = Int8(design.hp(design.bricks[h]))
        guard snap.poses[h].hp < full else { return nil }
        snap.poses[h].hp += 1
        refresh()
        return h
    }

    /// Puts broken and fallen bricks back where they were built, lowest first, as long as each
    /// has something to stand on and nothing lies in its spot. Returns what was put back.
    func repair(mass budget: Double) -> [Int] {
        var left = budget, out: [Int] = []
        let order = design.bricks.indices.sorted { (design.bricks[$0].y, $0) < (design.bricks[$1].y, $1) }
        for i in order where !design.bricks[i].shape.isDecal && !isHome(i) {
            let b = design.bricks[i]
            if b.material == .heart { continue }
            if b.mass > left { continue }
            guard b.y == 0 || supporters[i].contains(where: isHome) else { continue }
            guard spotIsFree(i) else { continue }
            snap.poses[i] = home.poses[i]
            left -= b.mass
            out.append(i)
            if left <= 0 { break }
        }
        if !out.isEmpty { refresh() }
        return out
    }

    /// No other brick lies across brick `i`'s home spot.
    private func spotIsFree(_ i: Int) -> Bool {
        let b = design.bricks[i], e = b.extent, s = BK.step
        let lo0 = SIMD3(Double(b.x), Double(b.y), Double(b.z)) * s + 0.15
        let hi0 = SIMD3(Double(b.x + e.x), Double(b.y + e.y), Double(b.z + e.z)) * s - 0.15
        for (k, o) in design.bricks.enumerated() where k != i && !o.shape.isDecal {
            let p = snap.poses[k]
            if p.broken { continue }
            let box = localBox(k)
            if box.lo.x < hi0.x && box.hi.x > lo0.x && box.lo.y < hi0.y && box.hi.y > lo0.y && box.lo.z < hi0.z && box.hi.z > lo0.z { return false }
        }
        return true
    }

    /// Local axis-aligned box around brick `k` where it is now.
    func localBox(_ k: Int) -> (lo: SIMD3<Double>, hi: SIMD3<Double>) {
        let p = snap.poses[k], s = design.bricks[k].shape.size
        let h = SIMD3(Double(s.x), Double(s.y), Double(s.z)) * (BK.step / 2)
        let ax = rotate(SIMD3(h.x, 0, 0), by: p.q), ay = rotate(SIMD3(0, h.y, 0), by: p.q), az = rotate(SIMD3(0, 0, h.z), by: p.q)
        let ext = SIMD3(abs(ax.x) + abs(ay.x) + abs(az.x), abs(ax.y) + abs(ay.y) + abs(az.y), abs(ax.z) + abs(ay.z) + abs(az.z))
        return (p.pos - ext, p.pos + ext)
    }

    /// Recomputes what depends on the snapshot: standing share, bounds and the open bricks.
    private func refresh() {
        var standing = 0.0
        var home = [Bool](repeating: false, count: design.bricks.count)
        lo = SIMD3(repeating: .greatestFiniteMagnitude); hi = SIMD3(repeating: -.greatestFiniteMagnitude)
        for (i, b) in design.bricks.enumerated() where !b.shape.isDecal {
            if snap.poses[i].broken { continue }
            let box = localBox(i)
            lo = SIMD3(min(lo.x, box.lo.x), min(lo.y, box.lo.y), min(lo.z, box.lo.z))
            hi = SIMD3(max(hi.x, box.hi.x), max(hi.y, box.hi.y), max(hi.z, box.hi.z))
            if isHome(i) { home[i] = true; standing += b.mass }
        }
        if lo.x > hi.x { lo = .zero; hi = .zero }
        pct = standing / total
        let bricks = design.bricks
        open = bricks.indices.filter { i in
            let b = bricks[i]
            guard home[i], b.y >= 2, !b.shape.isDecal else { return false }
            let e = b.extent
            return !bricks.indices.contains { j in
                guard j != i, home[j] else { return false }
                let o = bricks[j], f = o.extent
                return o.y >= b.y + e.y && o.x < b.x + e.x && b.x < o.x + f.x && o.z < b.z + e.z && b.z < o.z + f.z
            }
        }
    }

    // MARK: Structure, for the computer

    /// Mass that would be left with nothing under it if brick `i` went, counting only bricks at home.
    func unsupported(without i: Int) -> Double {
        let n = design.bricks.count
        var held = [Bool](repeating: false, count: n)
        let order = design.bricks.indices.sorted { design.bricks[$0].y < design.bricks[$1].y }
        var lost = 0.0
        for j in order where j != i && !design.bricks[j].shape.isDecal && isHome(j) {
            if design.bricks[j].y == 0 || supporters[j].contains(where: { held[$0] }) { held[j] = true }
            else { lost += design.bricks[j].mass }
        }
        return lost
    }
}

// MARK: - Battle

final class Battle {
    let seed: UInt32
    let first: Int
    let rules: MatchRules
    let arena: Arena
    private(set) var shot = 0
    let castles: [Castle]
    /// Whose turn it is. Seats whose heart is gone are skipped.
    private(set) var turn: Int
    /// Mega meter per side, 0...1. Fills by dealing damage and, more slowly, by taking it.
    private(set) var charge: [Double]
    /// Consecutive shots that damaged an enemy, per side.
    private(set) var streak: [Int]
    /// Special shots left, per side, indexed by `Ammo.rawValue`.
    private(set) var stock: [[Int]]
    /// A shielded castle takes the next shot's impulses at `K.shieldFactor`.
    private(set) var shield: [Bool]
    private(set) var pickup: Pickup?
    private var nextSpawn = 2
    /// An aegis heart shields its castle once per match.
    private(set) var aegisUsed: [Bool]
    /// Heart brick that mended at the start of the last turn, and on which side.
    private(set) var regrown: (side: Int, block: Int)?

    init(seed: UInt32, first: Int, designs: [BrickDesign] = [Presets.classic, Presets.classic], rules: MatchRules = MatchRules(), arena: Arena = .duel) {
        self.seed = seed
        self.first = first
        self.rules = rules
        self.arena = arena
        let n = arena.seats
        castles = (0..<n).map { Castle(side: $0, design: designs[min($0, designs.count - 1)], arena: arena) }
        turn = first % n
        charge = Array(repeating: 0, count: n)
        streak = Array(repeating: 0, count: n)
        stock = Array(repeating: [0, 1, 1, 1], count: n)
        shield = Array(repeating: false, count: n)
        aegisUsed = Array(repeating: false, count: n)
    }

    var designs: [BrickDesign] { castles.map { $0.design } }
    var snapshots: [CastleSnapshot] { castles.map { $0.snap } }

    /// Seats still in the match.
    var standing: [Int] { castles.indices.filter { !castles[$0].heartLost } }

    /// Every castle the side to move could shoot at.
    var enemies: [Int] { standing.filter { $0 != turn } }

    func wind() -> (x: Double, z: Double) {
        var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: shot + 1) &* 0x9E37_79B1))
        _ = r.next()
        let wx = (r.next() * 2 - 1) * K.wind * rules.windScale
        let wz = (r.next() * 2 - 1) * K.wind * rules.windScale
        return (wx, wz)
    }

    /// This turn's gold target: a brick on an enemy castle that is open to the sky.
    /// A shot that first touches within `K.critRange` of it is a critical hit.
    func goldTarget() -> Vec3? {
        var open: [Vec3] = []
        for e in enemies {
            let c = castles[e]
            for i in c.open { open.append(c.center(i)) }
        }
        guard !open.isEmpty else { return nil }
        var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: shot + 1) &* 0x85EB_CA6B))
        _ = r.next()
        return open[min(open.count - 1, Int(r.next() * Double(open.count)))]
    }

    /// Moves to the next turn (or skips the other side's, in the solo siege) and looks after the balloon.
    func advance(by n: Int = 1) {
        let count = castles.count
        for _ in 0..<n {
            shot += 1
            var next = (turn + 1) % count
            while next != turn && castles[next].heartLost { next = (next + 1) % count }
            turn = next
        }
        regrown = castles[turn].regrowHeart().map { (turn, $0) }
        guard rules.pickups else { return }
        if let p = pickup, shot - p.born >= 4 { pickup = nil; nextSpawn = shot + 2 }
        if pickup == nil && shot >= nextSpawn {
            var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: shot + 7) &* 0xC2B2_AE35))
            _ = r.next()
            let kind = PickupKind.allCases[min(PickupKind.allCases.count - 1, Int(r.next() * Double(PickupKind.allCases.count)))]
            let x = (r.next() * 2 - 1) * 7, y = 10 + r.next() * 8, z = (r.next() * 2 - 1) * 11
            pickup = Pickup(kind: kind, pos: Vec3(x: x, y: y, z: z), born: shot)
        }
    }

    /// Where a free flight first touches something.
    struct Trace {
        var steps: Int
        var pos: Vec3
        var vel: Vec3
        var kind: HitKind
        var side: Int
        var brick: Int?
        var collectedAt: Int?
    }

    /// Fixed-step flight up to the first touch. Uses only additions, multiplications, divisions
    /// and square roots, so two devices fed the same launch agree on it. `homeTo` steers a homing shot.
    func trace(p0: Vec3, v0: Vec3, wind w: (x: Double, z: Double), homeTo target: Vec3? = nil, path: UnsafeMutablePointer<[Vec3]>? = nil) -> Trace {
        var x = p0.x, y = p0.y, z = p0.z, vx = v0.x, vy = v0.y, vz = v0.z
        var kind = HitKind.out, side = -1, n = 1, brick: Int?
        var collectedAt: Int?
        let r = K.ballR, g = rules.gravity
        while n <= 8000 {
            var ax = w.x, az = w.z
            if vy < 0, let t = target {
                let dx = t.x - x, dz = t.z - z, d = (dx * dx + dz * dz).squareRoot()
                if d > 0.5 { ax += K.homing * dx / d; az += K.homing * dz / d }
            }
            vx += ax * K.dt; vy -= g * K.dt; vz += az * K.dt
            x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
            path?.pointee.append(Vec3(x: x, y: y, z: z))
            if collectedAt == nil, let p = pickup {
                let dx = x - p.pos.x, dy = y - p.pos.y, dz = z - p.pos.z
                if dx * dx + dy * dy + dz * dz <= K.pickupRange * K.pickupRange { collectedAt = n }
            }
            if y <= r {
                y = r
                if path != nil { path!.pointee[path!.pointee.count - 1].y = r }
                kind = arena.isWater(x, z) || castles.contains(where: { $0.inMoat(x, z) }) ? .water : .ground
                break
            }
            var touched = false
            for (i, c) in castles.enumerated() {
                if let b = c.hit(x, y, z) { kind = .castle; side = i; brick = b; touched = true; break }
            }
            if touched { break }
            if n > 40 && y < K.platTop + r {
                var onPlatform = false
                for i in castles.indices {
                    let p = arena.pivot(i)
                    if abs(x - p.x) < K.platHalf + r && abs(z - p.z) < K.platHalf + r { onPlatform = true; break }
                }
                if onPlatform { kind = .ground; break }
            }
            if x > 220 || x < -220 || z > 160 || z < -160 { kind = .out; break }
            n += 1
        }
        return Trace(steps: min(n, 8000), pos: Vec3(x: x, y: y, z: z), vel: Vec3(x: vx, y: vy, z: vz), kind: kind, side: side, brick: brick, collectedAt: collectedAt)
    }

    /// The flight of the side to move, with the path the ball takes.
    func fly(p0: Vec3, v0: Vec3, wind w: (x: Double, z: Double), ammo wanted: Ammo = .standard, mega wantsMega: Bool = false) -> (res: ShotResult, path: [Vec3]) {
        let shooter = turn
        let ammo = wanted != .standard && stock[shooter][wanted.rawValue] > 0 ? wanted : Ammo.standard
        let mega = wantsMega && ammo == .standard && charge[shooter] >= 1
        let target = goldTarget()
        var path = [p0]
        path.reserveCapacity(600)
        let t = trace(p0: p0, v0: v0, wind: w, homeTo: ammo == .homing ? target : nil, path: &path)
        var res = ShotResult(steps: t.steps, pos: t.pos, vel: t.vel, kind: t.kind, side: t.side, brick: t.brick)
        if t.kind == .castle, let b = t.brick { res.crystal = castles[t.side].bricks[b].material.isCrystal }
        res.shooter = shooter
        res.ammo = ammo
        res.mega = mega
        res.collectedAt = t.collectedAt
        if t.kind == .castle, t.side != shooter, let g = target {
            let dx = t.pos.x - g.x, dy = t.pos.y - g.y, dz = t.pos.z - g.z
            res.crit = dx * dx + dy * dy + dz * dz <= K.critRange * K.critRange
        }
        return (res, path)
    }

    /// What the physics world plays once the ball touches down, or nil when nothing can move:
    /// a splash, a miss, or a landing too far from every castle.
    func impact(for res: ShotResult) -> ShotImpact? {
        switch res.kind {
        case .out, .water: return nil
        case .ground: if !castles.contains(where: { $0.distance(to: res.pos) < 6 }) && !res.mega { return nil }
        case .castle: break
        }
        var imp = ShotImpact(point: res.pos, velocity: res.vel, ammo: res.ammo, mega: res.mega, crit: res.crit, shielded: shield)
        imp.weight = rules.blastScale
        if res.ammo == .cluster {
            // Two more balls either side of the first, a little behind it and fanning out.
            let v = res.vel, hl = max(0.001, (v.x * v.x + v.z * v.z).squareRoot())
            let dx = v.x / hl, dz = v.z / hl, lx = -dz, lz = dx, sp = v.length
            imp.extraBalls = [-1.0, 1.0].map { k in
                (Vec3(x: res.pos.x + lx * k * 1.5 - dx * 1.6, y: res.pos.y + 0.6, z: res.pos.z + lz * k * 1.5 - dz * 1.6),
                 Vec3(x: v.x + lx * k * sp * 0.14, y: v.y, z: v.z + lz * k * sp * 0.14))
            }
        }
        return imp
    }

    /// Applies a settled shot: damage, shields, the mega meter, streaks, ammo and any balloon it grabbed.
    func apply(_ res: ShotResult, settle: SettleReport?) -> ShotOutcome {
        let s = res.shooter, n = castles.count
        var out = ShotOutcome(damage: Array(repeating: Damage(), count: n))
        if let settle, settle.snapshots.count == n {
            for i in 0..<n { out.damage[i] = castles[i].settle(settle.snapshots[i]) }
        }
        for i in 0..<n where shield[i] && (out.damage[i].hit || (res.kind == .castle && res.side == i)) {
            shield[i] = false
            out.shieldBroken = i
        }
        for i in 0..<n where castles[i].heartKind == .aegis && !aegisUsed[i] && out.damage[i].heart > 0 && !castles[i].heartLost {
            aegisUsed[i] = true
            shield[i] = true
            out.aegis = i
        }
        if res.ammo != .standard { stock[s][res.ammo.rawValue] = max(0, stock[s][res.ammo.rawValue] - 1) }
        var dealt = 0.0
        for e in 0..<n where e != s { dealt += out.damage[e].lost + out.damage[e].heart * 0.25 }
        if res.mega { charge[s] = 0 }
        if dealt > 0 || (0..<n).contains(where: { $0 != s && out.damage[$0].hit }) {
            streak[s] += 1
            if !res.mega {
                let combo = 1 + 0.2 * Double(min(streak[s] - 1, 3))
                charge[s] = min(1, charge[s] + (dealt * 2.4 * combo + (res.crit ? 0.15 : 0) + 0.04) * rules.megaRate)
            }
            for e in 0..<n where e != s && out.damage[e].lost > 0 {          // taking damage charges the defender: a way back in
                charge[e] = min(1, charge[e] + out.damage[e].lost * 1.5 * rules.megaRate)
            }
        } else {
            streak[s] = 0
        }
        if res.collectedAt != nil, let p = pickup {
            out.pickup = p.kind
            switch p.kind {
            case .repair: out.repaired = castles[s].repair(mass: castles[s].total * K.repairShare)
            case .shield: shield[s] = true
            case .charge: charge[s] = min(1, charge[s] + 0.5)
            }
            pickup = nil
            nextSpawn = shot + 3
        }
        return out
    }

    /// The side to move let the shot clock run out.
    func forfeitTurn() { streak[turn] = 0 }

    /// The last heart standing, once there is one. If a shot takes every heart left, the side
    /// that fired it loses.
    func winner() -> Int? {
        let left = standing
        if left.count == 1 { return left[0] }
        if left.isEmpty { return castles.indices.first { $0 != turn } }
        return nil
    }
}

// MARK: - Aiming

enum Ballistics {
    static func speed(power: Double) -> Double { K.vMin + (K.vMax - K.vMin) * power / 100 }

    /// Which way a seat's cannon points at aim zero.
    static func heading(_ arena: Arena, side: Int, aim: Aim) -> Double {
        arena.heading(from: side, to: aim.target < 0 ? arena.across(side) : aim.target)
    }

    /// Unit launch direction and muzzle position for a yaw (degrees) off a heading (radians).
    static func muzzle(_ arena: Arena, side: Int, heading h: Double, yaw: Double) -> (d: Vec3, p0: Vec3) {
        let a = h + yaw * .pi / 180, pit = K.pitch * .pi / 180, cp = cos(pit)
        let d = Vec3(x: cp * cos(a), y: sin(pit), z: cp * sin(a))
        let pv = arena.pivot(side)
        return (d, Vec3(x: pv.x + d.x * K.muzzle, y: pv.y + d.y * K.muzzle, z: pv.z + d.z * K.muzzle))
    }

    static func launch(_ arena: Arena, side: Int, aim: Aim) -> (p0: Vec3, v0: Vec3, d: Vec3) {
        let m = muzzle(arena, side: side, heading: heading(arena, side: side, aim: aim), yaw: aim.yaw), v = speed(power: aim.power)
        return (m.p0, Vec3(x: m.d.x * v, y: m.d.y * v, z: m.d.z * v), m.d)
    }
}

// MARK: - Computer player

enum Difficulty: String, CaseIterable, Identifiable {
    case kolay, orta, zor
    var id: String { rawValue }
    var goldChance: Double { self == .kolay ? 0.15 : self == .orta ? 0.4 : 0.75 }
    var ammoChance: Double { self == .kolay ? 0.1 : self == .orta ? 0.22 : 0.35 }
    /// Bricks it weighs up before it picks one.
    var samples: Int { self == .kolay ? 2 : self == .orta ? 5 : 12 }
    var heartChance: Double { self == .kolay ? 0.06 : self == .orta ? 0.12 : 0.2 }
    var yawNoise: Double { self == .kolay ? 4.5 : self == .orta ? 2.0 : 0.7 }
    var speedNoise: Double { self == .kolay ? 0.07 : self == .orta ? 0.032 : 0.012 }
}

enum Computer {
    struct Choice {
        var aim: Aim
        var mega = false
        var ammo = Ammo.standard
        /// The castle it is going for.
        var target = 0
    }

    private static func gauss() -> Double { (Double.random(in: 0...1) + Double.random(in: 0...1) + Double.random(in: 0...1) - 1.5) * 1.15 }

    static func solve(arena: Arena, side: Int, heading h: Double, target t: Vec3, wind w: (x: Double, z: Double), gravity g: Double) -> (yaw: Double, v: Double)? {
        let pv = arena.pivot(side), ch = cos(h), sh = sin(h)
        func flat(_ x: Double, _ z: Double) -> (Double, Double) { let ax = x - pv.x, az = z - pv.z; return (ax * ch + az * sh, az * ch - ax * sh) }
        let (dx, dz) = flat(t.x, t.z), d = (dx * dx + dz * dz).squareRoot()
        let yawT = atan2(dz, dx), pit = K.pitch * .pi / 180
        let den = 2 * cos(pit) * cos(pit) * (d * tan(pit) - (t.y - pv.y))
        if den <= 0 { return nil }
        var v = (g * d * d / den).squareRoot(), yaw = yawT
        for _ in 0..<10 {
            let m = Ballistics.muzzle(arena, side: side, heading: h, yaw: yaw * 180 / .pi)
            var x = m.p0.x, y = m.p0.y, z = m.p0.z, vx = m.d.x * v, vy = m.d.y * v, vz = m.d.z * v
            for _ in 0..<6000 {
                vx += w.x * K.dt; vy -= g * K.dt; vz += w.z * K.dt
                x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
                if (vy < 0 && y <= t.y) || y <= 0 { break }
            }
            let (lx, lz) = flat(x, z), dl = max(1, (lx * lx + lz * lz).squareRoot())
            yaw += yawT - atan2(lz, lx)
            v *= (d / dl).squareRoot()
        }
        return (yaw * 180 / .pi, v)
    }

    /// Picks a castle to attack. With several to choose from it leans toward the weakest heart.
    static func pickTarget(battle: Battle, side: Int) -> Int {
        let foes = battle.standing.filter { $0 != side }
        guard foes.count > 1 else { return foes.first ?? battle.arena.across(side) }
        let low = foes.map { battle.castles[$0].heartPct + battle.castles[$0].pct * 0.3 }
        let best = low.min() ?? 1
        if best < 1.3, Double.random(in: 0...1) < 0.55, let i = low.firstIndex(of: best) { return foes[i] }
        return foes.randomElement()!
    }

    /// What it hopes a shot that first touches brick `i` of castle `c` will do: the brick itself,
    /// everything that rests on it, and a lot for anything that looks like the heart.
    static func worth(_ c: Castle, brick i: Int, revealed: Bool = false) -> Double {
        let b = c.bricks[i]
        var w = b.mass * 0.6 + c.unsupported(without: i)
        if b.material == .heart || (b.material == .decoy && !revealed) { w += c.total * 0.5 }
        if b.material == .ice { w += b.mass * 0.6 }          // brittle: it will likely break
        if b.material == .iron { w -= b.mass * 0.4 }
        return w
    }

    static func choose(battle: Battle, side: Int, difficulty: Difficulty, wind w: (x: Double, z: Double)) -> Choice {
        let foe = pickTarget(battle: battle, side: side)
        let enemy = battle.castles[foe]
        let mega = battle.charge[side] >= 1 && (difficulty != .kolay || Bool.random())
        var ammo = Ammo.standard
        if !mega, Double.random(in: 0...1) < difficulty.ammoChance {
            ammo = Ammo.specials.filter { battle.stock[side][$0.rawValue] > 0 }.randomElement() ?? .standard
        }
        let heading = battle.arena.heading(from: side, to: foe)
        let gold = battle.goldTarget()
        func aimAt(_ t: Vec3) -> (yaw: Double, v: Double)? { solve(arena: battle.arena, side: side, heading: heading, target: t, wind: w, gravity: battle.rules.gravity) }
        /// Where a noiseless shot at `t` would first touch, and what that is worth.
        func score(_ t: Vec3) -> (Double, (yaw: Double, v: Double))? {
            guard let sol = aimAt(t) else { return nil }
            let m = Ballistics.muzzle(battle.arena, side: side, heading: heading, yaw: sol.yaw)
            let v0 = Vec3(x: m.d.x * sol.v, y: m.d.y * sol.v, z: m.d.z * sol.v)
            let tr = battle.trace(p0: m.p0, v0: v0, wind: w, homeTo: ammo == .homing ? gold : nil)
            var s = 0.0
            if tr.kind == .castle, tr.side == foe, let b = tr.brick {
                let k = enemy.decoys.firstIndex(of: b)
                s = worth(enemy, brick: b, revealed: k.map { enemy.decoyRevealed[$0] } ?? false)
                if let g = gold {
                    let dx = tr.pos.x - g.x, dy = tr.pos.y - g.y, dz = tr.pos.z - g.z
                    if dx * dx + dy * dy + dz * dz <= K.critRange * K.critRange { s *= 1.3; s += enemy.total * 0.03 }
                }
            } else if tr.kind == .ground, enemy.distance(to: tr.pos) < 3 {
                s = 0.2
            }
            return (s, sol)
        }
        let standing = enemy.bricks.indices.filter { !enemy.bricks[$0].shape.isDecal && enemy.isHome($0) }
        var best: (Double, (yaw: Double, v: Double))?
        if !standing.isEmpty {
            // Front-facing, higher bricks first: those are the ones a ball can reach.
            let picks = (0..<difficulty.samples).map { _ in standing.randomElement()! }
            for i in picks {
                if let s = score(enemy.center(i)), s.0 > (best?.0 ?? -1) { best = s }
            }
        }
        if ammo == .homing || Double.random(in: 0...1) < difficulty.goldChance, let g = gold,
           let s = score(g), ammo == .homing || s.0 > (best?.0 ?? -1) { best = s }
        // Going straight for the heart, when it can see one. It cannot tell a decoy from the heart until one breaks.
        // Once the walls are mostly down there is little left to topple but the heart.
        let heartChance = enemy.pct < 0.35 ? max(0.5, difficulty.heartChance) : difficulty.heartChance
        if ammo != .homing, Double.random(in: 0...1) < heartChance {
            for h in enemy.heartLookalikes.shuffled() {
                if let s = score(h), s.0 > enemy.total * 0.4 { best = s; break }
            }
        }
        let sol = best?.1 ?? aimAt(battle.arena.castleCenter(foe)) ?? (yaw: 0, v: 32)
        let v = sol.v * (1 + gauss() * difficulty.speedNoise)
        let yaw = sol.yaw + gauss() * difficulty.yawNoise
        let aim = Aim(yaw: min(max(yaw, -K.maxYaw), K.maxYaw), power: min(max((v - K.vMin) / (K.vMax - K.vMin) * 100, 0), 100), target: foe)
        return Choice(aim: aim, mega: mega, ammo: ammo, target: foe)
    }
}

// MARK: - Daily siege

/// Solo score attack: the same castle, winds and gold targets for every player on a given day.
enum Challenge {
    static let shots = 8

    static func seed(day: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in ("siege-" + day).utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return h
    }

    /// Points for one shot: damage first, then precision and consistency.
    static func points(dealt: Int, crit: Bool, streak: Int) -> Int {
        guard dealt > 0 else { return 0 }
        return dealt * 10 + (crit ? 50 : 0) + (streak >= 2 ? 10 * min(streak, 5) : 0)
    }

    /// Breaking the heart early pays for every shot left unused.
    static func clearBonus(unusedShots: Int) -> Int { 150 + 75 * unusedShots }
}

// MARK: - Campaign

/// A ladder of computer opponents: each stage has its own castle, skill and twist.
struct Stage: Identifiable {
    let id: Int
    let design: BrickDesign
    let difficulty: Difficulty
    let modifier: Modifier

    static let all: [Stage] = [
        Stage(id: 1, design: Presets.stages[0], difficulty: .kolay, modifier: .calm),
        Stage(id: 2, design: Presets.stages[1], difficulty: .kolay, modifier: .none),
        Stage(id: 3, design: Presets.stages[2], difficulty: .kolay, modifier: .none),
        Stage(id: 4, design: Presets.stages[3], difficulty: .orta, modifier: .storm),
        Stage(id: 5, design: Presets.stages[4], difficulty: .orta, modifier: .none),
        Stage(id: 6, design: Presets.stages[5], difficulty: .orta, modifier: .megaRush),
        Stage(id: 7, design: Presets.stages[6], difficulty: .orta, modifier: .none),
        Stage(id: 8, design: Presets.stages[7], difficulty: .orta, modifier: .lowGravity),
        Stage(id: 9, design: Presets.stages[8], difficulty: .zor, modifier: .storm),
        Stage(id: 10, design: Presets.stages[9], difficulty: .zor, modifier: .bigBlast),
        Stage(id: 11, design: Presets.stages[10], difficulty: .zor, modifier: .none),
        Stage(id: 12, design: Presets.stages[11], difficulty: .zor, modifier: .megaRush),
    ]

    /// Stars for a win, by how much of your own castle is still standing.
    static func stars(ownPct: Double) -> Int { ownPct >= 0.6 ? 3 : ownPct >= 0.4 ? 2 : 1 }
}

// MARK: - Gauntlet

/// Castle after castle until yours falls. Damage carries over; a win patches some of it up.
enum Gauntlet {
    /// Share of the castle's mass a won round puts back.
    static let repairShare = 0.4

    struct Foe {
        let design: BrickDesign
        let difficulty: Difficulty
        let modifier: Modifier
    }

    /// The castle met in a round (1 is the first), harder as the run goes on.
    static func foe(round: Int, seed: UInt32) -> Foe {
        var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: round) &* 0x27D4_EB2F))
        _ = r.next()
        var design = Presets.all[min(Presets.all.count - 1, Int(r.next() * Double(Presets.all.count)))]
        if round >= 11 { design.heart = .aegis } else if round >= 8 { design.heart = .living }
        let difficulty: Difficulty = round <= 3 ? .kolay : round <= 7 ? .orta : .zor
        let twists = Modifier.allCases.filter { $0 != .none }
        let modifier = round >= 4 && round % 3 == 1 ? twists[min(twists.count - 1, Int(r.next() * Double(twists.count)))] : Modifier.none
        return Foe(design: design, difficulty: difficulty, modifier: modifier)
    }
}

// MARK: - Castle codes

/// A castle as a short text code that can be sent to a friend and pasted back into the game.
/// Version 2 (`KS2-`) lists every brick; version 1 (`KS-`) codes from before bricks still read,
/// rebuilt from stamps.
enum CastleCode {
    static let prefix = "KS2-"
    static let legacyPrefix = "KS-"
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static func text(_ bits: [Bool], prefix: String) -> String {
        var bits = bits
        while bits.count % 5 != 0 { bits.append(false) }
        var out = prefix
        for i in stride(from: 0, to: bits.count, by: 5) {
            var v = 0
            for b in bits[i..<i + 5] { v = v * 2 + (b ? 1 : 0) }
            out.append(alphabet[v])
        }
        return out
    }

    private static func bits(_ text: String, after prefix: String) -> [Bool]? {
        let up = text.uppercased()
        guard let start = up.range(of: prefix) else { return nil }
        var bits: [Bool] = []
        for ch in up[start.upperBound...] {
            let c: Character = ch == "O" ? "0" : ch == "I" || ch == "L" ? "1" : ch
            guard let v = alphabet.firstIndex(of: c) else { break }
            for i in stride(from: 4, through: 0, by: -1) { bits.append((v >> i) & 1 == 1) }
        }
        return bits
    }

    static func encode(_ d: BrickDesign) -> String {
        var bits: [Bool] = []
        func put(_ v: Int, _ n: Int) { for i in stride(from: n - 1, through: 0, by: -1) { bits.append((v >> i) & 1 == 1) } }
        put(2, 4)
        put(d.heart.rawValue, 4)
        put(d.bricks.count, 9)
        for b in d.bricks { put(b.shape.rawValue, 4); put(b.material.rawValue, 3); put(b.x, 5); put(b.y, 5); put(b.z, 5); put(b.rot, 2) }
        put(checksum(d), 12)
        return text(bits, prefix: prefix)
    }

    /// Finds a castle code anywhere in a piece of text. Returns nil unless it is a playable castle.
    static func decode(_ text: String) -> BrickDesign? {
        guard let bits = bits(text, after: prefix) else { return decodeTest(text) ?? decodeLegacy(text).map(BrickDesign.init(legacy:)) }
        var at = 0
        func take(_ n: Int) -> Int? {
            guard at + n <= bits.count else { return nil }
            var v = 0
            for b in bits[at..<at + n] { v = v * 2 + (b ? 1 : 0) }
            at += n
            return v
        }
        guard take(4) == 2, let h = take(4), let heart = HeartKind(rawValue: h), let n = take(9), n <= BK.maxBricks else { return nil }
        var d = BrickDesign(heart: heart)
        for _ in 0..<n {
            guard let s = take(4), let shape = BrickShape(rawValue: s), let m = take(3), let material = BrickMaterial(rawValue: m),
                  let x = take(5), let y = take(5), let z = take(5), let rot = take(2) else { return nil }
            d.bricks.append(PlacedBrick(shape: shape, material: material, x: x, y: y, z: z, rot: rot))
        }
        guard take(12) == checksum(d), d.problem == nil else { return nil }
        return d
    }

    private static func checksum(_ d: BrickDesign) -> Int {
        var h = 17 &* 31 &+ d.heart.rawValue
        for b in d.bricks {
            h = h &* 31 &+ b.shape.rawValue &* 7 &+ b.material.rawValue
            h = h &* 31 &+ ((b.x * 32 + b.y) * 32 + b.z) * 4 + b.rot
        }
        return ((h % 4096) + 4096) % 4096
    }

    /// A brick code from a 2.0 test build (24 bits a brick, 8-bit checksum).
    private static func decodeTest(_ text: String) -> BrickDesign? {
        guard let bits = bits(text, after: "KSB-") else { return nil }
        var at = 0
        func take(_ n: Int) -> Int? {
            guard at + n <= bits.count else { return nil }
            var v = 0
            for b in bits[at..<at + n] { v = v * 2 + (b ? 1 : 0) }
            at += n
            return v
        }
        guard take(4) == 2, let h = take(4), let n = take(9), n <= BK.maxBricks else { return nil }
        var flat = [2, h]
        for _ in 0..<n {
            guard let s = take(4), let m = take(3), let x = take(5), let y = take(5), let z = take(5), let r = take(2) else { return nil }
            flat += [s, m, x, y, z, r]
        }
        guard take(8) == flat.reduce(17, { ($0 * 31 + $1) & 0xff }), let d = BrickDesign(encoded: flat), d.problem == nil else { return nil }
        return d
    }

    /// A version 1 code: the tile castle it describes.
    private static func decodeLegacy(_ text: String) -> CastleDesign? {
        guard let bits = bits(text, after: legacyPrefix) else { return nil }
        var at = 0
        func take(_ n: Int) -> Int? {
            guard at + n <= bits.count else { return nil }
            var v = 0
            for b in bits[at..<at + n] { v = v * 2 + (b ? 1 : 0) }
            at += n
            return v
        }
        guard take(4) == 1, let h = take(4), let heart = HeartKind(rawValue: h), let n = take(8) else { return nil }
        var d = CastleDesign()
        d.heart = heart
        for _ in 0..<n {
            guard let k = take(4), let kind = PieceKind(rawValue: k), let tx = take(4), let tz = take(4) else { return nil }
            d.pieces.append(Piece(kind: kind, tx: tx, tz: tz))
        }
        guard take(8) == legacyChecksum(d), d.problem == nil else { return nil }
        return d
    }

    private static func legacyChecksum(_ d: CastleDesign) -> Int {
        var h = 17 &* 31 &+ d.heart.rawValue
        for p in d.pieces { h = h &* 31 &+ p.kind.rawValue &* 225 &+ p.tx &* 15 &+ p.tz }
        return ((h % 256) + 256) % 256
    }
}

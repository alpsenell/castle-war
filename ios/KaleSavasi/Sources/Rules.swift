import Foundation

// Game rules with no rendering: castle designs, ballistics, damage, power-ups and the computer
// player. Everything that decides an outcome lives here so both players of an online match
// compute identical results from the same numbers.

enum K {
    static let gw = 22, gd = 30, gh = 20          // castle grid: depth, width, layers
    static let lh = 1.2                            // layer height
    static let grav = 12.0, dt = 1.0 / 120.0
    static let ballR = 0.7, blastR = 5.1
    static let vMin = 20.0, vMax = 42.0, pitch = 32.0
    static let wind = 1.4
    static let front = 40.0                        // |x| of each castle's front face
    static let xEdge = front + Double(gw)          // |x| of the back face
    static let river = 8.0
    static let platX = 31.0, platHalf = 3.0, platTop = 2.4
    static let pivotY = platTop + 1.25, muzzle = 2.6
    static let maxYaw = 35.0
    static let critRange = 3.2, critBoost = 1.25     // gold target: how close counts, and the blast bonus
    static let megaBoost = 1.45                      // blast bonus of a charged mega shot
    static let turnSeconds = 20.0                    // shot clock for timed modes
    static let homing = 7.0                          // steering pull of a homing shot
    static let pierceDepth = 6.5                     // how far a piercer travels inside before it goes off
    static let clusterSpread = 4.6, clusterScale = 0.72
    static let pickupRange = 2.8                     // how close a shot must pass to grab a balloon
    static let shieldFactor = 0.6                    // blast radius against a shielded castle
    static let repairCells = 110
    static let heartReach = 0.5                      // the heart only breaks this much closer to a blast than stone does
    static let rulesVersion = 2                      // bumped whenever an online match would play out differently
    static let cells = gw * gh * gd
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

/// Direction in degrees (positive = right of the shooter) and power 0...100.
struct Aim: Equatable {
    var yaw = 0.0
    var power = 50.0
}

struct Block {
    let id: Int
    let x: Int, y: Int, z: Int
    let len: Int
    let dir: Int        // 1 runs along x, 2 along z
    let mat: UInt8      // 1 stone, 2 team colour, 3 trim, 4 heart
    var alive = true
    var ghost = false   // never stood: cut from the plan because nothing held it up
}

struct DecorSpec {
    let x: Double, y: Double, z: Double    // grid coordinates of the base centre
    let w: Double, d: Double, ht: Double
    let flag: Bool
    let cells: [[Int]]
}

struct Damage {
    var blast: [Int] = []
    var fall: [Int] = []
    var cells = 0
    var heart = 0
    mutating func add(_ d: Damage) { blast += d.blast; fall += d.fall; cells += d.cells; heart += d.heart }
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
        case .bigBlast: blastScale = 1.2
        }
    }
}

struct Blast: Equatable {
    var center: Vec3
    var radius: Double
}

struct ShotResult {
    var steps: Int
    var pos: Vec3
    var vel: Vec3
    var kind: HitKind
    var side: Int
    var blasts: [Blast] = []
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
    var repaired: [Int] = []
    var pickup: PickupKind?
    var shieldBroken: Int?
}

@inline(__always) func cellIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * K.gw + x) * K.gd + z }

// MARK: - Castle designs

/// Building pieces. A tile is 2×2 grid cells; `span` is the piece's footprint in tiles.
enum PieceKind: Int, CaseIterable, Identifiable {
    case wallLow = 1, wallHigh, tower, tallTower, bastion, keep, heart
    var id: Int { rawValue }
    var span: Int {
        switch self {
        case .wallLow, .wallHigh, .heart: return 1
        case .tower, .tallTower, .bastion: return 2
        case .keep: return 3
        }
    }
}

struct Piece: Equatable {
    var kind: PieceKind
    var tx: Int      // tile row, 0 = back of the castle
    var tz: Int      // tile column, 0 = the owner's left
}

/// A castle as its owner laid it out: pieces on an 11×15 tile grid, paid for in stone.
/// Every castle guards one heart; the heart is free, the keep is optional.
struct CastleDesign: Equatable {
    var pieces: [Piece] = []

    static let rows = K.gw / 2, cols = K.gd / 2
    static let budget = 2400, minimum = 1200

    private static let costs: [PieceKind: Int] = {
        var out: [PieceKind: Int] = [:]
        for k in PieceKind.allCases where k != .heart {
            var p = Plan()
            p.add(Piece(kind: k, tx: 4, tz: 4))
            out[k] = p.vox.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
        }
        return out
    }()

    static func cost(of kind: PieceKind) -> Int { costs[kind] ?? 0 }
    var cost: Int { pieces.reduce(0) { $0 + CastleDesign.cost(of: $1.kind) } }
    var keeps: Int { pieces.filter { $0.kind == .keep }.count }
    var hearts: Int { pieces.filter { $0.kind == .heart }.count }

    /// Index of the piece covering a tile, if any.
    func piece(atRow tx: Int, col tz: Int) -> Int? {
        pieces.firstIndex { tx >= $0.tx && tx < $0.tx + $0.kind.span && tz >= $0.tz && tz < $0.tz + $0.kind.span }
    }

    func fits(_ kind: PieceKind, row tx: Int, col tz: Int) -> Bool {
        let n = kind.span
        guard tx >= 0, tz >= 0, tx + n <= CastleDesign.rows, tz + n <= CastleDesign.cols else { return false }
        for p in pieces {
            let m = p.kind.span
            if tx < p.tx + m && p.tx < tx + n && tz < p.tz + m && p.tz < tz + n { return false }
        }
        return true
    }

    /// What stops this design from being played, if anything.
    enum Problem { case noHeart, manyHearts, manyKeeps, tooSmall, overBudget, overlap }
    var problem: Problem? {
        var seen = CastleDesign()
        for p in pieces {
            if !seen.fits(p.kind, row: p.tx, col: p.tz) { return .overlap }
            seen.pieces.append(p)
        }
        if hearts == 0 { return .noHeart }
        if hearts > 1 { return .manyHearts }
        if keeps > 1 { return .manyKeeps }
        if cost > CastleDesign.budget { return .overBudget }
        if cost < CastleDesign.minimum { return .tooSmall }
        return nil
    }

    /// Flat form for storage and the network: kind, row, column per piece.
    var encoded: [Int] { pieces.flatMap { [$0.kind.rawValue, $0.tx, $0.tz] } }

    /// Rebuilds a design from its flat form. Returns nil for anything that is not a playable castle.
    init?(encoded: [Int]) {
        guard encoded.count % 3 == 0, encoded.count <= 3 * CastleDesign.rows * CastleDesign.cols else { return nil }
        var out: [Piece] = []
        for i in stride(from: 0, to: encoded.count, by: 3) {
            guard let k = PieceKind(rawValue: encoded[i]) else { return nil }
            out.append(Piece(kind: k, tx: encoded[i + 1], tz: encoded[i + 2]))
        }
        pieces = out
        if problem != nil { return nil }
    }

    init(pieces: [Piece] = []) { self.pieces = pieces }

    /// Reads a castle saved before hearts existed: the heart goes on the free tile nearest the back centre.
    static func migrating(encoded: [Int]) -> CastleDesign? {
        if let d = CastleDesign(encoded: encoded) { return d }
        guard encoded.count % 3 == 0 else { return nil }
        var d = CastleDesign()
        for i in stride(from: 0, to: encoded.count, by: 3) {
            guard let k = PieceKind(rawValue: encoded[i]) else { return nil }
            d.pieces.append(Piece(kind: k, tx: encoded[i + 1], tz: encoded[i + 2]))
        }
        guard d.hearts == 0 else { return nil }
        var spots: [(Int, Int)] = []
        for r in 0..<rows { for c in 0..<cols where d.fits(.heart, row: r, col: c) { spots.append((r, c)) } }
        let mid = cols / 2
        guard let best = spots.min(by: { abs($0.0 - 2) * 2 + abs($0.1 - mid) < abs($1.0 - 2) * 2 + abs($1.1 - mid) }) else { return nil }
        d.pieces.append(Piece(kind: .heart, tx: best.0, tz: best.1))
        return d.problem == nil ? d : nil
    }

    /// Reads a drawing: one string per tile row, back of the castle first.
    /// w/W low/high wall, T tower, A tall tower, B bastion, K keep (top-left tile of the piece), H heart, anything else empty.
    init(map: [String]) {
        var out: [Piece] = []
        for (r, line) in map.enumerated() {
            for (c, ch) in line.enumerated() {
                let kind: PieceKind?
                switch ch {
                case "w": kind = .wallLow
                case "W": kind = .wallHigh
                case "T": kind = .tower
                case "A": kind = .tallTower
                case "B": kind = .bastion
                case "K": kind = .keep
                case "H": kind = .heart
                default: kind = nil
                }
                if let kind { out.append(Piece(kind: kind, tx: r, tz: c)) }
            }
        }
        pieces = out
    }

    static let classic = CastleDesign(map: [
        "A+WWWWWWWWWWWA+",
        "++...........++",
        "w.............w",
        "w......H......w",
        "w.....K++.....w",
        "w.....+++.....w",
        "w.....+++.....w",
        "w.............w",
        "w.............w",
        "T+...........T+",
        "++wwwww.wwwww++",
    ])
}

/// Ready-made castles for the computer, the campaign and the daily siege.
enum Presets {
    static let outpost = CastleDesign(map: [
        "...............",
        "...............",
        "...T+wwwwwT+...",
        "...++..H..++...",
        "...w..K++..w...",
        "...w..+++..w...",
        "...w..+++..w...",
        "...w.......w...",
        "...T+ww.wwT+...",
        "...++.....++...",
        "...............",
    ])
    static let longWall = CastleDesign(map: [
        "T+wwwwwwwwwwwT+",
        "++...........++",
        "...............",
        "..wwwwwwwwwww..",
        ".......H.......",
        "......K++......",
        "......+++......",
        "......+++......",
        "..wwwwwwwwwww..",
        "T+...........T+",
        "++wwwww.wwwww++",
    ])
    static let spires = CastleDesign(map: [
        "A+..A+...A+..A+",
        "++ww++www++ww++",
        ".......H.......",
        "w.....K++.....w",
        "w.....+++.....w",
        "w.....+++.....w",
        "w.............w",
        "...............",
        "A+..T+...T+..A+",
        "++ww++w.w++ww++",
        "...............",
    ])
    static let citadel = CastleDesign(map: [
        "...............",
        "..B+WWWWWWWB+..",
        "..++.......++..",
        "..W.A+.H.A+.W..",
        "..W.++K++++.W..",
        "..W...+++...W..",
        "..W...+++...W..",
        "..W.........W..",
        "..B+WWW.WWWB+..",
        "..++.......++..",
        "...............",
    ])
    static let bulwark = CastleDesign(map: [
        "T+wwwwwwwwwwwT+",
        "++...........++",
        "w......H......w",
        "w.....K++.....w",
        "w.....+++.....w",
        "w.....+++.....w",
        "w.............w",
        "W.............W",
        "W..B+.....B+..W",
        "A+.++.....++.A+",
        "++WWWWW.WWWWW++",
    ])
    static let twinWalls = CastleDesign(map: [
        "T+wwwwwwwwwwwT+",
        "++...........++",
        "W.............W",
        "W...wwwwwww...W",
        "W...wHK++.w...W",
        "W...w.+++.w...W",
        "W...w.+++.w...W",
        "W...www.www...W",
        "W.............W",
        "T+...........T+",
        "++WWWWW.WWWWW++",
    ])
    static let stronghold = CastleDesign(map: [
        "A+WWWWWWWWWWWA+",
        "++...........++",
        "w..B+.....B+..w",
        "w..++..H..++..w",
        "w.....K++.....w",
        "w.....+++.....w",
        "w.....+++.....w",
        "w.............w",
        "w.............w",
        "A+...........A+",
        "++WWWWW.WWWWW++",
    ])

    static let all: [CastleDesign] = [.classic, outpost, longWall, spires, citadel, bulwark, twinWalls, stronghold]

    /// A castle for a quick match against the computer, chosen by the match seed.
    static func pick(_ seed: UInt32) -> CastleDesign { all[Int(seed % UInt32(all.count))] }
}

// MARK: - From design to blocks

private struct Plan {
    var vox = [UInt8](repeating: 0, count: K.cells)
    var hint = [UInt8](repeating: 0, count: K.cells)
    var decor: [DecorSpec] = []

    init() {}

    init(_ design: CastleDesign) {
        for p in design.pieces { add(p) }
    }

    mutating func set(_ x: Int, _ y: Int, _ z: Int, _ m: UInt8, _ h: UInt8 = 0) {
        guard x >= 0, x < K.gw, y >= 0, y < K.gh, z >= 0, z < K.gd else { return }
        let i = cellIndex(x, y, z)
        vox[i] = m
        hint[i] = m == 0 ? 0 : h
    }
    mutating func box(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ m: UInt8, _ h: UInt8 = 0) {
        for y in y0...y1 { for x in x0...x1 { for z in z0...z1 { set(x, y, z, m, h) } } }
    }
    mutating func ring(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ m: UInt8) {
        for y in y0...y1 { for x in x0...x1 { for z in z0...z1 where x == x0 || x == x1 || z == z0 || z == z1 { set(x, y, z, m) } } }
    }
    mutating func crenel(_ x0: Int, _ x1: Int, _ y: Int, _ z0: Int, _ z1: Int, _ m: UInt8) {
        for x in x0...x1 { for z in z0...z1 where (x == x0 || x == x1 || z == z0 || z == z1) && (x + z) % 2 == 0 { set(x, y, z, m) } }
    }

    mutating func add(_ p: Piece) {
        let x0 = p.tx * 2, z0 = p.tz * 2
        switch p.kind {
        case .wallLow: wall(x0, z0, 5)
        case .wallHigh: wall(x0, z0, 8)
        case .tower: tower(x0, z0, 10)
        case .tallTower: tower(x0, z0, 14)
        case .bastion: bastion(x0, z0)
        case .keep: keep(x0, z0)
        case .heart: heart(x0, z0)
        }
    }

    /// The heart: three courses of glowing crystal, harder to break than stone. Lose it and the castle falls.
    private mutating func heart(_ x0: Int, _ z0: Int) {
        box(x0, x0 + 1, 0, 2, z0, z0 + 1, 4)
    }

    /// Solid wall, two cells thick, with a team-colour top course and battlements.
    private mutating func wall(_ x0: Int, _ z0: Int, _ h: Int) {
        box(x0, x0 + 1, 0, h - 2, z0, z0 + 1, 1)
        box(x0, x0 + 1, h - 1, h - 1, z0, z0 + 1, 2)
        for x in x0...x0 + 1 { for z in z0...z0 + 1 where (x + z) % 2 == 0 { set(x, h, z, 1) } }
    }

    /// Hollow 4×4 tower with two floors, arrow slits and a roof.
    private mutating func tower(_ x0: Int, _ z0: Int, _ h: Int) {
        ring(x0, x0 + 3, 0, h - 1, z0, z0 + 3, 1)
        let mid = (h / 2) & ~1
        box(x0, x0 + 3, mid, mid, z0, z0 + 3, 3)
        for y in [h - 3, h - 2] {
            set(x0 + 1, y, z0, 0); set(x0 + 2, y, z0 + 3, 0); set(x0, y, z0 + 2, 0); set(x0 + 3, y, z0 + 1, 0)
        }
        box(x0, x0 + 3, h, h, z0, z0 + 3, 3)
        crenel(x0, x0 + 3, h + 1, z0, z0 + 3, 1)
        box(x0 + 1, x0 + 2, h + 1, h + 1, z0 + 1, z0 + 2, 2)
        decor.append(DecorSpec(x: Double(x0) + 2, y: Double(h + 2), z: Double(z0) + 2, w: 1.6, d: 1.6, ht: 3.4, flag: false,
                               cells: [[x0 + 1, h + 1, z0 + 1], [x0 + 2, h + 1, z0 + 2], [x0 + 1, h + 1, z0 + 2], [x0 + 2, h + 1, z0 + 1]]))
    }

    /// Low, solid 4×4 block: little to knock off, nothing to collapse.
    private mutating func bastion(_ x0: Int, _ z0: Int) {
        box(x0, x0 + 3, 0, 4, z0, z0 + 3, 1)
        box(x0, x0 + 3, 5, 5, z0, z0 + 3, 2)
        crenel(x0, x0 + 3, 6, z0, z0 + 3, 1)
    }

    /// Hollow 6×6 keep with three floors, a turret and the flag.
    private mutating func keep(_ x0: Int, _ z0: Int) {
        ring(x0, x0 + 5, 0, 9, z0, z0 + 5, 1)
        for l in [4, 8, 10] { box(x0, x0 + 5, l, l, z0, z0 + 5, 3, 1) }
        crenel(x0, x0 + 5, 11, z0, z0 + 5, 1)
        ring(x0 + 1, x0 + 4, 11, 12, z0 + 1, z0 + 4, 2)
        box(x0 + 1, x0 + 4, 13, 13, z0 + 1, z0 + 4, 3, 1)
        box(x0 + 5, x0 + 5, 0, 2, z0 + 2, z0 + 3, 0)                     // door, facing the enemy
        for c in [[x0 + 5, 6, z0 + 1], [x0 + 5, 6, z0 + 4], [x0, 6, z0 + 2], [x0 + 2, 6, z0], [x0 + 3, 6, z0 + 5]] { set(c[0], c[1], c[2], 0) }
        decor.append(DecorSpec(x: Double(x0) + 3, y: 14, z: Double(z0) + 3, w: 2.35, d: 2.35, ht: 4.2, flag: true,
                               cells: [[x0 + 1, 13, z0 + 1], [x0 + 4, 13, z0 + 4], [x0 + 1, 13, z0 + 4], [x0 + 4, 13, z0 + 1]]))
    }
}

/// Cuts the voxel plan into 1×N blocks (N ≤ 4) laid in running bond.
private func tile(_ plan: Plan) -> (blocks: [Block], cellBlock: [Int]) {
    let vox = plan.vox, hint = plan.hint
    var blocks: [Block] = []
    var cellBlock = [Int](repeating: -1, count: K.cells)

    func run(_ x: Int, _ y: Int, _ z: Int, _ dx: Int, _ dz: Int) -> Int {
        let m = vox[cellIndex(x, y, z)]
        var n = 1
        for s in [-1, 1] {
            var i = 1
            while true {
                let xx = x + dx * i * s, zz = z + dz * i * s
                if xx < 0 || xx >= K.gw || zz < 0 || zz >= K.gd || vox[cellIndex(xx, y, zz)] != m { break }
                n += 1; i += 1
            }
        }
        return n
    }
    func dirOf(_ x: Int, _ y: Int, _ z: Int) -> Int {
        let h = Int(hint[cellIndex(x, y, z)])
        if h != 0 { return h }
        let rx = run(x, y, z, 1, 0), rz = run(x, y, z, 0, 1)
        if rx == 1 && rz == 1 { return 0 }
        if rx > rz { return 1 }
        if rz > rx { return 2 }
        return y % 2 == 1 ? 2 : 1
    }
    for y in 0..<K.gh { for x in 0..<K.gw { for z in 0..<K.gd {
        let i = cellIndex(x, y, z), m = vox[i]
        if m == 0 || cellBlock[i] >= 0 { continue }
        let d = dirOf(x, y, z), id = blocks.count, off = (y % 2) * 2
        var len = 1, cx = x, cz = z
        cellBlock[i] = id
        if d != 0 {
            while len < 4 {
                let nx = cx + (d == 1 ? 1 : 0), nz = cz + (d == 2 ? 1 : 0)
                if nx >= K.gw || nz >= K.gd { break }
                if ((d == 1 ? nx : nz) + off) % 4 == 0 { break }
                let j = cellIndex(nx, y, nz)
                if vox[j] != m || cellBlock[j] >= 0 || dirOf(nx, y, nz) != d { break }
                cellBlock[j] = id; len += 1; cx = nx; cz = nz
            }
        }
        blocks.append(Block(id: id, x: x, y: y, z: z, len: len, dir: d == 2 ? 2 : 1, mat: m))
    } } }
    return (blocks, cellBlock)
}

// MARK: - Castle state

final class Castle {
    let side: Int
    /// +1 for the left castle, -1 for the right one, which is the same design turned to face the other way.
    let s: Double
    let x0: Double
    private(set) var blocks: [Block]
    let cellBlock: [Int]
    let decor: [DecorSpec]
    let total: Int
    private(set) var aliveCells: Int
    /// Heart cells at the start and now. The castle falls when the last one is gone.
    let heartTotal: Int
    private(set) var heartAlive: Int

    init(side: Int, design: CastleDesign) {
        self.side = side
        s = side == 0 ? 1 : -1
        x0 = side == 0 ? -K.xEdge : K.xEdge
        let plan = Plan(design)
        let t = tile(plan)
        blocks = t.blocks
        cellBlock = t.cellBlock
        decor = plan.decor
        var sup = [Bool](repeating: false, count: t.blocks.count)
        var sum = 0, hearts = 0
        for i in blocks.indices {
            if Castle.supported(blocks[i], sup, cellBlock) {
                sup[i] = true
                sum += blocks[i].len
                if blocks[i].mat == 4 { hearts += blocks[i].len }
            } else { blocks[i].alive = false; blocks[i].ghost = true }
        }
        total = max(1, sum)
        aliveCells = sum
        heartTotal = hearts
        heartAlive = hearts
    }

    private static func supported(_ b: Block, _ sup: [Bool], _ cellBlock: [Int]) -> Bool {
        if b.y == 0 { return true }
        for i in 0..<b.len {
            let id = cellBlock[cellIndex(b.x + (b.dir == 1 ? i : 0), b.y - 1, b.z + (b.dir == 2 ? i : 0))]
            if id >= 0 && sup[id] { return true }
        }
        return false
    }

    var pct: Double { Double(aliveCells) / Double(total) }
    var heartPct: Double { heartTotal == 0 ? 0 : Double(heartAlive) / Double(heartTotal) }
    var heartLost: Bool { heartAlive <= 0 }

    /// Middle of what is left of the heart, if anything is.
    var heartCenter: Vec3? {
        let live = blocks.filter { $0.alive && $0.mat == 4 }
        guard !live.isEmpty else { return nil }
        var c = Vec3()
        for b in live { let p = center(of: b); c.x += p.x; c.y += p.y; c.z += p.z }
        let n = Double(live.count)
        return Vec3(x: c.x / n, y: c.y / n, z: c.z / n)
    }

    func center(of b: Block) -> Vec3 {
        let lx = Double(b.x) + (b.dir == 1 ? Double(b.len) / 2 : 0.5)
        let lz = Double(b.z) + (b.dir == 2 ? Double(b.len) / 2 : 0.5)
        return worldPoint(gx: lx, gy: Double(b.y) + 0.5, gz: lz)
    }

    func worldPoint(gx: Double, gy: Double, gz: Double) -> Vec3 {
        Vec3(x: x0 + s * gx, y: gy * K.lh, z: s * (gz - Double(K.gd) / 2))
    }

    func hit(_ px: Double, _ py: Double, _ pz: Double) -> Bool {
        let r = K.ballR, lx = s * (px - x0), lz = s * pz + Double(K.gd) / 2
        if lx < -r || lx > Double(K.gw) + r || lz < -r || lz > Double(K.gd) + r || py > Double(K.gh) * K.lh + r { return false }
        let xa = max(0, Int((lx - r).rounded(.down))), xb = min(K.gw - 1, Int((lx + r).rounded(.down)))
        let ya = max(0, Int(((py - r) / K.lh).rounded(.down))), yb = min(K.gh - 1, Int(((py + r) / K.lh).rounded(.down)))
        let za = max(0, Int((lz - r).rounded(.down))), zb = min(K.gd - 1, Int((lz + r).rounded(.down)))
        if xa > xb || ya > yb || za > zb { return false }
        for gy in ya...yb { for gx in xa...xb { for gz in za...zb {
            let id = cellBlock[cellIndex(gx, gy, gz)]
            if id < 0 || !blocks[id].alive { continue }
            let cx = min(max(lx, Double(gx)), Double(gx + 1)) - lx
            let cy = min(max(py, Double(gy) * K.lh), Double(gy + 1) * K.lh) - py
            let cz = min(max(lz, Double(gz)), Double(gz + 1)) - lz
            if cx * cx + cy * cy + cz * cz <= r * r { return true }
        } } }
        return false
    }

    /// Blocks removed by a blast at a world point plus everything left with nothing underneath. Does not change state.
    func damage(at c: Vec3, radius R: Double = K.blastR) -> Damage {
        var out = Damage()
        let lx = s * (c.x - x0), lz = s * c.z + Double(K.gd) / 2
        if lx < -R || lx > Double(K.gw) + R || lz < -R || lz > Double(K.gd) + R { return out }
        var dead = [Bool](repeating: false, count: blocks.count)
        let r2 = R * R, h2 = r2 * K.heartReach * K.heartReach
        for b in blocks where b.alive {
            for i in 0..<b.len {
                let dx = Double(b.x + (b.dir == 1 ? i : 0)) + 0.5 - lx
                let dy = (Double(b.y) + 0.5) * K.lh - c.y
                let dz = Double(b.z + (b.dir == 2 ? i : 0)) + 0.5 - lz
                if dx * dx + dy * dy + dz * dz <= (b.mat == 4 ? h2 : r2) {
                    dead[b.id] = true; out.blast.append(b.id); out.cells += b.len
                    if b.mat == 4 { out.heart += b.len }
                    break
                }
            }
        }
        if out.blast.isEmpty { return out }
        var sup = [Bool](repeating: false, count: blocks.count)
        for b in blocks where b.alive && !dead[b.id] {
            if Castle.supported(b, sup, cellBlock) { sup[b.id] = true } else {
                out.fall.append(b.id); out.cells += b.len
                if b.mat == 4 { out.heart += b.len }
            }
        }
        return out
    }

    /// True when nothing stands above at least one cell of the block, so a falling shot can reach it.
    func isOpenToSky(_ b: Block) -> Bool {
        for i in 0..<b.len {
            let x = b.x + (b.dir == 1 ? i : 0), z = b.z + (b.dir == 2 ? i : 0)
            var covered = false
            var y = b.y + 1
            while y < K.gh {
                let id = cellBlock[cellIndex(x, y, z)]
                if id >= 0 && blocks[id].alive { covered = true; break }
                y += 1
            }
            if !covered { return true }
        }
        return false
    }

    func kill(_ d: Damage) {
        for id in d.blast { blocks[id].alive = false }
        for id in d.fall { blocks[id].alive = false }
        aliveCells -= d.cells
        heartAlive -= d.heart
    }

    /// Puts fallen blocks back, lowest first, as long as each has something to stand on. Returns what was rebuilt.
    func repair(cells budget: Int) -> [Int] {
        var left = budget, out: [Int] = []
        for i in blocks.indices where !blocks[i].alive && !blocks[i].ghost {
            let b = blocks[i]
            if b.len > left { continue }
            var held = b.y == 0
            if !held {
                for k in 0..<b.len {
                    let id = cellBlock[cellIndex(b.x + (b.dir == 1 ? k : 0), b.y - 1, b.z + (b.dir == 2 ? k : 0))]
                    if id >= 0 && blocks[id].alive { held = true; break }
                }
            }
            if held {
                blocks[i].alive = true; left -= b.len; aliveCells += b.len; out.append(i)
                if b.mat == 4 { heartAlive += b.len }
            }
            if left <= 0 { break }
        }
        return out
    }
}

// MARK: - Battle

final class Battle {
    let seed: UInt32
    let first: Int
    let rules: MatchRules
    private(set) var shot = 0
    let castles: [Castle]
    /// Mega meter per side, 0...1. Fills by dealing damage and, more slowly, by taking it.
    private(set) var charge = [0.0, 0.0]
    /// Consecutive shots that damaged the enemy, per side.
    private(set) var streak = [0, 0]
    /// Special shots left, per side, indexed by `Ammo.rawValue`.
    private(set) var stock = [[0, 1, 1, 1], [0, 1, 1, 1]]
    /// A shielded castle takes the next blast at reduced radius.
    private(set) var shield = [false, false]
    private(set) var pickup: Pickup?
    private var nextSpawn = 2

    init(seed: UInt32, first: Int, designs: [CastleDesign] = [.classic, .classic], rules: MatchRules = MatchRules()) {
        self.seed = seed
        self.first = first
        self.rules = rules
        castles = [Castle(side: 0, design: designs[0]), Castle(side: 1, design: designs[1])]
    }

    var turn: Int { (first + shot) % 2 }

    func wind() -> (x: Double, z: Double) {
        var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: shot + 1) &* 0x9E37_79B1))
        _ = r.next()
        let wx = (r.next() * 2 - 1) * K.wind * rules.windScale
        let wz = (r.next() * 2 - 1) * K.wind * rules.windScale
        return (wx, wz)
    }

    /// This turn's gold target: a block on the defender's castle that is open to the sky.
    /// Landing a shot within `K.critRange` of it is a critical hit.
    func goldTarget() -> Vec3? {
        let enemy = castles[1 - turn]
        let open = enemy.blocks.filter { $0.alive && $0.y >= 2 && enemy.isOpenToSky($0) }
        guard !open.isEmpty else { return nil }
        var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: shot + 1) &* 0x85EB_CA6B))
        _ = r.next()
        return enemy.center(of: open[min(open.count - 1, Int(r.next() * Double(open.count)))])
    }

    /// Moves to the next turn (or skips the other side's, in the solo siege) and looks after the balloon.
    func advance(by n: Int = 1) {
        shot += n
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

    /// Fixed-step flight. Uses only additions, multiplications, divisions and square roots, so two
    /// devices fed the same launch position and velocity agree on the result. Returns the outcome
    /// and the path the ball took.
    func fly(p0: Vec3, v0: Vec3, wind w: (x: Double, z: Double), ammo wanted: Ammo = .standard, mega wantsMega: Bool = false) -> (res: ShotResult, path: [Vec3]) {
        let shooter = turn
        let ammo = wanted != .standard && stock[shooter][wanted.rawValue] > 0 ? wanted : Ammo.standard
        let mega = wantsMega && ammo == .standard && charge[shooter] >= 1
        let target = goldTarget()
        var x = p0.x, y = p0.y, z = p0.z, vx = v0.x, vy = v0.y, vz = v0.z
        var kind = HitKind.out, side = -1, n = 1
        var collectedAt: Int?
        var path = [p0]
        path.reserveCapacity(600)
        let r = K.ballR, g = rules.gravity
        while n <= 8000 {
            var ax = w.x, az = w.z
            if ammo == .homing, vy < 0, let t = target {
                let dx = t.x - x, dz = t.z - z, d = (dx * dx + dz * dz).squareRoot()
                if d > 0.5 { ax += K.homing * dx / d; az += K.homing * dz / d }
            }
            vx += ax * K.dt; vy -= g * K.dt; vz += az * K.dt
            x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
            path.append(Vec3(x: x, y: y, z: z))
            if collectedAt == nil, let p = pickup {
                let dx = x - p.pos.x, dy = y - p.pos.y, dz = z - p.pos.z
                if dx * dx + dy * dy + dz * dz <= K.pickupRange * K.pickupRange { collectedAt = n }
            }
            if y <= r { y = r; path[path.count - 1].y = r; kind = (x > -K.river && x < K.river) ? .water : .ground; break }
            if castles[0].hit(x, y, z) { kind = .castle; side = 0; break }
            if castles[1].hit(x, y, z) { kind = .castle; side = 1; break }
            if n > 40 && y < K.platTop + r && z > -K.platHalf - r && z < K.platHalf + r {
                let ax = abs(x)
                if ax > K.platX - K.platHalf - r && ax < K.platX + K.platHalf + r { kind = .ground; break }
            }
            if x > 220 || x < -220 || z > 160 || z < -160 { kind = .out; break }
            n += 1
        }
        if n > 8000 { n = 8000 }
        let contact = Vec3(x: x, y: y, z: z)
        let sp = max(0.001, (vx * vx + vy * vy + vz * vz).squareRoot())
        let dir = Vec3(x: vx / sp, y: vy / sp, z: vz / sp)
        var center = contact
        if kind == .castle {
            if ammo == .piercer {
                // Drill on through the stone, then go off deep inside.
                var gone = 0.0
                while gone < K.pierceDepth && y > r {
                    vy -= g * K.dt
                    x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
                    gone += sp * K.dt
                    n += 1
                    path.append(Vec3(x: x, y: max(y, r), z: z))
                }
                center = Vec3(x: x, y: max(y, r), z: z)
            } else {
                center = Vec3(x: x + dir.x * 1.2, y: y + dir.y * 1.2, z: z + dir.z * 1.2)
            }
        }
        var res = ShotResult(steps: n, pos: center, vel: Vec3(x: vx, y: vy, z: vz), kind: kind, side: side)
        res.pos = kind == .castle && ammo == .piercer ? center : contact
        res.shooter = shooter
        res.ammo = ammo
        res.mega = mega
        res.collectedAt = collectedAt
        if kind == .castle, side == 1 - shooter, let t = target {
            let dx = contact.x - t.x, dy = contact.y - t.y, dz = contact.z - t.z
            res.crit = dx * dx + dy * dy + dz * dz <= K.critRange * K.critRange
        }
        if kind == .castle || kind == .ground {
            var radius = K.blastR * rules.blastScale
            if mega { radius *= K.megaBoost }
            if res.crit { radius *= K.critBoost }
            switch ammo {
            case .standard:
                res.blasts = [Blast(center: center, radius: radius)]
            case .piercer:
                res.blasts = [Blast(center: center, radius: radius * 0.95)]
            case .homing:
                res.blasts = [Blast(center: center, radius: radius * 0.9)]
            case .cluster:
                // Three smaller blasts in a row across the line of fire.
                let hl = max(0.001, (dir.x * dir.x + dir.z * dir.z).squareRoot())
                let lx = -dir.z / hl * K.clusterSpread, lz = dir.x / hl * K.clusterSpread
                res.blasts = [-1.0, 0.0, 1.0].map { k in
                    Blast(center: Vec3(x: center.x + lx * k, y: center.y, z: center.z + lz * k), radius: radius * K.clusterScale)
                }
            }
        }
        return (res, path)
    }

    /// Applies a shot: damage, shields, the mega meter, streaks, ammo and any balloon it grabbed.
    func apply(_ res: ShotResult) -> ShotOutcome {
        let s = res.shooter, e = 1 - s
        var out = ShotOutcome(damage: [Damage(), Damage()])
        var struck = [false, false]
        for b in res.blasts {
            for (i, c) in castles.enumerated() {
                let d = c.damage(at: b.center, radius: b.radius * (shield[i] ? K.shieldFactor : 1))
                if d.cells > 0 { struck[i] = true }
                c.kill(d)
                out.damage[i].add(d)
            }
        }
        for i in 0..<2 where shield[i] && (struck[i] || (res.kind == .castle && res.side == i)) {
            shield[i] = false
            out.shieldBroken = i
        }
        if res.ammo != .standard { stock[s][res.ammo.rawValue] = max(0, stock[s][res.ammo.rawValue] - 1) }
        let dealt = Double(out.damage[e].cells) / Double(castles[e].total)
        if res.mega { charge[s] = 0 }
        if dealt > 0 {
            streak[s] += 1
            if !res.mega {
                let combo = 1 + 0.2 * Double(min(streak[s] - 1, 3))
                charge[s] = min(1, charge[s] + (dealt * 2.4 * combo + (res.crit ? 0.15 : 0)) * rules.megaRate)
            }
            charge[e] = min(1, charge[e] + dealt * 1.5 * rules.megaRate)      // taking damage charges the defender: a way back in
        } else {
            streak[s] = 0
        }
        if res.collectedAt != nil, let p = pickup {
            out.pickup = p.kind
            switch p.kind {
            case .repair: out.repaired = castles[s].repair(cells: K.repairCells)
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

    /// The side whose heart is gone. If one shot takes both hearts, the side that fired it loses.
    func loser() -> Int? {
        let lost = castles.filter { $0.heartLost }.map { $0.side }
        if lost.count == 2 { return turn }
        return lost.first
    }
}

// MARK: - Aiming

enum Ballistics {
    static func pivot(_ side: Int) -> Vec3 { Vec3(x: side == 0 ? -K.platX : K.platX, y: K.pivotY, z: 0) }

    static func speed(power: Double) -> Double { K.vMin + (K.vMax - K.vMin) * power / 100 }

    /// Unit launch direction and muzzle position for an aim.
    static func muzzle(side: Int, yaw: Double) -> (d: Vec3, p0: Vec3) {
        let ya = yaw * .pi / 180, pit = K.pitch * .pi / 180, sg: Double = side == 0 ? 1 : -1, cp = cos(pit)
        let d = Vec3(x: sg * cp * cos(ya), y: sin(pit), z: sg * cp * sin(ya))
        let pv = pivot(side)
        return (d, Vec3(x: pv.x + d.x * K.muzzle, y: pv.y + d.y * K.muzzle, z: pv.z + d.z * K.muzzle))
    }

    static func launch(side: Int, aim: Aim) -> (p0: Vec3, v0: Vec3, d: Vec3) {
        let m = muzzle(side: side, yaw: aim.yaw), v = speed(power: aim.power)
        return (m.p0, Vec3(x: m.d.x * v, y: m.d.y * v, z: m.d.z * v), m.d)
    }
}

// MARK: - Computer player

enum Difficulty: String, CaseIterable, Identifiable {
    case kolay, orta, zor
    var id: String { rawValue }
    var goldChance: Double { self == .kolay ? 0.15 : self == .orta ? 0.4 : 0.75 }
    var ammoChance: Double { self == .kolay ? 0.1 : self == .orta ? 0.22 : 0.35 }
    var samples: Int { self == .kolay ? 1 : self == .orta ? 3 : 12 }
    var heartChance: Double { self == .kolay ? 0.1 : self == .orta ? 0.2 : 0.25 }
    var yawNoise: Double { self == .kolay ? 5.0 : self == .orta ? 2.2 : 0.7 }
    var speedNoise: Double { self == .kolay ? 0.075 : self == .orta ? 0.035 : 0.012 }
}

enum Computer {
    struct Choice {
        var aim: Aim
        var mega = false
        var ammo = Ammo.standard
    }

    private static func gauss() -> Double { (Double.random(in: 0...1) + Double.random(in: 0...1) + Double.random(in: 0...1) - 1.5) * 1.15 }

    private static func solve(side: Int, target t: Vec3, wind w: (x: Double, z: Double), gravity g: Double) -> (yaw: Double, v: Double)? {
        let pv = Ballistics.pivot(side), sg: Double = side == 0 ? 1 : -1
        let dx = (t.x - pv.x) * sg, dz = (t.z - pv.z) * sg, d = (dx * dx + dz * dz).squareRoot()
        let yawT = atan2(dz, dx), pit = K.pitch * .pi / 180
        let den = 2 * cos(pit) * cos(pit) * (d * tan(pit) - (t.y - pv.y))
        if den <= 0 { return nil }
        var v = (g * d * d / den).squareRoot(), yaw = yawT
        for _ in 0..<10 {
            let m = Ballistics.muzzle(side: side, yaw: yaw * 180 / .pi)
            var x = m.p0.x, y = m.p0.y, z = m.p0.z, vx = m.d.x * v, vy = m.d.y * v, vz = m.d.z * v
            for _ in 0..<6000 {
                vx += w.x * K.dt; vy -= g * K.dt; vz += w.z * K.dt
                x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
                if (vy < 0 && y <= t.y) || y <= 0 { break }
            }
            let lx = (x - pv.x) * sg, lz = (z - pv.z) * sg, dl = max(1, (lx * lx + lz * lz).squareRoot())
            yaw += yawT - atan2(lz, lx)
            v *= (d / dl).squareRoot()
        }
        return (yaw * 180 / .pi, v)
    }

    static func choose(battle: Battle, side: Int, difficulty: Difficulty, wind w: (x: Double, z: Double)) -> Choice {
        let enemy = battle.castles[1 - side]
        let alive = enemy.blocks.filter { $0.alive }
        guard !alive.isEmpty else { return Choice(aim: Aim()) }
        let mega = battle.charge[side] >= 1 && (difficulty != .kolay || Bool.random())
        var ammo = Ammo.standard
        if !mega, Double.random(in: 0...1) < difficulty.ammoChance {
            ammo = Ammo.specials.filter { battle.stock[side][$0.rawValue] > 0 }.randomElement() ?? .standard
        }
        let radius = K.blastR * battle.rules.blastScale * (mega ? K.megaBoost : 1)
        func worth(_ d: Damage) -> Int { d.cells + d.heart * 15 }
        var best = enemy.center(of: alive[0]), bestScore = -1
        for _ in 0..<difficulty.samples {
            let c = enemy.center(of: alive.randomElement()!)
            let score = worth(enemy.damage(at: c, radius: radius))
            if score > bestScore { bestScore = score; best = c }
        }
        // Sometimes go for the gold target instead; better players do it more often. A homing shot always does.
        if ammo == .homing || Double.random(in: 0...1) < difficulty.goldChance, let t = battle.goldTarget() {
            let score = worth(enemy.damage(at: t, radius: radius * K.critBoost))
            if ammo == .homing || score > bestScore { bestScore = score; best = t }
        }
        // Going straight for the heart: the walls in front of it are what stops this.
        if ammo != .homing, Double.random(in: 0...1) < difficulty.heartChance, let h = enemy.heartCenter { best = h }
        let sol = solve(side: side, target: best, wind: w, gravity: battle.rules.gravity) ?? (yaw: 0, v: 32)
        let v = sol.v * (1 + gauss() * difficulty.speedNoise)
        let yaw = sol.yaw + gauss() * difficulty.yawNoise
        let aim = Aim(yaw: min(max(yaw, -K.maxYaw), K.maxYaw), power: min(max((v - K.vMin) / (K.vMax - K.vMin) * 100, 0), 100))
        return Choice(aim: aim, mega: mega, ammo: ammo)
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
    let design: CastleDesign
    let difficulty: Difficulty
    let modifier: Modifier

    static let all: [Stage] = [
        Stage(id: 1, design: Presets.outpost, difficulty: .kolay, modifier: .calm),
        Stage(id: 2, design: Presets.longWall, difficulty: .kolay, modifier: .none),
        Stage(id: 3, design: .classic, difficulty: .kolay, modifier: .none),
        Stage(id: 4, design: Presets.outpost, difficulty: .orta, modifier: .storm),
        Stage(id: 5, design: Presets.spires, difficulty: .orta, modifier: .none),
        Stage(id: 6, design: Presets.citadel, difficulty: .orta, modifier: .megaRush),
        Stage(id: 7, design: Presets.bulwark, difficulty: .orta, modifier: .none),
        Stage(id: 8, design: Presets.twinWalls, difficulty: .orta, modifier: .lowGravity),
        Stage(id: 9, design: Presets.spires, difficulty: .zor, modifier: .storm),
        Stage(id: 10, design: Presets.citadel, difficulty: .zor, modifier: .bigBlast),
        Stage(id: 11, design: Presets.twinWalls, difficulty: .zor, modifier: .none),
        Stage(id: 12, design: Presets.stronghold, difficulty: .zor, modifier: .megaRush),
    ]

    /// Stars for a win, by how much of your own castle is still standing.
    static func stars(ownPct: Double) -> Int { ownPct >= 0.6 ? 3 : ownPct >= 0.4 ? 2 : 1 }
}

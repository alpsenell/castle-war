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
    static let lake = 13.0                           // radius of the lake in the middle of a four-castle arena
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
    static let rulesVersion = 5                      // bumped whenever an online match would play out differently
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

/// Direction in degrees (positive = right of the shooter) and power 0...100, relative to the
/// castle aimed at. `target` -1 means the castle across the field.
struct Aim: Equatable {
    var yaw = 0.0
    var power = 50.0
    var target = -1
}

struct Block {
    let id: Int
    let x: Int, y: Int, z: Int
    let len: Int
    let dir: Int        // 1 runs along x, 2 along z
    let mat: UInt8      // 1 stone, 2 team colour, 3 trim, 4 heart, 5 reinforced stone, 6 decoy crystal
    var alive = true
    var hp: UInt8 = 1   // reinforced stone takes two blasts
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
    /// Reinforced blocks that took their first blast and still stand.
    var crack: [Int] = []
    /// Decoy hearts this damage gave away.
    var decoys: [Int] = []
    mutating func add(_ d: Damage) {
        blast += d.blast; fall += d.fall; cells += d.cells; heart += d.heart; crack += d.crack
        decoys += d.decoys.filter { !decoys.contains($0) }
    }
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
    /// Side whose aegis heart just threw up a shield.
    var aegis: Int?
}

@inline(__always) func cellIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * K.gw + x) * K.gd + z }

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

// MARK: - Castle designs

/// Building pieces. A tile is 2×2 grid cells; `span` is the piece's footprint in tiles.
enum PieceKind: Int, CaseIterable, Identifiable {
    case wallLow = 1, wallHigh, tower, tallTower, bastion, keep, heart, wallStrong, shelter, moat, decoy
    var id: Int { rawValue }
    var span: Int {
        switch self {
        case .wallLow, .wallHigh, .heart, .wallStrong, .moat, .decoy: return 1
        case .tower, .tallTower, .bastion: return 2
        case .keep, .shelter: return 3
        }
    }
    /// Pieces that may sit in the open middle tile of a shelter.
    var fitsUnderShelter: Bool { self == .heart || self == .decoy }
}

/// What the heart can do besides being protected. Chosen in the builder, unlocked by level.
enum HeartKind: Int, CaseIterable, Identifiable {
    case crystal = 0, living, aegis, titan
    var id: Int { rawValue }
    /// Stone it costs on top of the free crystal heart.
    var cost: Int { [0, 80, 80, 100][rawValue] }
    var level: Int { [1, 4, 7, 10][rawValue] }
    /// Courses of crystal it stands.
    var courses: Int { self == .titan ? 4 : 3 }
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
    var heart = HeartKind.crystal

    static let rows = K.gw / 2, cols = K.gd / 2
    static let budget = 2400, minimum = 1200
    static let maxDecoys = 2

    private static let costs: [PieceKind: Int] = {
        var out: [PieceKind: Int] = [:]
        for k in PieceKind.allCases {
            var p = Plan()
            p.add(Piece(kind: k, tx: 4, tz: 4))
            out[k] = p.vox.reduce(0) { $0 + ($1 == 0 ? 0 : $1 == 5 ? 2 : 1) }
        }
        out[.heart] = 0
        out[.moat] = 30
        out[.decoy] = 80
        return out
    }()

    static func cost(of kind: PieceKind) -> Int { costs[kind] ?? 0 }
    var cost: Int { pieces.reduce(heart.cost) { $0 + CastleDesign.cost(of: $1.kind) } }
    var keeps: Int { pieces.filter { $0.kind == .keep }.count }
    var hearts: Int { pieces.filter { $0.kind == .heart }.count }
    var decoys: Int { pieces.filter { $0.kind == .decoy }.count }

    /// Does a piece take up a tile? A shelter leaves its middle tile open for a heart.
    static func covers(_ p: Piece, row tx: Int, col tz: Int) -> Bool {
        let n = p.kind.span
        guard tx >= p.tx && tx < p.tx + n && tz >= p.tz && tz < p.tz + n else { return false }
        return p.kind != .shelter || tx != p.tx + 1 || tz != p.tz + 1
    }

    /// Index of the piece covering a tile, if any.
    func piece(atRow tx: Int, col tz: Int) -> Int? {
        pieces.firstIndex { CastleDesign.covers($0, row: tx, col: tz) }
    }

    func fits(_ kind: PieceKind, row tx: Int, col tz: Int) -> Bool {
        let n = kind.span
        guard tx >= 0, tz >= 0, tx + n <= CastleDesign.rows, tz + n <= CastleDesign.cols else { return false }
        let new = Piece(kind: kind, tx: tx, tz: tz)
        for p in pieces {
            for r in tx..<tx + n { for c in tz..<tz + n where CastleDesign.covers(new, row: r, col: c) && CastleDesign.covers(p, row: r, col: c) { return false } }
            // Only a heart or a decoy goes in the middle of a shelter.
            if p.kind == .shelter, !kind.fitsUnderShelter, tx <= p.tx + 1, p.tx + 1 < tx + n, tz <= p.tz + 1, p.tz + 1 < tz + n { return false }
            if kind == .shelter, !p.kind.fitsUnderShelter, p.tx <= tx + 1, tx + 1 < p.tx + p.kind.span, p.tz <= tz + 1, tz + 1 < p.tz + p.kind.span { return false }
        }
        return true
    }

    /// What stops this design from being played, if anything.
    enum Problem { case noHeart, manyHearts, manyKeeps, manyDecoys, tooSmall, overBudget, overlap }
    var problem: Problem? {
        var seen = CastleDesign()
        for p in pieces {
            if !seen.fits(p.kind, row: p.tx, col: p.tz) { return .overlap }
            seen.pieces.append(p)
        }
        if hearts == 0 { return .noHeart }
        if hearts > 1 { return .manyHearts }
        if keeps > 1 { return .manyKeeps }
        if decoys > CastleDesign.maxDecoys { return .manyDecoys }
        if cost > CastleDesign.budget { return .overBudget }
        if cost < CastleDesign.minimum { return .tooSmall }
        return nil
    }

    /// Flat form for storage and the network: kind, row, column per piece, then the heart kind
    /// as a triple led by `heartTag` when it is not the plain crystal.
    var encoded: [Int] {
        pieces.flatMap { [$0.kind.rawValue, $0.tx, $0.tz] } + (heart == .crystal ? [] : [CastleDesign.heartTag, heart.rawValue, 0])
    }
    static let heartTag = 100

    /// Rebuilds a design from its flat form. Returns nil for anything that is not a playable castle.
    init?(encoded: [Int]) {
        guard let d = CastleDesign.unchecked(encoded), d.problem == nil else { return nil }
        self = d
    }

    private static func unchecked(_ encoded: [Int]) -> CastleDesign? {
        guard encoded.count % 3 == 0, encoded.count <= 3 * (rows * cols + 1) else { return nil }
        var d = CastleDesign()
        for i in stride(from: 0, to: encoded.count, by: 3) {
            if encoded[i] == heartTag {
                guard let h = HeartKind(rawValue: encoded[i + 1]) else { return nil }
                d.heart = h
                continue
            }
            guard let k = PieceKind(rawValue: encoded[i]) else { return nil }
            d.pieces.append(Piece(kind: k, tx: encoded[i + 1], tz: encoded[i + 2]))
        }
        return d
    }

    init(pieces: [Piece] = []) { self.pieces = pieces }

    /// Reads a castle saved before hearts existed: the heart goes on the free tile nearest the back centre.
    static func migrating(encoded: [Int]) -> CastleDesign? {
        if let d = CastleDesign(encoded: encoded) { return d }
        guard var d = unchecked(encoded), d.hearts == 0 else { return nil }
        var spots: [(Int, Int)] = []
        for r in 0..<rows { for c in 0..<cols where d.fits(.heart, row: r, col: c) { spots.append((r, c)) } }
        let mid = cols / 2
        guard let best = spots.min(by: { abs($0.0 - 2) * 2 + abs($0.1 - mid) < abs($1.0 - 2) * 2 + abs($1.1 - mid) }) else { return nil }
        d.pieces.append(Piece(kind: .heart, tx: best.0, tz: best.1))
        return d.problem == nil ? d : nil
    }

    /// Reads a drawing: one string per tile row, back of the castle first.
    /// w/W low/high wall, S reinforced wall, T tower, A tall tower, B bastion, K keep, R shelter (top-left tile of the piece),
    /// H heart, D decoy, M moat, anything else empty.
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
                case "S": kind = .wallStrong
                case "R": kind = .shelter
                case "M": kind = .moat
                case "D": kind = .decoy
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
        "...MMMMMMMMM...",
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
        "w......D......w",
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
        "..W....D....W..",
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
        "++WSSWW.WWSSW++",
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
        "A+wwwwwwwwwwwA+",
        "++....R++....++",
        "w..B+.+H+.B+..w",
        "w..++.+++.++..w",
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
    /// Cells of each decoy heart, and the corner cell of each moat tile.
    var decoys: [[Int]] = []
    var moats: [(x: Int, z: Int)] = []

    init() {}

    var heartKind = HeartKind.crystal

    init(_ design: CastleDesign) {
        heartKind = design.heart
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
        case .wallStrong: strongWall(x0, z0)
        case .shelter: shelter(x0, z0)
        case .moat: moats.append((x0, z0))
        case .decoy: decoy(x0, z0)
        }
    }

    /// Looks exactly like the heart from across the river. Breaking it wins nothing.
    private mutating func decoy(_ x0: Int, _ z0: Int) {
        box(x0, x0 + 1, 0, 2, z0, z0 + 1, 6)
        var cells: [Int] = []
        for y in 0...2 { for x in x0...x0 + 1 { for z in z0...z0 + 1 { cells.append(cellIndex(x, y, z)) } } }
        decoys.append(cells)
    }

    /// Iron-banded wall: every stone in it takes two blasts to break.
    private mutating func strongWall(_ x0: Int, _ z0: Int) {
        box(x0, x0 + 1, 0, 5, z0, z0 + 1, 5)
        for x in x0...x0 + 1 { for z in z0...z0 + 1 where (x + z) % 2 == 0 { set(x, 6, z, 5) } }
    }

    /// A stone roof on two side walls over a 3×3 tile area, open front and back. Its middle tile
    /// holds the heart, out of reach of shots that drop from above.
    private mutating func shelter(_ x0: Int, _ z0: Int) {
        box(x0, x0 + 5, 0, 5, z0, z0, 1)
        box(x0, x0 + 5, 0, 5, z0 + 5, z0 + 5, 1)
        box(x0, x0 + 5, 6, 6, z0, z0 + 5, 3, 2)          // laid across, so every slab rests on a side wall
        crenel(x0, x0 + 5, 7, z0, z0 + 5, 1)
    }

    /// The heart: three courses of glowing crystal, harder to break than stone. Lose it and the castle falls.
    private mutating func heart(_ x0: Int, _ z0: Int) {
        box(x0, x0 + 1, 0, heartKind.courses - 1, z0, z0 + 1, 4)
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
    /// The castle's frame: its back corner on the ground, the way its front faces (local x) and its right (local z).
    let origin: Vec3
    let fx: Double, fz: Double, rx: Double, rz: Double
    private(set) var blocks: [Block]
    let cellBlock: [Int]
    let decor: [DecorSpec]
    let total: Int
    private(set) var aliveCells: Int
    /// Heart cells at the start and now. The castle falls when the last one is gone.
    let heartTotal: Int
    private(set) var heartAlive: Int
    /// Decoy heart of each decoy block, and which decoys have been found out.
    let decoyOf: [Int: Int]
    private(set) var decoyRevealed: [Bool]
    /// Corner cells of the moat tiles. A shot that lands in one only splashes.
    let moats: [(x: Int, z: Int)]
    let heartKind: HeartKind

    init(side: Int, design: CastleDesign, arena: Arena = .duel) {
        self.side = side
        let f = arena.forward(side), r = arena.right(side)
        fx = f.x; fz = f.z; rx = r.x; rz = r.z
        origin = Vec3(x: -K.xEdge * f.x, y: 0, z: -K.xEdge * f.z)
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
        var dOf: [Int: Int] = [:]
        for (i, cells) in plan.decoys.enumerated() {
            for c in cells where t.cellBlock[c] >= 0 { dOf[t.cellBlock[c]] = i }
        }
        decoyOf = dOf
        decoyRevealed = Array(repeating: false, count: plan.decoys.count)
        moats = plan.moats
        heartKind = design.heart
        for i in blocks.indices where blocks[i].mat == 5 { blocks[i].hp = 2 }
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
    var heartCenter: Vec3? { middle(blocks.filter { $0.alive && $0.mat == 4 }) }

    /// Middle of a decoy, whether or not it has been found out.
    func decoyCenter(_ i: Int) -> Vec3? { middle(blocks.filter { $0.alive && decoyOf[$0.id] == i }) }

    /// Everything an attacker would take for the heart: the real one and the decoys not yet found out.
    var heartLookalikes: [Vec3] {
        var out: [Vec3] = []
        if let h = heartCenter { out.append(h) }
        for i in decoyRevealed.indices where !decoyRevealed[i] { if let c = decoyCenter(i) { out.append(c) } }
        return out
    }

    private func middle(_ live: [Block]) -> Vec3? {
        guard !live.isEmpty else { return nil }
        var c = Vec3()
        for b in live { let p = center(of: b); c.x += p.x; c.y += p.y; c.z += p.z }
        let n = Double(live.count)
        return Vec3(x: c.x / n, y: c.y / n, z: c.z / n)
    }

    /// True when a world point on the ground lies in one of this castle's moats.
    /// A world point in grid units: x from the back toward the front, z from the owner's left.
    func local(_ px: Double, _ pz: Double) -> (x: Double, z: Double) {
        let dx = px - origin.x, dz = pz - origin.z
        return (dx * fx + dz * fz, dx * rx + dz * rz + Double(K.gd) / 2)
    }

    /// True when a castle's local x axis runs along the world x axis (seats west and east).
    var alongWorldX: Bool { fx != 0 }

    func inMoat(_ px: Double, _ pz: Double) -> Bool {
        let (lx, lz) = local(px, pz)
        return moats.contains { lx >= Double($0.x) && lx <= Double($0.x + 2) && lz >= Double($0.z) && lz <= Double($0.z + 2) }
    }

    func center(of b: Block) -> Vec3 {
        let lx = Double(b.x) + (b.dir == 1 ? Double(b.len) / 2 : 0.5)
        let lz = Double(b.z) + (b.dir == 2 ? Double(b.len) / 2 : 0.5)
        return worldPoint(gx: lx, gy: Double(b.y) + 0.5, gz: lz)
    }

    func worldPoint(gx: Double, gy: Double, gz: Double) -> Vec3 {
        let w = gz - Double(K.gd) / 2
        return Vec3(x: origin.x + gx * fx + w * rx, y: gy * K.lh, z: origin.z + gx * fz + w * rz)
    }

    func hit(_ px: Double, _ py: Double, _ pz: Double) -> Bool {
        let r = K.ballR, (lx, lz) = local(px, pz)
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
        let (lx, lz) = local(c.x, c.z)
        if lx < -R || lx > Double(K.gw) + R || lz < -R || lz > Double(K.gd) + R { return out }
        var dead = [Bool](repeating: false, count: blocks.count)
        let r2 = R * R, h2 = r2 * K.heartReach * K.heartReach
        for b in blocks where b.alive {
            for i in 0..<b.len {
                let dx = Double(b.x + (b.dir == 1 ? i : 0)) + 0.5 - lx
                let dy = (Double(b.y) + 0.5) * K.lh - c.y
                let dz = Double(b.z + (b.dir == 2 ? i : 0)) + 0.5 - lz
                // Decoys break like the heart, so a near miss tells nothing either way.
                if dx * dx + dy * dy + dz * dz <= (b.mat == 4 || b.mat == 6 ? h2 : r2) {
                    if b.hp > 1 { out.crack.append(b.id); break }
                    dead[b.id] = true; out.blast.append(b.id); out.cells += b.len
                    if b.mat == 4 { out.heart += b.len }
                    if let d = decoyOf[b.id], !decoyRevealed[d], !out.decoys.contains(d) { out.decoys.append(d) }
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
                if let d = decoyOf[b.id], !decoyRevealed[d], !out.decoys.contains(d) { out.decoys.append(d) }
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
        for id in d.crack where blocks[id].alive && blocks[id].hp > 1 { blocks[id].hp -= 1 }
        for i in d.decoys { decoyRevealed[i] = true }
    }

    /// Takes over the state of an earlier castle built from the same design: what fell stays down.
    func adopt(_ other: Castle) {
        guard other.blocks.count == blocks.count else { return }
        for i in blocks.indices { blocks[i].alive = other.blocks[i].alive; blocks[i].hp = other.blocks[i].hp }
        decoyRevealed = other.decoyRevealed
        aliveCells = other.aliveCells
        heartAlive = other.heartAlive
    }

    /// A living heart grows back one lost crystal block. Returns it, if one could grow.
    func regrowHeart() -> Int? {
        guard heartKind == .living, heartAlive > 0, heartAlive < heartTotal else { return nil }
        for i in blocks.indices where blocks[i].mat == 4 && !blocks[i].alive && !blocks[i].ghost {
            let b = blocks[i]
            var held = b.y == 0
            if !held {
                for k in 0..<b.len {
                    let id = cellBlock[cellIndex(b.x + (b.dir == 1 ? k : 0), b.y - 1, b.z + (b.dir == 2 ? k : 0))]
                    if id >= 0 && blocks[id].alive { held = true; break }
                }
            }
            guard held else { continue }
            blocks[i].alive = true
            aliveCells += b.len
            heartAlive += b.len
            return i
        }
        return nil
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
                blocks[i].alive = true; blocks[i].hp = b.mat == 5 ? 2 : 1; left -= b.len; aliveCells += b.len; out.append(i)
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
    /// A shielded castle takes the next blast at reduced radius.
    private(set) var shield: [Bool]
    private(set) var pickup: Pickup?
    private var nextSpawn = 2
    /// An aegis heart shields its castle once per match.
    private(set) var aegisUsed: [Bool]
    /// Heart block that grew back at the start of the last turn, and on which side.
    private(set) var regrown: (side: Int, block: Int)?

    init(seed: UInt32, first: Int, designs: [CastleDesign] = [.classic, .classic], rules: MatchRules = MatchRules(), arena: Arena = .duel) {
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

    /// This turn's gold target: a block on an enemy castle that is open to the sky.
    /// Landing a shot within `K.critRange` of it is a critical hit.
    func goldTarget() -> Vec3? {
        var open: [Vec3] = []
        for e in enemies {
            let c = castles[e]
            for b in c.blocks where b.alive && b.y >= 2 && c.isOpenToSky(b) { open.append(c.center(of: b)) }
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
            if y <= r {
                y = r; path[path.count - 1].y = r
                kind = arena.isWater(x, z) || castles.contains(where: { $0.inMoat(x, z) }) ? .water : .ground
                break
            }
            if let i = castles.firstIndex(where: { $0.hit(x, y, z) }) { kind = .castle; side = i; break }
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
        if kind == .castle, side != shooter, let t = target {
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
        let s = res.shooter, n = castles.count
        var out = ShotOutcome(damage: Array(repeating: Damage(), count: n))
        var struck = Array(repeating: false, count: n)
        for b in res.blasts {
            for (i, c) in castles.enumerated() {
                let d = c.damage(at: b.center, radius: b.radius * (shield[i] ? K.shieldFactor : 1))
                if d.cells > 0 { struck[i] = true }
                c.kill(d)
                out.damage[i].add(d)
            }
        }
        for i in 0..<n where shield[i] && (struck[i] || (res.kind == .castle && res.side == i)) {
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
        for e in 0..<n where e != s { dealt += Double(out.damage[e].cells) / Double(castles[e].total) }
        if res.mega { charge[s] = 0 }
        if dealt > 0 {
            streak[s] += 1
            if !res.mega {
                let combo = 1 + 0.2 * Double(min(streak[s] - 1, 3))
                charge[s] = min(1, charge[s] + (dealt * 2.4 * combo + (res.crit ? 0.15 : 0)) * rules.megaRate)
            }
            for e in 0..<n where e != s && out.damage[e].cells > 0 {          // taking damage charges the defender: a way back in
                charge[e] = min(1, charge[e] + Double(out.damage[e].cells) / Double(castles[e].total) * 1.5 * rules.megaRate)
            }
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

    /// The side whose heart this shot would break, worked out before it lands. Overlapping
    /// blasts can count a block twice, so it may now and then call a shot that falls just short.
    func wouldBreakHeart(_ res: ShotResult) -> Int? {
        for (i, c) in castles.enumerated() where c.heartAlive > 0 {
            var cells = 0
            for b in res.blasts { cells += c.damage(at: b.center, radius: b.radius * (shield[i] ? K.shieldFactor : 1)).heart }
            if cells >= c.heartAlive { return i }
        }
        return nil
    }

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
        /// The castle it is going for.
        var target = 0
    }

    private static func gauss() -> Double { (Double.random(in: 0...1) + Double.random(in: 0...1) + Double.random(in: 0...1) - 1.5) * 1.15 }

    private static func solve(arena: Arena, side: Int, heading h: Double, target t: Vec3, wind w: (x: Double, z: Double), gravity g: Double) -> (yaw: Double, v: Double)? {
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
        let low = foes.map { battle.castles[$0].heartPct }.min() ?? 1
        if low < 1, Double.random(in: 0...1) < 0.55 { return foes.filter { battle.castles[$0].heartPct == low }.randomElement()! }
        return foes.randomElement()!
    }

    static func choose(battle: Battle, side: Int, difficulty: Difficulty, wind w: (x: Double, z: Double)) -> Choice {
        let foe = pickTarget(battle: battle, side: side)
        let enemy = battle.castles[foe]
        let alive = enemy.blocks.filter { $0.alive }
        guard !alive.isEmpty else { return Choice(aim: Aim(target: foe), target: foe) }
        let mega = battle.charge[side] >= 1 && (difficulty != .kolay || Bool.random())
        var ammo = Ammo.standard
        if !mega, Double.random(in: 0...1) < difficulty.ammoChance {
            ammo = Ammo.specials.filter { battle.stock[side][$0.rawValue] > 0 }.randomElement() ?? .standard
        }
        let radius = K.blastR * battle.rules.blastScale * (mega ? K.megaBoost : 1)
        func worth(_ d: Damage) -> Int { d.cells + (d.heart > 0 ? 180 : 0) + d.decoys.count * 180 }
        var best = enemy.center(of: alive[0]), bestScore = -1
        for _ in 0..<difficulty.samples {
            let c = enemy.center(of: alive.randomElement()!)
            let score = worth(enemy.damage(at: c, radius: radius))
            if score > bestScore { bestScore = score; best = c }
        }
        // Sometimes go for the gold target instead; better players do it more often. A homing shot always does.
        let center = battle.arena.castleCenter(foe)
        if ammo == .homing || Double.random(in: 0...1) < difficulty.goldChance, let t = battle.goldTarget(),
           (t.x - center.x) * (t.x - center.x) + (t.z - center.z) * (t.z - center.z) < 400 {
            let score = worth(enemy.damage(at: t, radius: radius * K.critBoost))
            if ammo == .homing || score > bestScore { bestScore = score; best = t }
        }
        // Going straight for the heart: the walls in front of it are what stops this.
        // It cannot tell a decoy from the heart until one breaks.
        if ammo != .homing, Double.random(in: 0...1) < difficulty.heartChance, let h = enemy.heartLookalikes.randomElement() { best = h }
        let heading = battle.arena.heading(from: side, to: foe)
        let sol = solve(arena: battle.arena, side: side, heading: heading, target: best, wind: w, gravity: battle.rules.gravity) ?? (yaw: 0, v: 32)
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

// MARK: - Gauntlet

/// Castle after castle until yours falls. Damage carries over; a win patches some of it up.
enum Gauntlet {
    static let repairCells = 420

    struct Foe {
        let design: CastleDesign
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
enum CastleCode {
    static let prefix = "KS-"
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func encode(_ d: CastleDesign) -> String {
        var bits: [Bool] = []
        func put(_ v: Int, _ n: Int) { for i in stride(from: n - 1, through: 0, by: -1) { bits.append((v >> i) & 1 == 1) } }
        put(1, 4)
        put(d.heart.rawValue, 4)
        put(d.pieces.count, 8)
        for p in d.pieces { put(p.kind.rawValue, 4); put(p.tx, 4); put(p.tz, 4) }
        put(checksum(d), 8)
        while bits.count % 5 != 0 { bits.append(false) }
        var out = prefix
        for i in stride(from: 0, to: bits.count, by: 5) {
            var v = 0
            for b in bits[i..<i + 5] { v = v * 2 + (b ? 1 : 0) }
            out.append(alphabet[v])
        }
        return out
    }

    /// Finds a castle code anywhere in a piece of text. Returns nil unless it is a playable castle.
    static func decode(_ text: String) -> CastleDesign? {
        let up = text.uppercased()
        guard let start = up.range(of: prefix) else { return nil }
        var bits: [Bool] = []
        for ch in up[start.upperBound...] {
            let c: Character = ch == "O" ? "0" : ch == "I" || ch == "L" ? "1" : ch
            guard let v = alphabet.firstIndex(of: c) else { break }
            for i in stride(from: 4, through: 0, by: -1) { bits.append((v >> i) & 1 == 1) }
        }
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
        guard take(8) == checksum(d), d.problem == nil else { return nil }
        return d
    }

    private static func checksum(_ d: CastleDesign) -> Int {
        var h = 17 &* 31 &+ d.heart.rawValue
        for p in d.pieces { h = h &* 31 &+ p.kind.rawValue &* 225 &+ p.tx &* 15 &+ p.tz }
        return ((h % 256) + 256) % 256
    }
}

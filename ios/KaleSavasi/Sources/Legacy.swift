import Foundation

// Castles as they were laid out before bricks: pieces on an 11×15 tile grid. Kept only to read
// old saves and version 1 castle codes; `BrickDesign(legacy:)` rebuilds them from stamps.

/// Building pieces. A tile is one brick unit square; `span` is the piece's footprint in tiles.
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

struct Piece: Equatable {
    var kind: PieceKind
    var tx: Int      // tile row, 0 = back of the castle
    var tz: Int      // tile column, 0 = the owner's left
}

/// A castle as its owner laid it out before bricks: pieces paid for in stone.
struct CastleDesign: Equatable {
    var pieces: [Piece] = []
    var heart = HeartKind.crystal

    static let rows = BK.depth, cols = BK.width
    static let budget = 2400, minimum = 1200
    static let maxDecoys = 2

    /// Stone each piece cost, as the old voxel castles counted it.
    private static let costs: [PieceKind: Int] = [.wallLow: 22, .wallHigh: 34, .tower: 142, .tallTower: 190, .bastion: 102, .keep: 307,
                                                  .heart: 0, .wallStrong: 52, .shelter: 118, .moat: 30, .decoy: 80]

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

/// A castle as bricks, whichever form it was kept in.
func asBricks(_ d: CastleDesign) -> BrickDesign {
    let b = BrickDesign(legacy: d)
    return b.problem == nil ? b : Presets.classic
}
func asBricks(_ d: BrickDesign) -> BrickDesign { d.problem == nil ? d : Presets.classic }

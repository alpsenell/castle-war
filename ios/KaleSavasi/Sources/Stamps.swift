import Foundation

// Prefab stamps: a tower, a wall run, a keep and so on, expanded into bricks. The builder offers
// them as one-tap starting points; presets, campaign castles and castles saved before bricks are
// all built from them.

enum Stamp: Int, CaseIterable, Identifiable {
    case wall, tallWall, tower, tallTower, keep, gatehouse, shrine, bridge
    var id: Int { rawValue }

    /// Footprint in snap steps at rotation 0 (along x, along z).
    var footprint: (x: Int, z: Int) {
        switch self {
        case .wall, .tallWall: return (2, 8)
        case .tower, .tallTower: return (4, 4)
        case .keep: return (6, 6)
        case .gatehouse: return (4, 14)
        case .shrine: return (6, 6)
        case .bridge: return (2, 8)
        }
    }

    /// Where the heart goes inside the stamp, at rotation 0, if it has a place for one.
    var heartSpot: (x: Int, z: Int)? { self == .shrine ? (2, 2) : nil }

    /// The stamp's bricks with its minimum corner on the ground at (x, z), turned `rot` quarter
    /// turns, built mainly in `material`.
    func bricks(x: Int, z: Int, rot: Int = 0, material: BrickMaterial = .stone) -> [PlacedBrick] {
        var m = Mason()
        let wood: BrickMaterial = material == .ice ? .ice : .wood
        switch self {
        case .wall: m.wall(x: 0, z: 0, length: 8, courses: 3, material: material)
        case .tallWall: m.wall(x: 0, z: 0, length: 8, courses: 5, material: material, windows: true)
        case .tower: m.tower(x: 0, z: 0, courses: 5, material: material, roof: .pyramid, roofMaterial: wood)
        case .tallTower: m.tower(x: 0, z: 0, courses: 7, material: material, roof: .cone, roofMaterial: wood)
        case .keep: m.keep(x: 0, z: 0, material: material, floors: wood, roof: wood)
        case .gatehouse: m.gatehouse(x: 0, z: 0, material: material, roof: wood)
        case .shrine: m.shrine(x: 0, z: 0, material: material, roof: wood)
        case .bridge: m.bridge(x: 0, z: 0, material: material == .stone ? .wood : material, piers: material)
        }
        return Mason.turn(m.bricks, footprint: footprint, quarters: rot).map { b in
            var b = b
            b.x += x; b.z += z
            return b
        }
    }
}

/// Lays bricks one by one, skipping any that would not fit. The helpers below build the parts
/// castles are made of; stamps, presets and old castles all use them.
struct Mason {
    var bricks: [PlacedBrick] = []
    /// Bricks that did not fit; ready-made castles keep this at zero.
    private(set) var skipped = 0
    private var lastMisfit: PlacedBrick?

    enum Roof { case cone, pyramid, battlements, none }

    @discardableResult
    mutating func put(_ s: BrickShape, _ m: BrickMaterial, _ x: Int, _ y: Int, _ z: Int, rot: Int = 0) -> Bool {
        let b = PlacedBrick(shape: s, material: m, x: x, y: y, z: z, rot: rot)
        guard b.inBounds, !bricks.contains(where: { $0.overlaps(b) }) else { skipped += 1; lastMisfit = b; return false }
        bricks.append(b)
        return true
    }

    mutating func add(_ list: [PlacedBrick]) { for b in list { put(b.shape, b.material, b.x, b.y, b.z, rot: b.rot) } }

    /// Turns bricks a number of quarter turns inside a footprint, keeping it at the origin.
    static func turn(_ list: [PlacedBrick], footprint f: (x: Int, z: Int), quarters: Int) -> [PlacedBrick] {
        var out = list, fx = f.x, fz = f.z
        for _ in 0..<((quarters % 4) + 4) % 4 {
            out = out.map { b in
                var n = b
                n.x = b.z
                n.z = fx - b.x - b.extent.x
                n.rot = (b.rot + 1) % 4
                return n
            }
            (fx, fz) = (fz, fx)
        }
        return out
    }

    private static func beam(_ len: Int) -> BrickShape { [2: .cube, 4: .beam2, 6: .beam3, 8: .beam4][len] ?? .cube }

    /// One course of a wall: the longest bricks that fit, after a first brick `lead` steps long.
    mutating func course(x: Int, y: Int, z: Int, length: Int, alongX: Bool, lead: Int, material: BrickMaterial) {
        var at = 0, parts: [Int] = []
        if lead > 0 && lead < length { parts.append(lead); at = lead }
        while at < length {
            let n = min(8, length - at)
            parts.append(n == 1 ? 2 : n)
            at += n
        }
        var p = 0
        for n in parts {
            if alongX { put(Mason.beam(n), material, x + p, y, z, rot: 1) } else { put(Mason.beam(n), material, x, y, z + p) }
            p += n
        }
    }

    /// A wall one brick thick in running bond, `courses` bricks high, with battlements on top.
    mutating func wall(x: Int, z: Int, length: Int, alongX: Bool = false, courses: Int, material: BrickMaterial, y: Int = 0,
                       top: Roof = .battlements, cap: BrickMaterial? = nil, windows: Bool = false) {
        for c in 0..<courses {
            let m = c == courses - 1 ? cap ?? material : material
            let yy = y + c * 2
            if windows && c == courses - 2 && length >= 6 {
                for k in 0..<length / 2 {
                    let shape: BrickShape = k % 3 == 1 ? .window : .cube
                    if alongX { put(shape, m, x + k * 2, yy, z, rot: 1) } else { put(shape, m, x, yy, z + k * 2) }
                }
                continue
            }
            course(x: x, y: yy, z: z, length: length, alongX: alongX, lead: c % 2 == 0 ? 0 : (length >= 8 ? 4 : 2), material: m)
        }
        if top == .battlements { crenels(x: x, y: y + courses * 2, z: z, length: length, alongX: alongX, material: cap ?? material) }
    }

    /// Battlements on every other brick unit of a wall top, always one at each end.
    mutating func crenels(x: Int, y: Int, z: Int, length: Int, alongX: Bool, material: BrickMaterial) {
        let units = length / 2
        for k in 0..<units where k % 2 == 0 || k == units - 1 {
            if alongX { put(.battlement, material, x + k * 2, y, z, rot: 1) } else { put(.battlement, material, x, y, z + k * 2) }
        }
    }

    /// A row of upright logs, each standing on its own.
    mutating func palisade(x: Int, z: Int, length: Int, alongX: Bool = false, material: BrickMaterial = .wood, tall: Bool = true) {
        for k in 0..<length / 2 {
            let s: BrickShape = tall && k % 3 != 1 ? .pillar3 : .pillar2
            if alongX { put(s, material, x + k * 2, 0, z) } else { put(s, material, x, 0, z + k * 2) }
        }
    }

    /// A square tower two bricks across: courses laid crosswise, a ring of windows near the top and a roof.
    mutating func tower(x: Int, z: Int, y: Int = 0, courses: Int, material: BrickMaterial, roof: Roof, roofMaterial: BrickMaterial, windows: Bool = true) {
        for c in 0..<courses {
            let yy = y + c * 2
            if windows && c == courses - 2 {
                put(.window, material, x, yy, z); put(.window, material, x + 2, yy, z + 2)
                put(.window, material, x + 2, yy, z, rot: 1); put(.window, material, x, yy, z + 2, rot: 1)
            } else if c % 2 == 0 {
                put(.beam2, material, x, yy, z); put(.beam2, material, x + 2, yy, z)
            } else {
                put(.beam2, material, x, yy, z, rot: 1); put(.beam2, material, x, yy, z + 2, rot: 1)
            }
        }
        let top = y + courses * 2
        switch roof {
        case .cone: put(.coneRoof, roofMaterial, x, top, z)
        case .pyramid: put(.pyramidRoof, roofMaterial, x, top, z)
        case .battlements: put(.battlement, roofMaterial, x, top, z); put(.battlement, roofMaterial, x + 2, top, z + 2)
        case .none: break
        }
    }

    /// A low solid block two bricks across, topped with battlements.
    mutating func bastion(x: Int, z: Int, material: BrickMaterial) {
        tower(x: x, z: z, courses: 3, material: material, roof: .battlements, roofMaterial: material, windows: false)
        put(.battlement, material, x + 2, 6, z); put(.battlement, material, x, 6, z + 2)
    }

    /// One course of a keep's ring, three bricks square with a hollow middle. `crossed` turns it a quarter.
    private mutating func ring(x: Int, y: Int, z: Int, crossed: Bool, material: BrickMaterial, window: BrickMaterial? = nil) {
        if !crossed {
            put(.beam3, material, x, y, z)
            put(.cube, material, x + 2, y, z); put(.cube, material, x + 2, y, z + 4)
            if let w = window {
                put(.cube, material, x + 4, y, z); put(.window, w, x + 4, y, z + 2); put(.cube, material, x + 4, y, z + 4)
            } else { put(.beam3, material, x + 4, y, z) }
        } else {
            put(.beam3, material, x, y, z, rot: 1); put(.beam3, material, x, y, z + 4, rot: 1)
            if let w = window { put(.window, w, x, y, z + 2, rot: 1); put(.window, w, x + 4, y, z + 2, rot: 1) }
            else { put(.cube, material, x, y, z + 2); put(.cube, material, x + 4, y, z + 2) }
        }
    }

    /// A hollow keep three bricks square: an arched door toward the enemy, two timber floors,
    /// windows on each storey and a roof.
    mutating func keep(x: Int, z: Int, material: BrickMaterial, floors: BrickMaterial, roof: BrickMaterial, storeys: Int = 3) {
        // Ground storey: the arch is the front wall.
        put(.beam3, material, x, 0, z)
        put(.cube, material, x + 2, 0, z); put(.cube, material, x + 2, 0, z + 4)
        put(.arch, material, x + 4, 0, z)
        put(.beam2, material, x, 2, z, rot: 1); put(.beam2, material, x, 2, z + 4, rot: 1); put(.cube, material, x, 2, z + 2)
        var y = 4
        for s in 1..<storeys {
            for k in 0..<3 { put(.plank, floors, x + k * 2, y, z) }
            y += 1
            ring(x: x, y: y, z: z, crossed: false, material: material, window: s == storeys - 1 ? nil : material)
            ring(x: x, y: y + 2, z: z, crossed: true, material: material, window: s == storeys - 1 ? material : nil)
            y += 4
        }
        if y + 3 <= BK.maxY { put(.pyramidRoof, roof, x + 1, y, z + 1) }
    }

    /// Two towers either side of a double arch, a walkway over it and battlements.
    mutating func gatehouse(x: Int, z: Int, material: BrickMaterial, roof: BrickMaterial, gate: BrickMaterial? = nil) {
        tower(x: x, z: z, courses: 5, material: material, roof: .pyramid, roofMaterial: roof)
        tower(x: x, z: z + 10, courses: 5, material: material, roof: .pyramid, roofMaterial: roof)
        put(.arch, gate ?? material, x, 0, z + 4); put(.arch, gate ?? material, x + 2, 0, z + 4)
        course(x: x, y: 4, z: z + 4, length: 6, alongX: false, lead: 0, material: material)
        course(x: x + 2, y: 4, z: z + 4, length: 6, alongX: false, lead: 2, material: material)
        for k in 0..<3 { put(.half, roof, x, 6, z + 4 + k * 2); put(.half, roof, x + 2, 6, z + 4 + k * 2) }
        crenels(x: x + 2, y: 7, z: z + 4, length: 6, alongX: false, material: material)
    }

    /// Two side walls under a roof of beams, open front and back; the heart goes in the middle.
    mutating func shrine(x: Int, z: Int, material: BrickMaterial, roof: BrickMaterial) {
        for dz in [0, 4] {
            put(.beam3, material, x, 0, z + dz, rot: 1)
            put(.beam2, material, x, 2, z + dz, rot: 1); put(.cube, material, x + 4, 2, z + dz)
            put(.beam3, material, x, 4, z + dz, rot: 1)
        }
        for k in 0..<3 { put(.beam3, roof == .wood ? material : roof, x + k * 2, 6, z) }
        put(.pyramidRoof, roof, x + 1, 8, z + 1)
    }

    /// A walkway on two piers.
    mutating func bridge(x: Int, z: Int, material: BrickMaterial, piers: BrickMaterial) {
        put(.pillar2, piers, x, 0, z); put(.pillar2, piers, x, 0, z + 6)
        put(.beam4, material, x, 4, z)
        put(.half, material, x, 6, z); put(.half, material, x, 6, z + 6)
        put(.battlement, piers, x, 7, z); put(.battlement, piers, x, 7, z + 6)
    }

    mutating func heart(x: Int, z: Int, y: Int = 0) { put(.pillar2, .heart, x, y, z) }
    mutating func decoy(x: Int, z: Int, y: Int = 0) { put(.pillar2, .decoy, x, y, z) }

    /// A strip of moat, one brick wide.
    mutating func moat(x: Int, z: Int, length: Int, alongX: Bool = false) {
        for k in 0..<length / 2 {
            if alongX { put(.moat, .stone, x + k * 2, 0, z) } else { put(.moat, .stone, x, 0, z + k * 2) }
        }
    }

    func design(_ heart: HeartKind = .crystal) -> BrickDesign {
        #if DEBUG
        if skipped > 0 { print("Mason: \(skipped) bricks did not fit, last \(lastMisfit.map { "\($0.shape)@\($0.x),\($0.y),\($0.z)" } ?? "")") }
        #endif
        return BrickDesign(bricks: bricks, heart: heart)
    }
}

extension BrickDesign {
    /// A castle saved before bricks existed, rebuilt from stamps: walls become running-bond walls,
    /// iron walls iron bricks, towers and keeps their stamps, the shelter a shrine over the heart.
    init(legacy: CastleDesign) {
        var m = Mason()
        let pieces = legacy.pieces
        func at(_ p: Piece) -> (x: Int, z: Int) { (p.tx * 2, p.tz * 2) }
        for p in pieces {
            let (x, z) = at(p)
            switch p.kind {
            case .keep: m.keep(x: x, z: z, material: .stone, floors: .wood, roof: .wood)
            case .shelter: m.shrine(x: x, z: z, material: .stone, roof: .wood)
            case .tower: m.tower(x: x, z: z, courses: 5, material: .stone, roof: .pyramid, roofMaterial: .wood)
            case .tallTower: m.tower(x: x, z: z, courses: 7, material: .stone, roof: .cone, roofMaterial: .wood)
            case .bastion: m.bastion(x: x, z: z, material: .stone)
            case .heart: m.heart(x: x, z: z)
            case .decoy: m.decoy(x: x, z: z)
            case .moat: m.put(.moat, .stone, x, 0, z)
            default: break
            }
        }
        // Wall tiles join into runs: rows first, then whatever is left by columns.
        var kind = [[PieceKind?]](repeating: Array(repeating: nil, count: CastleDesign.cols), count: CastleDesign.rows)
        for p in pieces where [.wallLow, .wallHigh, .wallStrong].contains(p.kind) { kind[p.tx][p.tz] = p.kind }
        var used = kind.map { $0.map { _ in false } }
        func build(_ k: PieceKind, x: Int, z: Int, tiles: Int, alongX: Bool) {
            let len = tiles * 2
            switch k {
            case .wallHigh: m.wall(x: x, z: z, length: len, alongX: alongX, courses: 5, material: .stone, windows: true)
            case .wallStrong: m.wall(x: x, z: z, length: len, alongX: alongX, courses: 3, material: .iron, cap: .stone)
            default: m.wall(x: x, z: z, length: len, alongX: alongX, courses: 3, material: .stone)
            }
        }
        for r in 0..<CastleDesign.rows {
            var c = 0
            while c < CastleDesign.cols {
                guard let k = kind[r][c] else { c += 1; continue }
                var e = c
                while e + 1 < CastleDesign.cols && kind[r][e + 1] == k { e += 1 }
                if e > c {
                    build(k, x: r * 2, z: c * 2, tiles: e - c + 1, alongX: false)
                    for i in c...e { used[r][i] = true }
                }
                c = e + 1
            }
        }
        for c in 0..<CastleDesign.cols {
            var r = 0
            while r < CastleDesign.rows {
                guard let k = kind[r][c], !used[r][c] else { r += 1; continue }
                var e = r
                while e + 1 < CastleDesign.rows && kind[e + 1][c] == k && !used[e + 1][c] { e += 1 }
                build(k, x: r * 2, z: c * 2, tiles: e - r + 1, alongX: true)
                r = e + 1
            }
        }
        self.init(bricks: m.bricks, heart: legacy.heart)
        // A castle that no longer fits the limits loses its battlements, then trades stone for wood.
        if bricks.count > BK.maxBricks || cost > BK.budget { bricks.removeAll { $0.shape == .battlement } }
        while bricks.count > BK.maxBricks, let i = bricks.indices.max(by: { bricks[$0].y < bricks[$1].y }), bricks[i].material != .heart { bricks.remove(at: i) }
        var i = bricks.count - 1
        while cost > BK.budget && i >= 0 {
            if bricks[i].material == .stone || bricks[i].material == .iron { bricks[i].material = .wood }
            i -= 1
        }
    }
}

// MARK: - Ready-made castles

/// Ready-made castles for the computer, the campaign, the daily siege and four-castle matches.
/// x runs from the back (0) toward the enemy (22), z across (0...30); everything in snap steps.
enum Presets {
    /// Stone curtain walls, four corner towers, a keep in the middle and the heart behind it.
    static let classic: BrickDesign = {
        var m = Mason()
        m.tower(x: 0, z: 0, courses: 7, material: .stone, roof: .cone, roofMaterial: .wood)
        m.tower(x: 0, z: 26, courses: 7, material: .stone, roof: .cone, roofMaterial: .wood)
        m.tower(x: 18, z: 0, courses: 5, material: .stone, roof: .pyramid, roofMaterial: .wood)
        m.tower(x: 18, z: 26, courses: 5, material: .stone, roof: .pyramid, roofMaterial: .wood)
        m.wall(x: 0, z: 4, length: 22, courses: 5, material: .stone, windows: true)
        m.wall(x: 4, z: 0, length: 14, alongX: true, courses: 3, material: .stone)
        m.wall(x: 4, z: 28, length: 14, alongX: true, courses: 3, material: .stone)
        m.wall(x: 20, z: 4, length: 8, courses: 3, material: .stone)
        m.wall(x: 20, z: 18, length: 8, courses: 3, material: .stone)
        m.add(Stamp.gatehouse.bricks(x: 18, z: 8, material: .stone).filter { $0.z >= 12 && $0.z < 18 })
        m.keep(x: 9, z: 12, material: .stone, floors: .wood, roof: .wood)
        m.heart(x: 4, z: 14)
        return m.design()
    }()

    /// A small timber fort: a log palisade, two lookout towers and the heart in a hut.
    static let stockade: BrickDesign = {
        var m = Mason()
        m.palisade(x: 18, z: 6, length: 18)
        m.palisade(x: 6, z: 4, length: 12, alongX: true)
        m.palisade(x: 6, z: 26, length: 12, alongX: true)
        m.palisade(x: 4, z: 6, length: 18)
        m.tower(x: 2, z: 2, courses: 4, material: .wood, roof: .pyramid, roofMaterial: .wood)
        m.tower(x: 2, z: 24, courses: 4, material: .wood, roof: .pyramid, roofMaterial: .wood)
        m.tower(x: 18, z: 2, courses: 4, material: .wood, roof: .cone, roofMaterial: .wood)
        m.tower(x: 18, z: 24, courses: 4, material: .wood, roof: .cone, roofMaterial: .wood)
        m.shrine(x: 9, z: 12, material: .stone, roof: .wood)
        m.heart(x: 11, z: 14)
        m.wall(x: 16, z: 10, length: 10, courses: 2, material: .stone)
        m.moat(x: 20, z: 6, length: 18)
        return m.design()
    }()

    /// Three walls one behind the other, each taller than the last, with the heart behind the third.
    static let layers: BrickDesign = {
        var m = Mason()
        m.wall(x: 18, z: 2, length: 26, courses: 2, material: .wood)
        m.wall(x: 12, z: 0, length: 30, courses: 3, material: .stone)
        m.wall(x: 6, z: 4, length: 22, courses: 5, material: .stone, windows: true)
        m.tower(x: 6, z: 0, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood)
        m.tower(x: 6, z: 26, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood)
        m.heart(x: 2, z: 14)
        m.decoy(x: 14, z: 8)
        m.wall(x: 0, z: 8, length: 14, courses: 2, material: .wood)
        m.moat(x: 20, z: 2, length: 26)
        return m.design()
    }()

    /// A crown of tall towers joined by low walls.
    static let spires: BrickDesign = {
        var m = Mason()
        for (x, z) in [(0, 0), (0, 26), (16, 0), (16, 26), (8, 13)] {
            m.tower(x: x, z: z, courses: 7, material: .stone, roof: .cone, roofMaterial: .wood)
        }
        m.tower(x: 18, z: 13, courses: 4, material: .stone, roof: .pyramid, roofMaterial: .wood)
        m.wall(x: 4, z: 0, length: 12, alongX: true, courses: 2, material: .stone)
        m.wall(x: 4, z: 28, length: 12, alongX: true, courses: 2, material: .stone)
        m.wall(x: 16, z: 4, length: 8, courses: 3, material: .stone)
        m.wall(x: 16, z: 18, length: 8, courses: 3, material: .stone)
        m.wall(x: 0, z: 4, length: 22, courses: 3, material: .stone)
        m.heart(x: 4, z: 14)
        m.decoy(x: 12, z: 8)
        m.decoy(x: 12, z: 20)
        return m.design()
    }()

    /// An inner keep behind iron-banded walls, bastions on the corners.
    static let citadel: BrickDesign = {
        var m = Mason()
        m.bastion(x: 2, z: 2, material: .stone)
        m.bastion(x: 2, z: 24, material: .stone)
        m.bastion(x: 16, z: 2, material: .stone)
        m.bastion(x: 16, z: 24, material: .stone)
        m.wall(x: 18, z: 6, length: 18, courses: 3, material: .iron, cap: .stone)
        m.wall(x: 2, z: 6, length: 18, courses: 4, material: .stone)
        m.wall(x: 6, z: 2, length: 10, alongX: true, courses: 4, material: .stone)
        m.wall(x: 6, z: 26, length: 10, alongX: true, courses: 4, material: .stone)
        m.keep(x: 9, z: 12, material: .stone, floors: .wood, roof: .stone)
        m.heart(x: 6, z: 9)
        m.decoy(x: 6, z: 19)
        return m.design()
    }()

    /// A deep front: a gatehouse in a thick double wall, the heart under a shrine far behind.
    static let bulwark: BrickDesign = {
        var m = Mason()
        m.add(Stamp.gatehouse.bricks(x: 18, z: 8, material: .stone))
        m.wall(x: 18, z: 0, length: 8, courses: 4, material: .stone)
        m.wall(x: 18, z: 22, length: 8, courses: 4, material: .stone)
        m.wall(x: 14, z: 0, length: 12, courses: 3, material: .iron, cap: .stone)
        m.wall(x: 14, z: 18, length: 12, courses: 3, material: .iron, cap: .stone)
        m.tower(x: 0, z: 0, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood)
        m.tower(x: 0, z: 26, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood)
        m.shrine(x: 4, z: 12, material: .stone, roof: .wood)
        m.heart(x: 6, z: 14)
        return m.design()
    }()

    /// Walls of ice on a stone footing; brittle, but light enough to topple onto attackers' shots.
    static let frost: BrickDesign = {
        var m = Mason()
        m.wall(x: 18, z: 4, length: 22, courses: 1, material: .stone, top: .none)
        m.wall(x: 18, z: 4, length: 22, courses: 3, material: .ice, y: 2)
        m.tower(x: 18, z: 0, courses: 6, material: .ice, roof: .cone, roofMaterial: .ice)
        m.tower(x: 18, z: 26, courses: 6, material: .ice, roof: .cone, roofMaterial: .ice)
        m.wall(x: 4, z: 0, length: 14, alongX: true, courses: 3, material: .ice)
        m.wall(x: 4, z: 28, length: 14, alongX: true, courses: 3, material: .ice)
        m.keep(x: 8, z: 12, material: .ice, floors: .stone, roof: .ice)
        m.tower(x: 0, z: 0, courses: 7, material: .ice, roof: .cone, roofMaterial: .ice)
        m.tower(x: 0, z: 26, courses: 7, material: .ice, roof: .cone, roofMaterial: .ice)
        m.wall(x: 0, z: 4, length: 22, courses: 3, material: .stone)
        m.heart(x: 3, z: 9)
        m.decoy(x: 3, z: 19)
        return m.design()
    }()

    /// Everything at once: tall towers, a shrine for the heart, an iron gate and a bridge.
    static let stronghold: BrickDesign = {
        var m = Mason()
        m.tower(x: 0, z: 0, courses: 7, material: .stone, roof: .cone, roofMaterial: .wood)
        m.tower(x: 0, z: 26, courses: 7, material: .stone, roof: .cone, roofMaterial: .wood)
        m.wall(x: 0, z: 4, length: 22, courses: 4, material: .stone)
        m.shrine(x: 4, z: 12, material: .stone, roof: .stone)
        m.heart(x: 6, z: 14)
        m.add(Stamp.gatehouse.bricks(x: 18, z: 8, material: .stone).map { b in
            var b = b
            if b.shape == .arch { b.material = .iron }
            return b
        })
        m.tower(x: 18, z: 0, courses: 5, material: .stone, roof: .battlements, roofMaterial: .stone)
        m.tower(x: 18, z: 26, courses: 5, material: .stone, roof: .battlements, roofMaterial: .stone)
        m.wall(x: 20, z: 4, length: 4, courses: 3, material: .stone)
        m.wall(x: 20, z: 22, length: 4, courses: 3, material: .stone)
        m.add(Stamp.bridge.bricks(x: 12, z: 2, material: .wood))
        m.add(Stamp.bridge.bricks(x: 12, z: 20, material: .wood))
        m.decoy(x: 12, z: 14)
        return m.design()
    }()

    static let all: [BrickDesign] = [classic, stockade, layers, spires, citadel, bulwark, frost, stronghold]

    /// A castle for a quick match against the computer, chosen by the match seed.
    static func pick(_ seed: UInt32) -> BrickDesign { all[Int(seed % UInt32(all.count))] }

    // MARK: Campaign

    /// The twelve campaign castles: timber forts first, then stone, ice and iron.
    static let stages: [BrickDesign] = [
        // 1: a lone timber palisade round a hut.
        {
            var m = Mason()
            m.palisade(x: 16, z: 8, length: 14)
            m.palisade(x: 8, z: 6, length: 8, alongX: true, tall: false)
            m.palisade(x: 8, z: 22, length: 8, alongX: true, tall: false)
            m.shrine(x: 8, z: 12, material: .wood, roof: .wood)
            m.heart(x: 10, z: 14)
            m.tower(x: 16, z: 4, courses: 3, material: .wood, roof: .pyramid, roofMaterial: .wood, windows: false)
            m.tower(x: 16, z: 22, courses: 3, material: .wood, roof: .pyramid, roofMaterial: .wood, windows: false)
            m.wall(x: 4, z: 8, length: 14, courses: 2, material: .wood)
            m.wall(x: 12, z: 2, length: 8, alongX: true, courses: 2, material: .wood)
            m.wall(x: 12, z: 26, length: 8, alongX: true, courses: 2, material: .wood)
            m.tower(x: 2, z: 2, courses: 4, material: .wood, roof: .cone, roofMaterial: .wood)
            m.tower(x: 2, z: 24, courses: 4, material: .wood, roof: .cone, roofMaterial: .wood)
            return m.design()
        }(),
        // 2: timber fort with two lookouts and a bridge.
        {
            var m = Mason()
            m.wall(x: 18, z: 4, length: 22, courses: 3, material: .wood)
            m.tower(x: 18, z: 0, courses: 5, material: .wood, roof: .cone, roofMaterial: .wood)
            m.tower(x: 18, z: 26, courses: 5, material: .wood, roof: .cone, roofMaterial: .wood)
            m.add(Stamp.bridge.bricks(x: 12, z: 11, material: .wood))
            m.wall(x: 6, z: 6, length: 18, courses: 3, material: .wood)
            m.heart(x: 2, z: 14)
            m.palisade(x: 0, z: 4, length: 8)
            m.palisade(x: 0, z: 18, length: 8)
            m.wall(x: 2, z: 2, length: 12, alongX: true, courses: 2, material: .wood)
            m.wall(x: 2, z: 26, length: 12, alongX: true, courses: 2, material: .wood)
            return m.design()
        }(),
        // 3: stone footing, timber above.
        {
            var m = Mason()
            m.wall(x: 18, z: 2, length: 26, courses: 1, material: .stone, top: .none)
            m.wall(x: 18, z: 2, length: 26, courses: 3, material: .wood, y: 2)
            m.tower(x: 12, z: 0, courses: 6, material: .stone, roof: .pyramid, roofMaterial: .wood)
            m.tower(x: 12, z: 26, courses: 6, material: .stone, roof: .pyramid, roofMaterial: .wood)
            m.keep(x: 6, z: 12, material: .wood, floors: .wood, roof: .wood, storeys: 2)
            m.heart(x: 2, z: 14)
            m.wall(x: 0, z: 6, length: 18, courses: 2, material: .stone)
            m.moat(x: 20, z: 2, length: 26)
            return m.design()
        }(),
        // 4: a stone tower house behind a low wall.
        {
            var m = Mason()
            m.wall(x: 18, z: 4, length: 22, courses: 3, material: .stone)
            m.keep(x: 8, z: 12, material: .stone, floors: .wood, roof: .wood)
            m.tower(x: 8, z: 4, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood)
            m.tower(x: 8, z: 22, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood)
            m.heart(x: 4, z: 14)
            m.wall(x: 0, z: 8, length: 14, courses: 3, material: .wood)
            m.palisade(x: 4, z: 2, length: 14, alongX: true)
            m.palisade(x: 4, z: 28, length: 14, alongX: true)
            return m.design()
        }(),
        classic,
        // 6: an ice outpost.
        {
            var m = Mason()
            m.wall(x: 18, z: 6, length: 18, courses: 3, material: .ice)
            m.tower(x: 18, z: 2, courses: 5, material: .ice, roof: .cone, roofMaterial: .ice)
            m.tower(x: 18, z: 24, courses: 5, material: .ice, roof: .cone, roofMaterial: .ice)
            m.shrine(x: 8, z: 12, material: .ice, roof: .ice)
            m.heart(x: 10, z: 14)
            m.wall(x: 15, z: 6, length: 18, courses: 2, material: .stone)
            m.tower(x: 2, z: 13, courses: 7, material: .ice, roof: .cone, roofMaterial: .ice)
            m.decoy(x: 4, z: 6)
            m.moat(x: 20, z: 6, length: 18)
            return m.design()
        }(),
        layers,
        // 8: a bridge fort: walkways between towers over a moat.
        {
            var m = Mason()
            for z in [0, 13, 26] { m.tower(x: 16, z: z, courses: 6, material: .stone, roof: .cone, roofMaterial: .wood) }
            m.add(Stamp.bridge.bricks(x: 16, z: 4, material: .wood).filter { $0.z + $0.extent.z <= 13 })
            m.add(Stamp.bridge.bricks(x: 16, z: 17, rot: 2, material: .wood).filter { $0.z >= 17 })
            m.wall(x: 10, z: 2, length: 26, courses: 3, material: .stone)
            m.keep(x: 2, z: 12, material: .stone, floors: .wood, roof: .wood)
            m.heart(x: 4, z: 6)
            m.decoy(x: 4, z: 22)
            m.moat(x: 20, z: 0, length: 30)
            return m.design()
        }(),
        spires,
        frost,
        citadel,
        stronghold,
    ]
}

import Foundation

// Castles built from rigid bricks. A design is a list of bricks placed on a snap grid; in a
// match each brick is a physics body that can slide, topple, fall and break. This file holds the
// design model and the types the rules, the physics world and the builder share.
//
// Coordinates, castle-local, in snap steps (half a brick unit):
//   x: depth, 0 = back of the castle, grows toward the enemy (the old `K.gw` axis)
//   y: height above the castle's ground
//   z: width, 0 = the owner's left (the old `K.gd` axis)
// One brick unit is `BK.unit` world units, so the footprint matches the old 22 × 30 castle.

enum BK {
    static let unit = 2.0                              // world units per brick unit
    static let steps = 2                               // snap steps per brick unit
    static let depth = 11, width = 15, height = 9      // footprint and height limit, in brick units
    static var maxX: Int { depth * steps }
    static var maxY: Int { height * steps }
    static var maxZ: Int { width * steps }
    static let maxBricks = 260
    static let budget = 3600, minimum = 900            // coins
    static let maxDecoys = 2
    /// World size of one snap step.
    static var step: Double { unit / Double(steps) }
}

enum BrickMaterial: Int, CaseIterable, Identifiable {
    case wood = 0, stone, ice, iron, heart, decoy
    var id: Int { rawValue }

    /// Mass per brick unit of volume.
    var density: Double { [0.6, 2.4, 0.9, 3.2, 9.0, 9.0][rawValue] }
    /// Collision impulse (per unit of the brick's mass) that breaks one hit point.
    var breakImpulse: Double { [7.0, 14.0, 3.5, 16.0, 9.0, 9.0][rawValue] }
    /// Hits it survives; iron cracks on the first and breaks on the second.
    var hp: Int { self == .iron ? 2 : 1 }
    /// Coins per brick unit of volume.
    var cost: Double { [6, 9, 7, 15, 0, 25][rawValue] }
    var isCrystal: Bool { self == .heart || self == .decoy }
    /// Materials a player can pick in the builder tray (hearts and decoys are their own tools).
    static let buildable: [BrickMaterial] = [.wood, .stone, .ice, .iron]
}

enum BrickShape: Int, CaseIterable, Identifiable {
    case cube = 0, half, beam2, beam3, beam4, plank, pillar2, pillar3, wedge, arch, coneRoof, pyramidRoof, battlement, window, moat
    var id: Int { rawValue }

    /// Size in snap steps at rotation 0: (along x, along y, along z).
    var size: (x: Int, y: Int, z: Int) {
        switch self {
        case .cube: return (2, 2, 2)
        case .half: return (2, 1, 2)
        case .beam2: return (2, 2, 4)
        case .beam3: return (2, 2, 6)
        case .beam4: return (2, 2, 8)
        case .plank: return (2, 1, 6)
        case .pillar2: return (2, 4, 2)
        case .pillar3: return (2, 6, 2)
        case .wedge: return (2, 2, 2)
        case .arch: return (2, 4, 6)
        case .coneRoof: return (4, 4, 4)
        case .pyramidRoof: return (4, 3, 4)
        case .battlement: return (2, 2, 2)
        case .window: return (2, 2, 2)
        case .moat: return (2, 0, 2)
        }
    }
    /// Share of the bounding box that is solid; scales mass and cost.
    var fill: Double {
        switch self {
        case .wedge: return 0.5
        case .arch: return 0.6
        case .coneRoof: return 0.3
        case .pyramidRoof: return 0.34
        case .battlement: return 0.7
        case .window: return 0.75
        case .moat: return 0
        default: return 1
        }
    }
    /// A moat is a ground decal: no body, nothing can stand on it, shots landing in it splash.
    var isDecal: Bool { self == .moat }
    /// Roofs and battlements are tops: nothing may be placed on them.
    var isTop: Bool { self == .coneRoof || self == .pyramidRoof || self == .battlement }
    var materials: [BrickMaterial] {
        switch self {
        case .moat: return []
        case .coneRoof, .pyramidRoof: return [.wood, .stone, .ice]
        default: return BrickMaterial.buildable
        }
    }
}

struct PlacedBrick: Hashable {
    var shape: BrickShape
    var material: BrickMaterial
    var x: Int, y: Int, z: Int     // minimum corner, snap steps
    var rot: Int = 0               // quarter turns about y; odd turns swap the x and z sizes

    /// Extent in snap steps after rotation.
    var extent: (x: Int, y: Int, z: Int) {
        let s = shape.size
        return rot % 2 == 0 ? s : (s.z, s.y, s.x)
    }
    /// Volume in brick units.
    var volume: Double {
        let e = shape.size, n = Double(BK.steps)
        return Double(e.x) * Double(e.y) * Double(e.z) / (n * n * n) * shape.fill
    }
    var mass: Double { max(volume, 0.05) * material.density }
    var cost: Int { shape.isDecal ? 30 : Int((volume * material.cost).rounded()) }

    /// Castle-local centre in world units (origin at the back-left ground corner).
    var center: Vec3 {
        let e = extent, s = BK.step
        return Vec3(x: (Double(x) + Double(e.x) / 2) * s, y: (Double(y) + Double(e.y) / 2) * s, z: (Double(z) + Double(e.z) / 2) * s)
    }

    func overlaps(_ o: PlacedBrick) -> Bool {
        if shape.isDecal || o.shape.isDecal { return shape.isDecal && o.shape.isDecal && x == o.x && z == o.z }
        let a = extent, b = o.extent
        return x < o.x + b.x && o.x < x + a.x && y < o.y + b.y && o.y < y + a.y && z < o.z + b.z && o.z < z + a.z
    }
    var inBounds: Bool {
        let e = extent
        return x >= 0 && y >= 0 && z >= 0 && x + e.x <= BK.maxX && y + e.y <= BK.maxY && z + e.z <= BK.maxZ
    }
    /// Does this brick's top face touch the underside of `o` with some footprint overlap?
    func supports(_ o: PlacedBrick) -> Bool {
        guard !shape.isDecal, !shape.isTop, y + extent.y == o.y else { return false }
        let a = extent, b = o.extent
        return x < o.x + b.x && o.x < x + a.x && z < o.z + b.z && o.z < z + a.z
    }
}

enum BrickProblem: Equatable {
    case overlap, outOfBounds, floating, noHeart, manyHearts, manyDecoys, overBudget, tooSmall, tooMany
}

/// A castle as its owner built it. Every castle guards exactly one heart crystal.
struct BrickDesign: Equatable {
    var bricks: [PlacedBrick] = []
    var heart = HeartKind.crystal

    var cost: Int { bricks.reduce(heart.cost) { $0 + $1.cost } }
    var hearts: Int { bricks.filter { $0.material == .heart }.count }
    var decoys: Int { bricks.filter { $0.material == .decoy }.count }

    /// Indices of bricks with nothing under them (the ground counts as support).
    var floating: [Int] {
        bricks.indices.filter { i in
            let b = bricks[i]
            return b.y > 0 && !b.shape.isDecal && !bricks.contains { $0.supports(b) }
        }
    }

    func fits(_ b: PlacedBrick) -> Bool { b.inBounds && !bricks.contains { $0.overlaps(b) } }

    var problem: BrickProblem? {
        if bricks.contains(where: { !$0.inBounds }) { return .outOfBounds }
        for i in bricks.indices { for j in bricks.indices where j > i && bricks[i].overlaps(bricks[j]) { return .overlap } }
        if !floating.isEmpty { return .floating }
        if hearts == 0 { return .noHeart }
        if hearts > 1 { return .manyHearts }
        if decoys > BK.maxDecoys { return .manyDecoys }
        if bricks.count > BK.maxBricks { return .tooMany }
        if cost > BK.budget { return .overBudget }
        if cost < BK.minimum { return .tooSmall }
        return nil
    }

    /// Flat form for saving and sending: format, heart, then six numbers per brick.
    static let format = 2
    var encoded: [Int] {
        var out = [BrickDesign.format, heart.rawValue]
        for b in bricks { out += [b.shape.rawValue, b.material.rawValue, b.x, b.y, b.z, b.rot] }
        return out
    }
    /// Reads the flat form. Returns nil unless it is a playable castle.
    init?(encoded e: [Int]) {
        guard e.count >= 2, e[0] == BrickDesign.format, (e.count - 2) % 6 == 0, let h = HeartKind(rawValue: e[1]) else { return nil }
        heart = h
        for i in stride(from: 2, to: e.count, by: 6) {
            guard let s = BrickShape(rawValue: e[i]), let m = BrickMaterial(rawValue: e[i + 1]) else { return nil }
            bricks.append(PlacedBrick(shape: s, material: m, x: e[i + 2], y: e[i + 3], z: e[i + 4], rot: e[i + 5] & 3))
        }
        guard problem == nil else { return nil }
    }
    init(bricks: [PlacedBrick] = [], heart: HeartKind = .crystal) { self.bricks = bricks; self.heart = heart }
}

// MARK: - Match state shared by the rules, the physics world and the network

/// Where one brick ended up, castle-local (same frame as `PlacedBrick.center`, world units).
struct BrickPose: Equatable {
    var p: SIMD3<Float>
    var q: SIMD4<Float>            // rotation quaternion (x, y, z, w)
    var hp: Int8                   // hit points left; 0 = broken and gone
    var broken: Bool { hp <= 0 }
}

/// Every brick of one castle after a shot has settled, in design order.
struct CastleSnapshot: Equatable {
    var poses: [BrickPose]

    /// The castle as built: every brick at home, full health.
    init(design: BrickDesign) {
        poses = design.bricks.map { b in
            let c = b.center
            let a = Float(b.rot) * .pi / 2
            return BrickPose(p: SIMD3(Float(c.x), Float(c.y), Float(c.z)), q: SIMD4(0, sin(a / 2), 0, cos(a / 2)), hp: Int8(design.hp(b)))
        }
    }
    init(poses: [BrickPose]) { self.poses = poses }

    /// Compact binary of the bricks that differ from `old`: id u16, position int16×3 in
    /// centimetres, rotation as the three smallest quaternion parts int16×3 plus a byte holding
    /// the dropped index and hp. 15 bytes per changed brick.
    func delta(from old: CastleSnapshot) -> Data {
        var d = Data()
        func u16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        func i16(_ v: Float, _ scale: Float) { u16(UInt16(bitPattern: Int16(clamping: Int((v * scale).rounded())))) }
        for (i, n) in poses.enumerated() where i >= old.poses.count || old.poses[i] != n {
            u16(UInt16(i))
            i16(n.p.x, 100); i16(n.p.y, 100); i16(n.p.z, 100)
            var q = n.q
            let comps = [q.x, q.y, q.z, q.w].map(abs)
            let drop = comps.firstIndex(of: comps.max()!)!
            if q[drop] < 0 { q = -q }
            for k in 0..<4 where k != drop { i16(q[k], 32767) }
            d.append(UInt8(drop) | UInt8(clamping: max(0, Int(n.hp))) << 2)
        }
        return d
    }

    /// Applies a `delta` to this snapshot. Returns nil if the data is malformed.
    func applying(_ d: Data) -> CastleSnapshot? {
        guard d.count % 15 == 0 else { return nil }
        var out = self
        let b = [UInt8](d)
        func u16(_ at: Int) -> UInt16 { UInt16(b[at]) | UInt16(b[at + 1]) << 8 }
        func f(_ at: Int, _ scale: Float) -> Float { Float(Int16(bitPattern: u16(at))) / scale }
        for at in stride(from: 0, to: b.count, by: 15) {
            let i = Int(u16(at))
            guard i < out.poses.count else { return nil }
            let p = SIMD3(f(at + 2, 100), f(at + 4, 100), f(at + 6, 100))
            let drop = Int(b[at + 14] & 3)
            var parts = [f(at + 8, 32767), f(at + 10, 32767), f(at + 12, 32767)]
            let w = (max(0, 1 - parts.reduce(0) { $0 + $1 * $1 })).squareRoot()
            parts.insert(w, at: drop)
            out.poses[i] = BrickPose(p: p, q: SIMD4(parts[0], parts[1], parts[2], parts[3]), hp: Int8(b[at + 14] >> 2))
        }
        return out
    }
}

/// What a cannonball does on first contact; handed from the rules to the physics world.
struct ShotImpact {
    var point: Vec3                // world position where the ball first touches something
    var velocity: Vec3             // ball velocity at that moment
    var ammo: Ammo
    var mega: Bool
    var crit: Bool
    var shielded: [Bool]           // per castle: incoming impulses are scaled by K.shieldFactor
    var extraBalls: [(point: Vec3, velocity: Vec3)] = []   // cluster shot: the other two balls
    var weight = 1.0               // match twist on the ball's mass (`MatchRules.blastScale`)
}

/// The settled result of one shot, produced by the physics world on the shooter's device and
/// sent to everyone else as-is.
struct SettleReport {
    var snapshots: [CastleSnapshot]          // per castle, after settling
}

/// The physics world as the rules and the controller see it. Implemented by `World`.
protocol BrickPhysics: AnyObject {
    /// Builds every castle's bricks as physics bodies, at the given poses (home if nil).
    func loadCastles(_ designs: [BrickDesign], poses: [CastleSnapshot]?)
    /// Plays one impact through real physics and calls back once every body sleeps or after
    /// `timeout` seconds of simulated time.
    func simulate(_ impact: ShotImpact, timeout: Double, done: @escaping (SettleReport) -> Void)
    /// Moves bricks to authoritative poses, blending over `blend` seconds (0 = snap).
    func adopt(_ snapshots: [CastleSnapshot], blend: Double)
    /// Builder: drop the preview castle under gravity, then put it back after `seconds`.
    func testGravity(seconds: Double)
}

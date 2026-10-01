import Foundation

// Game rules with no rendering: castle layout, ballistics, damage and the computer player.
// Everything that decides an outcome lives here so both players of an online match
// compute identical results from the same numbers.

enum K {
    static let gw = 22, gd = 30, gh = 20          // castle grid: depth, width, layers
    static let lh = 1.2                            // layer height
    static let grav = 12.0, dt = 1.0 / 120.0
    static let ballR = 0.7, blastR = 5.6
    static let vMin = 20.0, vMax = 42.0, pitch = 32.0
    static let wind = 1.4, lose = 0.2
    static let front = 40.0                        // |x| of each castle's front face
    static let xEdge = front + Double(gw)          // |x| of the back face
    static let river = 8.0
    static let platX = 31.0, platHalf = 3.0, platTop = 2.4
    static let pivotY = platTop + 1.25, muzzle = 2.6
    static let maxYaw = 35.0
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
    let mat: UInt8      // 1 stone, 2 team colour, 3 trim
    var alive = true
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
}

enum HitKind { case out, water, ground, castle }

struct ShotResult {
    var steps: Int
    var pos: Vec3
    var vel: Vec3
    var kind: HitKind
    var side: Int
    var center: Vec3
}

@inline(__always) func cellIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * K.gw + x) * K.gd + z }

// MARK: - Castle layout

private struct Plan {
    var vox = [UInt8](repeating: 0, count: K.cells)
    var hint = [UInt8](repeating: 0, count: K.cells)
    var decor: [DecorSpec] = []

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
    mutating func tower(_ x0: Int, _ z0: Int, _ h: Int) {
        ring(x0, x0 + 4, 0, h - 1, z0, z0 + 4, 1)
        let mid = (h / 2) & ~1
        box(x0, x0 + 4, mid, mid, z0, z0 + 4, 3)
        for y in [h - 3, h - 2] {                       // arrow slits
            set(x0 + 2, y, z0, 0); set(x0 + 2, y, z0 + 4, 0); set(x0, y, z0 + 2, 0); set(x0 + 4, y, z0 + 2, 0)
        }
        box(x0, x0 + 4, h, h, z0, z0 + 4, 3)
        crenel(x0, x0 + 4, h + 1, z0, z0 + 4, 1)
        box(x0 + 1, x0 + 3, h + 1, h + 1, z0 + 1, z0 + 3, 2)
        decor.append(DecorSpec(x: Double(x0) + 2.5, y: Double(h + 2), z: Double(z0) + 2.5, w: 2.25, d: 2.25, ht: 3.8, flag: false,
                               cells: [[x0 + 1, h + 1, z0 + 1], [x0 + 3, h + 1, z0 + 3], [x0 + 1, h + 1, z0 + 3], [x0 + 3, h + 1, z0 + 1], [x0 + 2, h + 1, z0 + 2]]))
    }
}

private func designCastle(seed: UInt32) -> Plan {
    var rnd = Mulberry32(seed ^ 0x5bd1_e995)
    var p = Plan()
    let hF = 10 + (rnd.next() < 0.5 ? 0 : 1), hB = 13 + (rnd.next() < 0.5 ? 0 : 1)
    p.tower(0, 0, hB); p.tower(0, 25, hB); p.tower(17, 0, hF); p.tower(17, 25, hF)

    // Curtain walls, two cells thick: the outer row carries a team-colour course and battlements,
    // the inner row stops one layer lower to form a walkway.
    let wh = 7
    p.box(1, 1, 0, wh - 2, 5, 24, 1);  p.box(1, 1, wh - 1, wh - 1, 5, 24, 2);  p.box(2, 2, 0, wh - 2, 5, 24, 1)
    p.box(20, 20, 0, wh - 2, 5, 24, 1); p.box(20, 20, wh - 1, wh - 1, 5, 24, 2); p.box(19, 19, 0, wh - 2, 5, 24, 1)
    p.box(5, 16, 0, wh - 2, 1, 1, 1);  p.box(5, 16, wh - 1, wh - 1, 1, 1, 2);  p.box(5, 16, 0, wh - 2, 2, 2, 1)
    p.box(5, 16, 0, wh - 2, 28, 28, 1); p.box(5, 16, wh - 1, wh - 1, 28, 28, 2); p.box(5, 16, 0, wh - 2, 27, 27, 1)
    for z in stride(from: 5, through: 24, by: 2) { p.set(1, wh, z, 1); p.set(20, wh, z, 1) }
    for x in stride(from: 5, through: 16, by: 2) { p.set(x, wh, 1, 1); p.set(x, wh, 28, 1) }
    p.box(19, 20, 0, 3, 13, 16, 0)                       // gate

    // Keep with an interior wall, three floors and a turret.
    p.ring(6, 14, 0, 11, 9, 20, 1)
    p.box(10, 10, 0, 11, 10, 19, 1)
    for l in [4, 8, 12] { p.box(6, 14, l, l, 9, 20, 3, 1) }
    p.crenel(6, 14, 13, 9, 20, 1)
    p.ring(8, 12, 13, 15, 12, 17, 2)
    p.box(8, 12, 16, 16, 12, 17, 3, 1)
    p.box(14, 14, 0, 2, 14, 15, 0)                       // keep door
    for y in [0, 1, 5, 6, 9, 10] { p.set(10, y, 14, 0); p.set(10, y, 15, 0) }
    for c in [[14, 6, 11], [14, 6, 18], [6, 6, 11], [6, 6, 18], [8, 6, 9], [12, 6, 20], [14, 10, 12], [14, 10, 17], [6, 10, 14], [9, 10, 9], [11, 10, 20], [14, 2, 11], [14, 2, 18]] {
        p.set(c[0], c[1], c[2], 0)
    }
    p.decor.append(DecorSpec(x: 10.5, y: 17, z: 15, w: 5.6, d: 6.6, ht: 4.6, flag: true,
                             cells: [[8, 16, 12], [12, 16, 17], [8, 16, 17], [12, 16, 12], [10, 16, 14]]))
    return p
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
    let s: Double          // +1 for the left castle, -1 for the mirrored right one
    let x0: Double
    private(set) var blocks: [Block]
    let cellBlock: [Int]
    let decor: [DecorSpec]
    let total: Int
    private(set) var aliveCells: Int

    init(side: Int, seed: UInt32) {
        self.side = side
        s = side == 0 ? 1 : -1
        x0 = side == 0 ? -K.xEdge : K.xEdge
        let plan = designCastle(seed: seed)
        let t = tile(plan)
        blocks = t.blocks
        cellBlock = t.cellBlock
        decor = plan.decor
        var sup = [Bool](repeating: false, count: t.blocks.count)
        var sum = 0
        for i in blocks.indices {
            if Castle.supported(blocks[i], sup, cellBlock) { sup[i] = true; sum += blocks[i].len } else { blocks[i].alive = false }
        }
        total = sum
        aliveCells = sum
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

    func center(of b: Block) -> Vec3 {
        let lx = Double(b.x) + (b.dir == 1 ? Double(b.len) / 2 : 0.5)
        let lz = Double(b.z) + (b.dir == 2 ? Double(b.len) / 2 : 0.5)
        return Vec3(x: x0 + s * lx, y: (Double(b.y) + 0.5) * K.lh, z: lz - Double(K.gd) / 2)
    }

    func worldPoint(gx: Double, gy: Double, gz: Double) -> Vec3 {
        Vec3(x: x0 + s * gx, y: gy * K.lh, z: gz - Double(K.gd) / 2)
    }

    func hit(_ px: Double, _ py: Double, _ pz: Double) -> Bool {
        let r = K.ballR, lx = s * (px - x0), lz = pz + Double(K.gd) / 2
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
    func damage(at c: Vec3) -> Damage {
        var out = Damage()
        let R = K.blastR, lx = s * (c.x - x0), lz = c.z + Double(K.gd) / 2
        if lx < -R || lx > Double(K.gw) + R || lz < -R || lz > Double(K.gd) + R { return out }
        var dead = [Bool](repeating: false, count: blocks.count)
        let r2 = R * R
        for b in blocks where b.alive {
            for i in 0..<b.len {
                let dx = Double(b.x + (b.dir == 1 ? i : 0)) + 0.5 - lx
                let dy = (Double(b.y) + 0.5) * K.lh - c.y
                let dz = Double(b.z + (b.dir == 2 ? i : 0)) + 0.5 - lz
                if dx * dx + dy * dy + dz * dz <= r2 { dead[b.id] = true; out.blast.append(b.id); out.cells += b.len; break }
            }
        }
        if out.blast.isEmpty { return out }
        var sup = [Bool](repeating: false, count: blocks.count)
        for b in blocks where b.alive && !dead[b.id] {
            if Castle.supported(b, sup, cellBlock) { sup[b.id] = true } else { out.fall.append(b.id); out.cells += b.len }
        }
        return out
    }

    func kill(_ d: Damage) {
        for id in d.blast { blocks[id].alive = false }
        for id in d.fall { blocks[id].alive = false }
        aliveCells -= d.cells
    }
}

// MARK: - Battle

final class Battle {
    let seed: UInt32
    let first: Int
    var shot = 0
    let castles: [Castle]

    init(seed: UInt32, first: Int) {
        self.seed = seed
        self.first = first
        castles = [Castle(side: 0, seed: seed), Castle(side: 1, seed: seed)]
    }

    var turn: Int { (first + shot) % 2 }

    func wind() -> (x: Double, z: Double) {
        var r = Mulberry32(seed ^ (UInt32(truncatingIfNeeded: shot + 1) &* 0x9E37_79B1))
        _ = r.next()
        let wx = (r.next() * 2 - 1) * K.wind
        let wz = (r.next() * 2 - 1) * K.wind
        return (wx, wz)
    }

    /// Fixed-step flight. Uses only additions, multiplications and one square root, so two devices
    /// fed the same launch position and velocity agree on the result.
    func simulate(p0: Vec3, v0: Vec3, wind w: (x: Double, z: Double)) -> ShotResult {
        var x = p0.x, y = p0.y, z = p0.z, vx = v0.x, vy = v0.y, vz = v0.z
        var kind = HitKind.out, side = -1, n = 1
        let r = K.ballR
        while n <= 8000 {
            vx += w.x * K.dt; vy -= K.grav * K.dt; vz += w.z * K.dt
            x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
            if y <= r { y = r; kind = (x > -K.river && x < K.river) ? .water : .ground; break }
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
        var c = Vec3(x: x, y: y, z: z)
        if kind == .castle {
            let sp = (vx * vx + vy * vy + vz * vz).squareRoot()
            c = Vec3(x: x + vx / sp * 1.2, y: y + vy / sp * 1.2, z: z + vz / sp * 1.2)
        }
        return ShotResult(steps: n, pos: Vec3(x: x, y: y, z: z), vel: Vec3(x: vx, y: vy, z: vz), kind: kind, side: side, center: c)
    }

    func trace(p0: Vec3, v0: Vec3, wind w: (x: Double, z: Double), steps: Int) -> [Vec3] {
        var out = [Vec3]()
        out.reserveCapacity(steps + 1)
        var x = p0.x, y = p0.y, z = p0.z, vx = v0.x, vy = v0.y, vz = v0.z
        out.append(p0)
        for _ in 0..<steps {
            vx += w.x * K.dt; vy -= K.grav * K.dt; vz += w.z * K.dt
            x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
            out.append(Vec3(x: x, y: y, z: z))
        }
        return out
    }

    func apply(_ res: ShotResult) -> [Damage] {
        castles.map { c in
            guard res.kind == .castle || res.kind == .ground else { return Damage() }
            let d = c.damage(at: res.center)
            c.kill(d)
            return d
        }
    }

    func loser() -> Int? { castles.firstIndex { $0.pct < K.lose } }
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
    var title: String { self == .kolay ? "Kolay" : self == .orta ? "Orta" : "Zor" }
    var samples: Int { self == .kolay ? 1 : self == .orta ? 3 : 12 }
    var yawNoise: Double { self == .kolay ? 5.0 : self == .orta ? 2.2 : 0.7 }
    var speedNoise: Double { self == .kolay ? 0.075 : self == .orta ? 0.035 : 0.012 }
}

enum Computer {
    private static func gauss() -> Double { (Double.random(in: 0...1) + Double.random(in: 0...1) + Double.random(in: 0...1) - 1.5) * 1.15 }

    private static func solve(side: Int, target t: Vec3, wind w: (x: Double, z: Double)) -> (yaw: Double, v: Double)? {
        let pv = Ballistics.pivot(side), sg: Double = side == 0 ? 1 : -1
        let dx = (t.x - pv.x) * sg, dz = (t.z - pv.z) * sg, d = (dx * dx + dz * dz).squareRoot()
        let yawT = atan2(dz, dx), pit = K.pitch * .pi / 180
        let den = 2 * cos(pit) * cos(pit) * (d * tan(pit) - (t.y - pv.y))
        if den <= 0 { return nil }
        var v = (K.grav * d * d / den).squareRoot(), yaw = yawT
        for _ in 0..<10 {
            let m = Ballistics.muzzle(side: side, yaw: yaw * 180 / .pi)
            var x = m.p0.x, y = m.p0.y, z = m.p0.z, vx = m.d.x * v, vy = m.d.y * v, vz = m.d.z * v
            for _ in 0..<6000 {
                vx += w.x * K.dt; vy -= K.grav * K.dt; vz += w.z * K.dt
                x += vx * K.dt; y += vy * K.dt; z += vz * K.dt
                if (vy < 0 && y <= t.y) || y <= 0 { break }
            }
            let lx = (x - pv.x) * sg, lz = (z - pv.z) * sg, dl = max(1, (lx * lx + lz * lz).squareRoot())
            yaw += yawT - atan2(lz, lx)
            v *= (d / dl).squareRoot()
        }
        return (yaw * 180 / .pi, v)
    }

    static func choose(battle: Battle, side: Int, difficulty: Difficulty, wind w: (x: Double, z: Double)) -> Aim {
        let enemy = battle.castles[1 - side]
        let alive = enemy.blocks.filter { $0.alive }
        guard !alive.isEmpty else { return Aim() }
        var best = enemy.center(of: alive[0]), bestScore = -1
        for _ in 0..<difficulty.samples {
            let c = enemy.center(of: alive.randomElement()!)
            let score = enemy.damage(at: c).cells
            if score > bestScore { bestScore = score; best = c }
        }
        let sol = solve(side: side, target: best, wind: w) ?? (yaw: 0, v: 32)
        let v = sol.v * (1 + gauss() * difficulty.speedNoise)
        let yaw = sol.yaw + gauss() * difficulty.yawNoise
        return Aim(yaw: min(max(yaw, -K.maxYaw), K.maxYaw), power: min(max((v - K.vMin) / (K.vMax - K.vMin) * 100, 0), 100))
    }
}

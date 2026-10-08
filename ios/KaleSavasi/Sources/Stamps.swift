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
        case .gatehouse: return (4, 8)
        case .shrine: return (6, 6)
        case .bridge: return (2, 8)
        }
    }

    /// The stamp's bricks with its minimum corner on the ground at (x, z), turned `rot` quarter
    /// turns, built mainly in `material`.
    /// Placeholder: a plain stack. The physics workstream replaces it with detailed designs.
    func bricks(x: Int, z: Int, rot: Int = 0, material: BrickMaterial = .stone) -> [PlacedBrick] {
        let f = footprint
        let (fx, fz) = rot % 2 == 0 ? (f.x, f.z) : (f.z, f.x)
        var out: [PlacedBrick] = []
        for xx in stride(from: 0, to: fx, by: 2) {
            for zz in stride(from: 0, to: fz, by: 2) {
                out.append(PlacedBrick(shape: .cube, material: material, x: x + xx, y: 0, z: z + zz))
            }
        }
        return out
    }
}

extension BrickDesign {
    /// A castle saved before bricks existed, rebuilt from stamps.
    /// Placeholder: the physics workstream maps every piece kind properly.
    init(legacy: CastleDesign) {
        self.init(heart: legacy.heart)
        for p in legacy.pieces {
            let x = p.tx * 2, z = p.tz * 2
            switch p.kind {
            case .heart: bricks.append(PlacedBrick(shape: .cube, material: .heart, x: x, y: 0, z: z))
            case .decoy: bricks.append(PlacedBrick(shape: .cube, material: .decoy, x: x, y: 0, z: z))
            case .moat: bricks.append(PlacedBrick(shape: .moat, material: .stone, x: x, y: 0, z: z))
            default: bricks += Stamp.wall.bricks(x: x, z: z).filter { b in !bricks.contains { $0.overlaps(b) } && b.inBounds }
            }
        }
    }
}

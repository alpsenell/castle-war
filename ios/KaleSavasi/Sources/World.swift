import SceneKit
import UIKit

// The SceneKit side of the game: terrain, castles, cannons, the ball, rubble and effects.
// It only draws what the rules decide; nothing here affects an outcome.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

extension Vec3 {
    var f: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
}

/// Materials. Everything is physically based and lit by the sky, so stone, slate, wood and
/// iron pick up the same light.
enum Look {
    static let stone: [[UInt32]] = [[0xb9bcbd, 0xa4a8ab, 0xcdcfce], [0xdcc9a0, 0xc9b488, 0xe9dcbd],
                                    [0xaab5a2, 0x96a28d, 0xc1cab9], [0xd6c7b4, 0xc2b19b, 0xe6dacb]]
    static let accent: [UInt32] = [0xb5301f, 0x2459b8, 0x2f8f3e, 0xd9a514]
    static let trim: [UInt32] = [0x7b8085, 0xa08f6b, 0x6f7f6a, 0x9c8a5e]
    static let ink: UInt32 = 0x1b2a34

    private static var tinted: [String: UIImage] = [:]

    /// A grey-scale texture with a colour multiplied in, cached per colour.
    private static func tint(_ base: UIImage, _ key: String, _ hex: UInt32) -> UIImage {
        let k = "\(key)-\(hex)"
        if let hit = tinted[k] { return hit }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: base.size, format: format).image { ctx in
            base.draw(at: .zero)
            UIColor(hex: hex).setFill()
            ctx.fill(CGRect(origin: .zero, size: base.size), blendMode: .multiply)
        }
        tinted[k] = img
        return img
    }

    private static func textured(_ albedo: UIImage, normal: UIImage?, roughness: CGFloat, metal: CGFloat = 0, bump: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = albedo
        m.roughness.contents = roughness
        m.metalness.contents = metal
        for p in [m.diffuse, m.normal] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 8 }
        if let normal { m.normal.contents = normal; m.normal.intensity = bump }
        return m
    }

    static func stoneMaterial(_ hex: UInt32) -> SCNMaterial {
        textured(tint(Textures.stone.albedo, "stone", hex), normal: Textures.stone.normal, roughness: 0.92, bump: 0.9)
    }

    static func roofMaterial(_ hex: UInt32) -> SCNMaterial {
        let m = textured(tint(Textures.roof.albedo, "roof", hex), normal: Textures.roof.normal, roughness: 0.6, bump: 1.2)
        for p in [m.diffuse, m.normal] { p.contentsTransform = SCNMatrix4MakeScale(2, 2, 1) }
        return m
    }

    static func wood() -> SCNMaterial { textured(tint(Textures.wood, "wood", 0x8a5a33), normal: nil, roughness: 0.75) }

    /// Plain painted or metal surface.
    static func solid(_ hex: UInt32, roughness: CGFloat = 0.6, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(hex: hex)
        m.roughness.contents = roughness
        m.metalness.contents = metal
        return m
    }

    static func unlit(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        return m
    }

    static let heartGlow: UInt32 = 0xff2f7d

    /// Crystal and glow colours of each heart type. Decoys copy the castle's own, so they still pass for the heart.
    static func heartColors(_ h: HeartKind) -> (body: UInt32, glow: UInt32) {
        switch h {
        case .crystal: return (0xc2185b, heartGlow)
        case .living: return (0x1f9d55, 0x5dff9a)
        case .aegis: return (0x1f6fc2, 0x6fd0ff)
        case .titan: return (0xb8690f, 0xffb43a)
        }
    }

    /// Glowing crystal for the heart, pulsing slowly.
    static func heartMaterial(_ h: HeartKind = .crystal) -> SCNMaterial {
        let c = heartColors(h)
        let m = solid(c.body, roughness: 0.18, metal: 0.2)
        m.emission.contents = UIColor(hex: c.glow)
        m.emission.intensity = 0.7
        let pulse = CABasicAnimation(keyPath: "intensity")
        pulse.fromValue = 0.45
        pulse.toValue = 1.1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        m.emission.addAnimation(pulse, forKey: "pulse")
        return m
    }

    /// Dark stone with iron bands, for walls that take two blasts.
    static func ironMaterial(cracked: Bool) -> SCNMaterial {
        let m = stoneMaterial(cracked ? 0x3d4146 : 0x5d646b)
        m.metalness.contents = cracked ? 0.1 : 0.35
        m.roughness.contents = cracked ? 0.95 : 0.7
        return m
    }

    static let moatWater: SCNMaterial = {
        let m = Look.solid(0x1f5a7d, roughness: 0.08, metal: 0.55)
        m.normal.contents = Textures.waterNormal
        m.normal.intensity = 0.5
        return m
    }()

    /// A castle's mesh materials: three stone shades, team colour, trim, heart (decoys use it too),
    /// iron, cracked iron, and the dull crystal of a decoy that has been found out.
    static func castleMaterials(_ side: Int, heart: HeartKind = .crystal) -> [SCNMaterial] {
        stone[side].map(stoneMaterial) + [stoneMaterial(accent[side]), stoneMaterial(trim[side]), heartMaterial(heart),
                                          ironMaterial(cracked: false), ironMaterial(cracked: true), solid(0x77707c, roughness: 0.55)]
    }
}

/// Collects boxes into one geometry with an element per material. Texture coordinates follow
/// world position, so the stone runs unbroken from block to block.
struct MeshBuilder {
    private var pos: [SCNVector3] = []
    private var nor: [SCNVector3] = []
    private var uv: [CGPoint] = []
    private var tan: [SIMD4<Float>] = []
    private var idx: [[Int32]]

    init(materials: Int) { idx = Array(repeating: [], count: materials) }

    /// A box whose edges and corners are cut at 45°. Each bevel takes its normals from the two faces
    /// it joins, so the light rolls over it like a worn, rounded stone.
    mutating func addBox(center c: SIMD3<Float>, size: SIMD3<Float>, material: Int, bevel: Float = 0, texel: Float = 0.3) {
        let h = size / 2
        let b = min(bevel, min(h.x, min(h.y, h.z)) * 0.45)
        let e = h - b
        // normal, tangent u, bitangent v with u × v = normal
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
        ]
        func key(_ f: Int, _ s: SIMD3<Float>) -> Int { f * 8 + (s.x > 0 ? 1 : 0) + (s.y > 0 ? 2 : 0) + (s.z > 0 ? 4 : 0) }
        func faceOf(_ n: SIMD3<Float>) -> Int { n.x != 0 ? (n.x > 0 ? 0 : 1) : n.y != 0 ? (n.y > 0 ? 2 : 3) : (n.z > 0 ? 4 : 5) }
        var vid: [Int: Int32] = [:]
        var at: [Int32: SIMD3<Float>] = [:]
        for (f, (n, u, v)) in faces.enumerated() {
            for s in [n - u - v, n + u - v, n + u + v, n - u + v] {
                let p = c + s * e + n * b
                let i = Int32(pos.count)
                pos.append(SCNVector3(p.x, p.y, p.z))
                nor.append(SCNVector3(n.x, n.y, n.z))
                uv.append(CGPoint(x: CGFloat(simd_dot(p, u) * texel), y: CGFloat(simd_dot(p, v) * texel)))
                tan.append(SIMD4(u.x, u.y, u.z, 1))
                vid[key(f, s)] = i
                at[i] = p
            }
        }
        func tri(_ a: Int32, _ b: Int32, _ d: Int32) {
            guard let pa = at[a], let pb = at[b], let pd = at[d] else { return }
            let out = simd_dot(simd_cross(pb - pa, pd - pa), (pa + pb + pd) / 3 - c)
            idx[material].append(contentsOf: out >= 0 ? [a, b, d] : [a, d, b])
        }
        for (f, (n, u, v)) in faces.enumerated() {
            let q = [n - u - v, n + u - v, n + u + v, n - u + v].map { vid[key(f, $0)]! }
            tri(q[0], q[1], q[2]); tri(q[0], q[2], q[3])
        }
        guard b > 0 else { return }
        for i in 0..<6 { for j in (i + 1)..<6 {
            let na = faces[i].0, nb = faces[j].0
            if simd_dot(na, nb) != 0 { continue }
            let t = simd_cross(na, nb)
            let a1 = vid[key(i, na + nb + t)]!, a2 = vid[key(i, na + nb - t)]!
            let b1 = vid[key(j, na + nb + t)]!, b2 = vid[key(j, na + nb - t)]!
            tri(a1, a2, b2); tri(a1, b2, b1)
        } }
        for sx in [Float(-1), 1] { for sy in [Float(-1), 1] { for sz in [Float(-1), 1] {
            let s = SIMD3(sx, sy, sz)
            tri(vid[key(faceOf(SIMD3(sx, 0, 0)), s)]!, vid[key(faceOf(SIMD3(0, sy, 0)), s)]!, vid[key(faceOf(SIMD3(0, 0, sz)), s)]!)
        } } }
    }

    func geometry(materials: [SCNMaterial]) -> SCNGeometry {
        var elements: [SCNGeometryElement] = [], mats: [SCNMaterial] = []
        for (i, list) in idx.enumerated() where !list.isEmpty {
            elements.append(SCNGeometryElement(indices: list, primitiveType: .triangles))
            mats.append(materials[i])
        }
        let tanData = tan.withUnsafeBufferPointer { Data(buffer: $0) }
        let tangents = SCNGeometrySource(data: tanData, semantic: .tangent, vectorCount: tan.count, usesFloatComponents: true,
                                         componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor), SCNGeometrySource(textureCoordinates: uv), tangents], elements: elements)
        g.materials = mats
        return g
    }
}

private enum Phys {
    static let fixed = 1, loose = 2
    private static var shapes: [Int: SCNPhysicsShape] = [:]
    static func blockShape(_ len: Int) -> SCNPhysicsShape {
        if let s = shapes[len] { return s }
        let s = SCNPhysicsShape(geometry: SCNBox(width: CGFloat(len) - 0.08, height: CGFloat(K.lh) - 0.08, length: 0.92, chamferRadius: 0), options: nil)
        shapes[len] = s
        return s
    }
}

final class CastleView {
    let castle: Castle
    let meshNode = SCNNode()
    let root = SCNNode()
    private let materials: [SCNMaterial]
    private var colorOf: [Int]
    private var fixedBodies: [Int: SCNNode] = [:]
    fileprivate var decor: [(node: SCNNode, ids: [Int], alive: Bool)] = []
    private var looseGeo: [Int: SCNGeometry] = [:]
    private let physics: Bool
    /// The mortar joint: each block is drawn this much smaller so a seam shows between stones.
    private let joint: Float = 0.03
    /// How far each stone's edges are rounded off.
    private let bevel: Float = 0.11
    /// The floating gems above the heart (decoy nil) and each decoy, until they break.
    private var gems: [(node: SCNNode, decoy: Int?)] = []

    /// `physics` is off for the builder preview, where nothing ever falls.
    init(castle: Castle, physics: Bool = true) {
        self.castle = castle
        self.physics = physics
        materials = Look.castleMaterials(castle.side, heart: castle.heartKind)
        var rnd = Mulberry32(UInt32(castle.side * 977 + 13))
        colorOf = castle.blocks.map { b in
            if b.mat == 2 { return 3 }
            if b.mat == 3 { return 4 }
            if b.mat == 4 || b.mat == 6 { return 5 }
            if b.mat == 5 { return 6 }
            let r = rnd.next()
            return r < 0.5 ? 0 : r < 0.8 ? 1 : 2
        }
        root.addChildNode(meshNode)
        if physics { for b in castle.blocks where b.alive { addFixedBody(b) } }
        let slate = Look.roofMaterial(Look.accent[castle.side])
        for d in castle.decor {
            let n = SCNNode()
            let roof = SCNNode(geometry: SCNPyramid(width: CGFloat(d.w * 2), height: CGFloat(d.ht), length: CGFloat(d.d * 2)))
            roof.geometry?.materials = [slate]
            n.addChildNode(roof)
            if d.flag {
                let pole = SCNNode(geometry: SCNCylinder(radius: 0.09, height: 3.4))
                pole.geometry?.materials = [Look.solid(0x3a3d40, roughness: 0.4, metal: 1)]
                pole.position = SCNVector3(0, Float(d.ht) + 1.3, 0)
                n.addChildNode(pole)
                let cloth = SCNNode(geometry: SCNBox(width: 2.2, height: 1.3, length: 0.05, chamferRadius: 0))
                cloth.geometry?.materials = [Look.solid(Look.accent[castle.side], roughness: 0.9)]
                cloth.position = SCNVector3(Float(castle.fx) * 1.15, Float(d.ht) + 2.3, Float(castle.fz) * 1.15)
                if !castle.alongWorldX { cloth.eulerAngles.y = .pi / 2 }
                n.addChildNode(cloth)
            }
            n.simdPosition = castle.worldPoint(gx: d.x, gy: d.y, gz: d.z).f
            root.addChildNode(n)
            var ids: [Int] = []
            for c in d.cells {
                let id = castle.cellBlock[cellIndex(c[0], c[1], c[2])]
                if id >= 0 && castle.blocks[id].alive && !ids.contains(id) { ids.append(id) }
            }
            decor.append((n, ids, true))
        }
        if let c = castle.heartCenter { addGem(at: c, decoy: nil) }
        for i in castle.decoyRevealed.indices where !castle.decoyRevealed[i] { if let c = castle.decoyCenter(i) { addGem(at: c, decoy: i) } }
        for m in castle.moats {
            let water = SCNNode(geometry: SCNPlane(width: 2, height: 2))
            water.geometry?.materials = [Look.moatWater]
            water.eulerAngles.x = -.pi / 2
            water.simdPosition = castle.worldPoint(gx: Double(m.x) + 1, gy: 0.06 / K.lh, gz: Double(m.z) + 1).f
            water.castsShadow = false
            root.addChildNode(water)
        }
        rebuildMesh()
    }

    private func addGem(at c: Vec3, decoy: Int?) {
        let n = SCNNode()
        n.simdPosition = c.f + SIMD3(0, 2.6, 0)
        let crystal = Look.heartMaterial(castle.heartKind)
        for flip in [false, true] {
            let half = SCNNode(geometry: SCNPyramid(width: 1.1, height: 1.0, length: 1.1))
            half.geometry?.materials = [crystal]
            if flip { half.eulerAngles.x = .pi }
            n.addChildNode(half)
        }
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(hex: Look.heartColors(castle.heartKind).glow)
        light.intensity = 900
        light.attenuationStartDistance = 1
        light.attenuationEndDistance = 9
        n.light = light
        n.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4)))
        n.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.4, z: 0, duration: 1.1), .moveBy(x: 0, y: -0.4, z: 0, duration: 1.1)])))
        root.addChildNode(n)
        gems.append((n, decoy))
    }

    /// Takes down the gem of the heart (decoy nil) or of a decoy. Returns where it was.
    fileprivate func breakGem(decoy: Int?) -> SIMD3<Float>? {
        guard let i = gems.firstIndex(where: { $0.decoy == decoy }) else { return nil }
        let n = gems.remove(at: i).node
        let p = n.presentation.simdWorldPosition
        n.removeFromParentNode()
        return p
    }

    /// The material a block shows right now: cracked iron and found-out decoys change.
    fileprivate func look(_ b: Block) -> Int {
        if b.mat == 5 && b.hp < 2 { return 7 }
        if b.mat == 6, let d = castle.decoyOf[b.id], castle.decoyRevealed[d] { return 8 }
        return colorOf[b.id]
    }

    private func addFixedBody(_ b: Block) {
        let n = SCNNode()
        n.simdPosition = castle.center(of: b).f
        if !runsAlongX(b) { n.eulerAngles.y = .pi / 2 }
        let body = SCNPhysicsBody(type: .static, shape: Phys.blockShape(b.len))
        body.categoryBitMask = Phys.fixed
        body.collisionBitMask = Phys.loose
        n.physicsBody = body
        root.addChildNode(n)
        fixedBodies[b.id] = n
    }

    func rebuildMesh() {
        var mb = MeshBuilder(materials: materials.count)
        for b in castle.blocks where b.alive {
            let c = castle.center(of: b).f
            let size: SIMD3<Float> = runsAlongX(b) ? SIMD3(Float(b.len), Float(K.lh), 1) : SIMD3(1, Float(K.lh), Float(b.len))
            mb.addBox(center: c, size: size - SIMD3(repeating: joint), material: look(b), bevel: bevel)
        }
        meshNode.geometry = mb.geometry(materials: materials)
    }

    /// Turns a block that just died into a loose physics body.
    fileprivate func release(_ id: Int) -> SCNNode {
        let b = castle.blocks[id]
        let old = fixedBodies.removeValue(forKey: id)
        old?.removeFromParentNode()
        let key = b.len * 10 + look(b)
        let geo: SCNGeometry
        if let g = looseGeo[key] { geo = g } else {
            let g = SCNBox(width: CGFloat(b.len) - 0.06, height: CGFloat(K.lh) - 0.06, length: 0.94, chamferRadius: CGFloat(bevel))
            g.chamferSegmentCount = 3
            g.materials = [materials[look(b)]]
            looseGeo[key] = g
            geo = g
        }
        let n = SCNNode(geometry: geo)
        n.simdPosition = castle.center(of: b).f
        if !runsAlongX(b) { n.eulerAngles.y = .pi / 2 }
        let body = SCNPhysicsBody(type: .dynamic, shape: Phys.blockShape(b.len))
        body.mass = CGFloat(b.len)
        body.friction = 0.8
        body.restitution = 0.12
        body.angularDamping = 0.3
        body.categoryBitMask = Phys.loose
        body.collisionBitMask = Phys.fixed | Phys.loose
        n.physicsBody = body
        return n
    }

    /// Whether a block's length lies along the world x axis; castles on the north and south seats are turned a quarter.
    private func runsAlongX(_ b: Block) -> Bool { (b.dir == 1) == castle.alongWorldX }

    /// Stands rebuilt blocks back up. Returns where they are, for the effect.
    fileprivate func restore(_ ids: [Int]) -> [SIMD3<Float>] {
        if physics { for id in ids where fixedBodies[id] == nil { addFixedBody(castle.blocks[id]) } }
        rebuildMesh()
        return ids.map { castle.center(of: castle.blocks[$0]).f }
    }
}

final class CannonView {
    let yawNode = SCNNode()
    private let barrel = SCNNode()
    var kick: Float = 0
    private let side: Int
    let root = SCNNode()

    init(side: Int, arena: Arena, scene: SCNScene) {
        self.side = side
        let pv = arena.pivot(side)
        root.position = SCNVector3(Float(pv.x), 0, Float(pv.z))
        let w = CGFloat(K.platHalf * 2)
        let base = SCNNode(geometry: SCNBox(width: w, height: 1.8, length: w, chamferRadius: 0.06))
        base.geometry?.materials = [Look.stoneMaterial(Look.trim[side])]
        base.position = SCNVector3(0, 0.9, 0)
        let top = SCNNode(geometry: SCNBox(width: w + 0.4, height: 0.6, length: w + 0.4, chamferRadius: 0.06))
        top.geometry?.materials = [Look.stoneMaterial(Look.accent[side])]
        top.position = SCNVector3(0, 2.1, 0)
        root.addChildNode(base); root.addChildNode(top)

        yawNode.position = SCNVector3(0, Float(K.platTop), 0)
        root.addChildNode(yawNode)
        let wood = Look.wood(), iron = Look.solid(0x2c2f33, roughness: 0.38, metal: 1), brass = Look.solid(0xb08d3c, roughness: 0.3, metal: 1)
        let carriage = SCNNode(geometry: SCNBox(width: 2.6, height: 0.5, length: 1.6, chamferRadius: 0.06))
        carriage.geometry?.materials = [wood]
        carriage.position = SCNVector3(0, 0.75, 0)
        yawNode.addChildNode(carriage)
        for z in [Float(-1.0), 1.0] {
            let wheel = SCNNode(geometry: SCNTube(innerRadius: 0.55, outerRadius: 0.8, height: 0.26))
            wheel.geometry?.materials = [wood]
            wheel.eulerAngles.x = .pi / 2
            wheel.position = SCNVector3(0, 0.8, z)
            yawNode.addChildNode(wheel)
            for a in 0..<4 {
                let spoke = SCNNode(geometry: SCNBox(width: 1.2, height: 0.12, length: 0.16, chamferRadius: 0))
                spoke.geometry?.materials = [wood]
                spoke.position = SCNVector3(0, 0.8, z)
                spoke.eulerAngles.z = Float(a) * .pi / 4
                yawNode.addChildNode(spoke)
            }
            let hub = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.34))
            hub.geometry?.materials = [brass]
            hub.eulerAngles.x = .pi / 2
            hub.position = SCNVector3(0, 0.8, z)
            yawNode.addChildNode(hub)
        }
        let pitchNode = SCNNode()
        pitchNode.position = SCNVector3(0, 1.25, 0)
        pitchNode.eulerAngles.z = Float(K.pitch * .pi / 180)
        yawNode.addChildNode(pitchNode)
        pitchNode.addChildNode(barrel)
        let tube = SCNNode(geometry: SCNCone(topRadius: 0.45, bottomRadius: 0.6, height: 3.3))
        tube.geometry?.materials = [iron]
        tube.eulerAngles.z = -.pi / 2
        tube.position = SCNVector3(0.8, 0, 0)
        barrel.addChildNode(tube)
        for x in [Float(-0.3), 1.0, 2.35] {
            let band = SCNNode(geometry: SCNCylinder(radius: x > 2 ? 0.6 : 0.62 - CGFloat(x) * 0.04, height: x > 2 ? 0.32 : 0.16))
            band.geometry?.materials = [x > 2 ? iron : brass]
            band.eulerAngles.z = -.pi / 2
            band.position = SCNVector3(x, 0, 0)
            barrel.addChildNode(band)
        }
        let knob = SCNNode(geometry: SCNSphere(radius: 0.5))
        knob.geometry?.materials = [iron]
        knob.position = SCNVector3(-0.9, 0, 0)
        barrel.addChildNode(knob)
        scene.rootNode.addChildNode(root)
    }

    /// Points the cannon `yaw` degrees off a heading (radians, from +x toward +z).
    func pose(heading: Double, yaw: Double, dt: Float) {
        yawNode.eulerAngles.y = -Float(heading + yaw * .pi / 180)
        kick *= exp(-7 * dt)
        barrel.position.x = -0.8 * kick
    }
}

final class World {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    private(set) var castleViews: [CastleView] = []
    private(set) var cannons: [CannonView] = []
    let ball = SCNNode(geometry: SCNSphere(radius: CGFloat(K.ballR)))
    private var dots: [SCNNode] = []
    private let targetNode = World.makeTargetNode()
    private let looseRoot = SCNNode()
    private var loose: [(node: SCNNode, born: TimeInterval, decor: Bool)] = []
    private var rubble: [SCNNode] = []
    private var pickupNode: SCNNode?
    private var pickupShown: Pickup?
    private var domes: [SCNNode] = []
    private(set) var arena = Arena.duel
    private var riverNodes: [SCNNode] = []
    private var lakeNodes: [SCNNode] = []
    private var earth: [SCNNode] = []
    private var clock: TimeInterval = 0
    private var sweep: TimeInterval = 0
    var onSplash: (() -> Void)?

    init() {
        buildSky()
        buildTerrain()
        buildScenery()
        setArena(.duel, force: true)

        ball.isHidden = true
        scene.rootNode.addChildNode(ball)

        let dotGeo = SCNSphere(radius: 0.22)
        dotGeo.segmentCount = 10
        dotGeo.materials = [Look.unlit(.white)]
        for _ in 0..<40 {
            let n = SCNNode(geometry: dotGeo)
            n.isHidden = true
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
            dots.append(n)
        }

        camera.zNear = 0.5
        camera.zFar = 1600
        camera.fieldOfView = 50
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0.45
        camera.bloomIntensity = 0.28
        camera.bloomThreshold = 0.92
        camera.bloomBlurRadius = 10
        camera.screenSpaceAmbientOcclusionIntensity = 0.75
        camera.screenSpaceAmbientOcclusionRadius = 1.6
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.vignettingPower = 0.6
        camera.vignettingIntensity = 0.3
        camera.saturation = 1.08
        camera.contrast = 0.06
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(90, 40, 90)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(looseRoot)
        scene.rootNode.addChildNode(targetNode)
        scene.physicsWorld.gravity = SCNVector3(0, -22, 0)
    }

    // MARK: Sky and light

    /// Direction to the sun, matching where it is painted in the sky panorama.
    private static let sunDirection: SIMD3<Float> = {
        let az = (Textures.sunU - 0.5) * 2 * .pi, el = Textures.sunElevation
        return simd_normalize(SIMD3(cos(el) * sin(az), sin(el), -cos(el) * cos(az)))
    }()

    private func buildSky() {
        scene.background.contents = Textures.sky
        scene.lightingEnvironment.contents = Textures.sky
        scene.lightingEnvironment.intensity = 1.5
        scene.fogColor = UIColor(hex: 0xcfe0f2)
        scene.fogStartDistance = 190
        scene.fogEndDistance = 820
        scene.fogDensityExponent = 1.4

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1500
        sun.color = UIColor(hex: 0xfff1dc)
        sun.castsShadow = true
        sun.shadowColor = UIColor(white: 0, alpha: 0.55)
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowBias = 2
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 260
        sun.shadowCascadeCount = 3
        let sn = SCNNode(); sn.light = sun
        sn.simdPosition = World.sunDirection * 120
        sn.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sn)
    }

    // MARK: Terrain

    private static let hills = Fractal(base: 5, octaves: 4, seed: 131)

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Ground height. The battlefield and the river valley are flat; hills rise around them.
    static func height(_ x: Float, _ z: Float) -> Float {
        let rise = smooth(135, 320, (x * x + z * z).squareRoot()) * smooth(28, 110, abs(x))
        if rise <= 0 { return 0 }
        return max(0, hills.value(x / 1500 + 0.5, z / 1500 + 0.5) - 0.3) * 150 * rise
    }

    private func buildTerrain() {
        let step: Float = 16, nx = 101, nz = 81
        let x0 = -Float(nx - 1) * step / 2, z0 = -Float(nz - 1) * step / 2
        var pos: [SCNVector3] = [], nor: [SCNVector3] = [], uv: [CGPoint] = [], idx: [Int32] = []
        for j in 0..<nz { for i in 0..<nx {
            let x = x0 + Float(i) * step, z = z0 + Float(j) * step, h = World.height(x, z)
            let dx = World.height(x + 2, z) - World.height(x - 2, z), dz = World.height(x, z + 2) - World.height(x, z - 2)
            let n = simd_normalize(SIMD3<Float>(-dx / 4, 1, -dz / 4))
            pos.append(SCNVector3(x, h, z))
            nor.append(SCNVector3(n.x, n.y, n.z))
            uv.append(CGPoint(x: CGFloat(x / 26), y: CGFloat(z / 26)))
        } }
        for j in 0..<nz - 1 { for i in 0..<nx - 1 {
            let a = Int32(j * nx + i), b = a + 1, c = a + Int32(nx), d = c + 1
            idx.append(contentsOf: [a, c, b, b, c, d])
        } }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor), SCNGeometrySource(textureCoordinates: uv)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let grass = SCNMaterial()
        grass.lightingModel = .physicallyBased
        grass.diffuse.contents = Textures.grass.albedo
        grass.normal.contents = Textures.grass.normal
        grass.normal.intensity = 0.6
        grass.roughness.contents = 1.0
        grass.metalness.contents = 0.0
        grass.multiply.contents = Textures.fieldPatches
        grass.multiply.contentsTransform = SCNMatrix4MakeScale(0.07, 0.07, 1)
        for p in [grass.diffuse, grass.normal, grass.multiply] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 8 }
        geo.materials = [grass]
        let land = SCNNode(geometry: geo)
        land.castsShadow = false
        scene.rootNode.addChildNode(land)

        @discardableResult
        func slab(width: CGFloat, depth: CGFloat, y: Float, x: Float, z: Float = 0, material: SCNMaterial) -> SCNNode {
            let plane = SCNPlane(width: width, height: depth)
            plane.materials = [material]
            let n = SCNNode(geometry: plane)
            n.eulerAngles.x = -.pi / 2
            n.position = SCNVector3(x, y, z)
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
            return n
        }
        // River: sandy banks under a reflective, slowly moving surface.
        let sand = Look.solid(0xb9a77c, roughness: 1)
        riverNodes.append(slab(width: CGFloat(K.river * 2 + 5), depth: 1300, y: 0.02, x: 0, material: sand))
        let water = SCNMaterial()
        water.lightingModel = .physicallyBased
        water.diffuse.contents = UIColor(hex: 0x1f5a7d)
        water.roughness.contents = 0.09
        water.metalness.contents = 0.55
        water.normal.contents = Textures.waterNormal
        water.normal.intensity = 0.55
        water.normal.wrapS = .repeat; water.normal.wrapT = .repeat
        let tiles = SCNMatrix4MakeScale(Float(K.river * 2) / 9, 1300 / 9, 1)
        water.normal.contentsTransform = tiles
        let flow = CABasicAnimation(keyPath: "contentsTransform")
        flow.fromValue = NSValue(scnMatrix4: tiles)
        flow.toValue = NSValue(scnMatrix4: SCNMatrix4Translate(tiles, 0.35, 1, 0))
        flow.duration = 16
        flow.repeatCount = .infinity
        water.normal.addAnimation(flow, forKey: "flow")
        riverNodes.append(slab(width: CGFloat(K.river * 2), depth: 1300, y: 0.06, x: 0, material: water))
        // A four-castle arena has a round lake in the middle instead.
        for (r, y, m) in [(K.lake + 2.5, Float(0.02), sand), (K.lake, Float(0.06), water)] {
            let disc = SCNNode(geometry: SCNCylinder(radius: CGFloat(r), height: 0.02))
            (disc.geometry as? SCNCylinder)?.radialSegmentCount = 64
            disc.geometry?.materials = [m]
            disc.position = SCNVector3(0, y, 0)
            disc.castsShadow = false
            scene.rootNode.addChildNode(disc)
            lakeNodes.append(disc)
        }
        // Packed earth under each castle seat.
        let d = Float(K.front + Double(K.gw) / 2), dirt = Look.solid(0x75684f, roughness: 1)
        let long = CGFloat(K.gw + 8), wide = CGFloat(K.gd + 8)
        earth = [slab(width: long, depth: wide, y: 0.03, x: -d, material: dirt), slab(width: long, depth: wide, y: 0.03, x: d, material: dirt),
                 slab(width: wide, depth: long, y: 0.03, x: 0, z: -d, material: dirt), slab(width: wide, depth: long, y: 0.03, x: 0, z: d, material: dirt)]

        let ground = SCNNode()
        ground.position = SCNVector3(0, -2, 0)
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: 1400, height: 4, length: 1000, chamferRadius: 0), options: nil))
        body.categoryBitMask = Phys.fixed
        body.collisionBitMask = Phys.loose
        body.friction = 0.9
        ground.physicsBody = body
        scene.rootNode.addChildNode(ground)
    }

    private func buildScenery() {
        let group = SCNNode()
        let leaves = [Look.solid(0x2c6b3a, roughness: 0.95), Look.solid(0x3a7d3f, roughness: 0.95), Look.solid(0x24583a, roughness: 0.95)]
        let bark = Look.solid(0x4f3a26, roughness: 0.9)
        var spots: [(Float, Float)] = [(-92, -44), (-84, 38), (-70, -40), (-48, -36), (-36, 40), (-22, -46), (-18, 34), (18, -40), (24, 46), (36, -42), (46, 38), (72, -40), (86, 34), (96, -14), (-100, 10), (-60, 50), (62, -54), (106, 54), (-112, -60), (14, 66), (-30, -70), (40, 72), (-124, 30), (126, -30)]
        var rnd = Mulberry32(2024)
        while spots.count < 150 {
            let x = Float(rnd.next() * 2 - 1) * 560, z = Float(rnd.next() * 2 - 1) * 460
            if abs(x) < 24 || (x * x + z * z).squareRoot() < 135 { continue }
            spots.append((x, z))
        }
        spots.removeAll { abs($0.0) < 30 && abs($0.1) < 80 }      // keep clear of the north and south seats
        for (i, s) in spots.enumerated() {
            let k = 0.9 + Float((i * 37) % 10) / 14, y = World.height(s.0, s.1)
            // Parts are direct children: flattening does not carry transforms of geometry-less parents.
            let trunk = SCNNode(geometry: SCNCylinder(radius: 0.45, height: 2.4))
            trunk.geometry?.materials = [bark]
            trunk.position = SCNVector3(s.0, y + 1.2 * k, s.1)
            trunk.scale = SCNVector3(k, k, k)
            group.addChildNode(trunk)
            for (r, h, up) in [(2.5, 3.2, 3.2), (2.0, 2.9, 5.0), (1.45, 2.6, 6.7), (0.9, 2.2, 8.2)] {
                let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: CGFloat(h)))
                (cone.geometry as? SCNCone)?.radialSegmentCount = 9
                cone.geometry?.materials = [leaves[i % leaves.count]]
                cone.position = SCNVector3(s.0, y + Float(up) * k, s.1)
                cone.scale = SCNVector3(k, k, k)
                group.addChildNode(cone)
            }
        }
        scene.rootNode.addChildNode(group.flattenedClone())

        // Far ranges, pale with distance, snow on the tallest.
        let far = SCNNode()
        let rock = Look.solid(0x6f8296, roughness: 1), snow = Look.solid(0xf2f5f8, roughness: 0.8)
        let peaks: [(Float, Float, Float, Float)] = [(-420, -620, 260, 150), (-120, -700, 330, 210), (190, -660, 280, 170), (480, -600, 250, 140), (-470, 620, 280, 160), (-150, 700, 340, 220), (180, 680, 300, 180), (500, 590, 240, 130), (-760, -120, 300, 190), (-780, 240, 260, 150), (770, 80, 310, 200), (780, -280, 250, 140)]
        for p in peaks {
            let n = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: CGFloat(p.2), height: CGFloat(p.3)))
            (n.geometry as? SCNCone)?.radialSegmentCount = 14
            n.geometry?.materials = [rock]
            n.position = SCNVector3(p.0, p.3 / 2 - 4, p.1)
            n.castsShadow = false
            far.addChildNode(n)
            if p.3 > 160 {
                let capH = p.3 * 0.3, capR = p.2 * 0.3
                let cap = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: CGFloat(capR) * 1.02, height: CGFloat(capH)))
                (cap.geometry as? SCNCone)?.radialSegmentCount = 14
                cap.geometry?.materials = [snow]
                cap.position = SCNVector3(p.0, p.3 - capH / 2 - 3.5, p.1)
                cap.castsShadow = false
                far.addChildNode(cap)
            }
        }
        scene.rootNode.addChildNode(far.flattenedClone())
    }

    // MARK: Castles

    /// Lays out the field for two or four castles: river or lake, cannons, shields and the ground under each seat.
    func setArena(_ a: Arena, force: Bool = false) {
        guard force || a != arena else { return }
        arena = a
        riverNodes.forEach { $0.isHidden = a.seats != 2 }
        lakeNodes.forEach { $0.isHidden = a.seats == 2 }
        for (i, n) in earth.enumerated() { n.isHidden = a.seats == 2 ? i > 1 : false }
        cannons.forEach { $0.root.removeFromParentNode() }
        domes.forEach { $0.removeFromParentNode() }
        cannons = (0..<a.seats).map { CannonView(side: $0, arena: a, scene: scene) }
        domes = (0..<a.seats).map { makeDome($0) }
    }

    func load(_ battle: Battle) {
        setArena(battle.arena)
        castleViews.forEach { $0.root.removeFromParentNode() }
        looseRoot.childNodes.forEach { $0.removeFromParentNode() }
        loose.removeAll(); rubble.removeAll()
        scene.removeAllParticleSystems()
        castleViews = battle.castles.map { CastleView(castle: $0) }
        castleViews.forEach { scene.rootNode.addChildNode($0.root) }
        ball.isHidden = true
        hidePreview()
        showTarget(nil)
        showPickup(nil)
        for i in domes.indices { setShield(i, on: false) }
        scene.physicsWorld.speed = 1
    }

    /// Builder preview: swaps the left castle for a design in progress.
    func preview(_ design: CastleDesign) {
        guard !castleViews.isEmpty else { return }
        castleViews[0].root.removeFromParentNode()
        let view = CastleView(castle: Castle(side: 0, design: design), physics: false)
        castleViews[0] = view
        scene.rootNode.addChildNode(view.root)
    }

    /// Shows the outcome of a shot: loose blocks, falling roofs, rebuilt walls and effects.
    func showImpact(_ res: ShotResult, outcome: ShotOutcome) {
        let sp = max(res.vel.length, 0.001)
        let dir = SIMD3<Float>(Float(res.vel.x / sp), Float(res.vel.y / sp), Float(res.vel.z / sp))
        let centers = res.blasts.map { ($0.center.f, Float($0.radius)) }
        var any = false
        for (i, d) in outcome.damage.enumerated() where d.cells > 0 || !d.crack.isEmpty {
            any = true
            let view = castleViews[i]
            for id in d.blast {
                let n = view.release(id)
                // Thrown outward from whichever blast was closest.
                var best = centers.first ?? (res.pos.f, Float(K.blastR)), bestD = Float.greatestFiniteMagnitude
                for c in centers { let dist = simd_distance(n.simdPosition, c.0); if dist < bestD { bestD = dist; best = c } }
                var o = n.simdPosition - best.0
                let l = max(simd_length(o), 0.001)
                o /= l
                let k = 7 + 12 * (1 - min(1, l / best.1)) + Float.random(in: 0...4)
                let v = o * k + dir * 7 + SIMD3(Float.random(in: -1.5...1.5), Float.random(in: 3...9), Float.random(in: -1.5...1.5))
                n.physicsBody?.velocity = SCNVector3(v.x, v.y, v.z)
                n.physicsBody?.angularVelocity = SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: 2...9))
                looseRoot.addChildNode(n)
                loose.append((n, clock, false))
            }
            for id in d.crack where view.castle.blocks[id].alive {
                burst(at: view.castle.center(of: view.castle.blocks[id]).f, colors: [0x5c6166, 0xb5b9bd], count: 8, speed: 3, life: 1.2, size: 1.0, accel: 1, cone: false, grow: 1.6, alpha: 0.5)
            }
            for id in d.fall {
                let n = view.release(id)
                n.physicsBody?.velocity = SCNVector3(Float.random(in: -1...1) + dir.x * 1.5, 0, Float.random(in: -1...1) + dir.z * 1.5)
                n.physicsBody?.angularVelocity = SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: 0...2))
                looseRoot.addChildNode(n)
                loose.append((n, clock, false))
            }
            for j in view.decor.indices where view.decor[j].alive {
                let ids = view.decor[j].ids
                let dead = ids.filter { !view.castle.blocks[$0].alive }.count
                if !ids.isEmpty && dead * 2 < ids.count { continue }
                view.decor[j].alive = false
                let n = view.decor[j].node
                let world = n.simdWorldPosition
                n.removeFromParentNode()
                n.simdPosition = world
                let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(node: n, options: [.type: SCNPhysicsShape.ShapeType.convexHull]))
                body.mass = 6
                body.categoryBitMask = Phys.loose
                body.collisionBitMask = Phys.fixed | Phys.loose
                body.velocity = SCNVector3(Float.random(in: -3...3) + dir.x * 4, Float.random(in: 4...8), Float.random(in: -3...3) + dir.z * 4)
                body.angularVelocity = SCNVector4(Float.random(in: -1...1), 0.2, Float.random(in: -1...1), Float.random(in: 1...3))
                n.physicsBody = body
                looseRoot.addChildNode(n)
                loose.append((n, clock, true))
            }
            if view.castle.heartLost, let p = view.breakGem(decoy: nil) {
                burst(at: p, colors: [Look.heartColors(view.castle.heartKind).glow, 0xffffff, 0xffb3d1], count: 160, speed: 22, life: 1.2, size: 0.9, accel: -9, cone: false, additive: true)
                flash(at: p, strength: 5200)
            }
            for k in d.decoys {
                guard let p = view.breakGem(decoy: k) else { continue }
                burst(at: p, colors: [0x8d8794, 0xc9c3cf], count: 50, speed: 7, life: 1.4, size: 1.6, accel: 2, cone: false, grow: 1.8, alpha: 0.6)
            }
            view.rebuildMesh()
        }
        switch res.kind {
        case .out: break
        case .water: splash(at: res.pos.f, big: true)
        case .ground, .castle:
            for (c, radius) in centers {
                let big = CGFloat(radius / Float(K.blastR))
                burst(at: c, colors: [0xffd84a, 0xff8a1e, 0xffffff], count: (any ? 90 : 36) * big * big, speed: (any ? 20 : 11) * big, life: 0.55, size: 1.4 * big, accel: -6, cone: false, additive: true)
                burst(at: c + SIMD3(0, 1, 0), colors: [0x5c6166, 0x8b9096, 0xb5b9bd], count: (any ? 54 : 22) * big, speed: 6.5, life: 2.2, size: 2.4 * big, accel: 2.4, cone: false, grow: 1.9, alpha: 0.42)
                flash(at: c, strength: 2600 * big)
            }
            if res.crit, let c = centers.first { burst(at: c.0, colors: [0xffe27a, 0xf2cd37], count: 80, speed: 26, life: 0.8, size: 0.8, accel: -10, cone: false, additive: true) }
            if res.kind == .ground { burst(at: SIMD3(res.pos.f.x, 0.3, res.pos.f.z), colors: [0x4c7a39, 0x5b4630], count: 46, speed: 13, life: 1.0, size: 0.8, accel: -26, cone: true) }
        }
        if !outcome.repaired.isEmpty {
            let spots = castleViews[res.shooter].restore(outcome.repaired)
            for p in spots.prefix(14) { burst(at: p, colors: [0x7be08f, 0xffffff], count: 10, speed: 3, life: 1.0, size: 0.6, accel: 4, cone: false, additive: true) }
        }
    }

    /// Stands blocks back up outside of a shot, such as a living heart growing back.
    func restoreBlocks(side: Int, ids: [Int]) {
        guard side < castleViews.count else { return }
        let glow = Look.heartColors(castleViews[side].castle.heartKind).glow
        for p in castleViews[side].restore(ids) { burst(at: p, colors: [glow, 0xffffff], count: 24, speed: 4, life: 1.2, size: 0.7, accel: 3, cone: false, additive: true) }
    }

    // MARK: Ball, preview, target, balloon, shield

    func fireBall(from p: Vec3, dir d: Vec3, side: Int, style: BallStyle, ammo: Ammo, mega: Bool) {
        ball.simdPosition = p.f
        ball.isHidden = false
        ball.simdScale = SIMD3(repeating: mega ? 1.7 : 1)
        let colors: (ball: UInt32, trail: UInt32)
        switch ammo {
        case .standard: colors = mega ? (0xff5a1e, 0xff8a1e) : (style.ball, style.trail)
        case .cluster: colors = (0x7a3b12, 0xffb347)
        case .piercer: colors = (0x9aa3ab, 0xd6ecff)
        case .homing: colors = (0x5a2a8a, 0xc79bff)
        }
        let m = Look.solid(colors.ball, roughness: 0.35, metal: ammo == .standard && !mega && style.id == 0 ? 1 : 0.6)
        if mega || ammo != .standard { m.emission.contents = UIColor(hex: colors.trail); m.emission.intensity = 0.6 }
        ball.geometry?.materials = [m]
        ball.removeAllParticleSystems()
        let plain = !mega && ammo == .standard && style.id == 0
        ball.addParticleSystem(World.makeTrail(color: colors.trail, size: mega ? 1.1 : 0.5, plain: plain))
        cannons[side].kick = 1
        burst(at: p.f, colors: [0xffd84a, 0xff8a1e, 0xffffff], count: 28, speed: 16, life: 0.25, size: 1.2, accel: 0, cone: true, direction: d.f, additive: true)
        burst(at: p.f, colors: [0xe4e7ea, 0xb4b9be, 0x8d9297], count: 36, speed: 7, life: 1.8, size: 2.6, accel: 1.5, cone: true, direction: d.f, grow: 2.4)
        flash(at: p.f, strength: 1800)
    }

    func endBall() {
        ball.isHidden = true
        ball.removeAllParticleSystems()
    }

    func showPreview(_ points: [SIMD3<Float>]) {
        for (i, n) in dots.enumerated() {
            if i < points.count {
                n.simdPosition = points[i]
                n.simdScale = SIMD3(repeating: max(0.35, 1 - Float(i) * 0.02))
                n.isHidden = false
            } else { n.isHidden = true }
        }
    }

    func hidePreview() { dots.forEach { $0.isHidden = true } }

    /// Places or hides the gold target marker. It always faces the camera and draws over the walls.
    func showTarget(_ p: Vec3?) {
        guard let p else { targetNode.isHidden = true; return }
        targetNode.simdPosition = p.f
        targetNode.isHidden = false
    }

    private static func badge(_ image: UIImage, size: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        let m = Look.unlit(.white)
        m.diffuse.contents = image
        m.isDoubleSided = true
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 50
        n.castsShadow = false
        return n
    }

    private static func makeTargetNode() -> SCNNode {
        let n = badge(Textures.bullseye, size: 4.4)
        n.isHidden = true
        n.runAction(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.6), .scale(to: 1, duration: 0.6)])))
        return n
    }

    static func tint(of kind: PickupKind) -> UInt32 {
        switch kind {
        case .repair: return 0x3fb65c
        case .shield: return 0x3a8fdc
        case .charge: return 0xf2cd37
        }
    }

    static func symbol(of kind: PickupKind) -> String {
        switch kind {
        case .repair: return "wrench.and.screwdriver.fill"
        case .shield: return "shield.fill"
        case .charge: return "bolt.fill"
        }
    }

    /// Shows the balloon for the current pickup, or takes it down.
    func showPickup(_ p: Pickup?) {
        if p == pickupShown { return }
        pickupShown = p
        pickupNode?.removeFromParentNode()
        pickupNode = nil
        guard let p else { return }
        let n = SCNNode()
        let envelope = SCNNode(geometry: SCNSphere(radius: 1.9))
        envelope.geometry?.materials = [Look.solid(World.tint(of: p.kind), roughness: 0.45)]
        envelope.scale = SCNVector3(1, 1.18, 1)
        n.addChildNode(envelope)
        let basket = SCNNode(geometry: SCNBox(width: 0.9, height: 0.7, length: 0.9, chamferRadius: 0.05))
        basket.geometry?.materials = [Look.wood()]
        basket.position = SCNVector3(0, -3.3, 0)
        n.addChildNode(basket)
        for (dx, dz) in [(Float(0.4), Float(0.4)), (-0.4, 0.4), (0.4, -0.4), (-0.4, -0.4)] {
            let rope = SCNNode(geometry: SCNCylinder(radius: 0.03, height: 1.5))
            rope.geometry?.materials = [Look.solid(0x3a3d40, roughness: 0.9)]
            rope.position = SCNVector3(dx, -2.3, dz)
            n.addChildNode(rope)
        }
        n.addChildNode(World.badge(Textures.symbol(World.symbol(of: p.kind)), size: 2))
        n.simdPosition = p.pos.f
        n.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.6, z: 0, duration: 1.4), .moveBy(x: 0, y: -0.6, z: 0, duration: 1.4)])))
        n.scale = SCNVector3(0.01, 0.01, 0.01)
        n.runAction(.scale(to: 1, duration: 0.35))
        scene.rootNode.addChildNode(n)
        pickupNode = n
    }

    /// The ball just went through the balloon.
    func popPickup() {
        guard let n = pickupNode, let p = pickupShown else { return }
        burst(at: n.presentation.simdPosition, colors: [World.tint(of: p.kind), 0xffffff], count: 60, speed: 12, life: 0.7, size: 0.7, accel: -8, cone: false, additive: true)
        n.removeFromParentNode()
        pickupNode = nil
        pickupShown = nil
    }

    private func makeDome(_ side: Int) -> SCNNode {
        let s = SCNSphere(radius: 1)
        s.segmentCount = 36
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: 0x6fc3ff)
        m.transparency = 0.2
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .add
        s.materials = [m]
        let n = SCNNode(geometry: s)
        let c = arena.castleCenter(side)
        n.position = SCNVector3(Float(c.x), 0, Float(c.z))
        n.scale = arena.forward(side).x != 0 ? SCNVector3(17, 21, 21) : SCNVector3(21, 21, 17)
        n.opacity = 0
        n.castsShadow = false
        n.renderingOrder = 20
        scene.rootNode.addChildNode(n)
        return n
    }

    func setShield(_ side: Int, on: Bool) {
        guard side < domes.count else { return }
        domes[side].runAction(.fadeOpacity(to: on ? 1 : 0, duration: 0.4))
    }

    // MARK: Effects

    private static func curve(_ values: [Double], _ times: [Double]) -> SCNParticlePropertyController {
        let a = CAKeyframeAnimation()
        a.values = values
        a.keyTimes = times.map { NSNumber(value: $0) }
        return SCNParticlePropertyController(animation: a)
    }

    private static let fade = curve([1.0, 0.85, 0.0], [0, 0.4, 1])

    private static func makeTrail(color: UInt32, size: CGFloat, plain: Bool) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = Textures.puff
        ps.birthRate = plain ? 70 : 100
        ps.particleLifeSpan = plain ? 0.5 : 0.65
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.3
        ps.particleVelocity = 0.3
        ps.spreadingAngle = 180
        ps.particleColor = UIColor(hex: color, alpha: plain ? 0.5 : 0.85)
        ps.blendMode = plain ? .alpha : .additive
        ps.isLightingEnabled = false
        ps.propertyControllers = [.opacity: fade]
        return ps
    }

    /// One puff of particles. `grow` makes each sprite swell over its life, which is what sells smoke.
    private func burst(at p: SIMD3<Float>, colors: [UInt32], count: CGFloat, speed: CGFloat, life: CGFloat, size: CGFloat, accel: Float, cone: Bool,
                       direction: SIMD3<Float> = SIMD3(0, 1, 0), additive: Bool = false, grow: Double = 1, alpha: CGFloat = 0.7) {
        for hex in colors {
            let ps = SCNParticleSystem()
            ps.particleImage = Textures.puff
            ps.loops = false
            ps.birthRate = count / CGFloat(colors.count)
            ps.emissionDuration = 0.06
            ps.particleLifeSpan = life
            ps.particleLifeSpanVariation = life * 0.5
            ps.particleVelocity = speed
            ps.particleVelocityVariation = speed * 0.7
            ps.emittingDirection = SCNVector3(direction.x, direction.y, direction.z)
            ps.spreadingAngle = cone ? 32 : 180
            ps.particleSize = size
            ps.particleSizeVariation = size * 0.5
            ps.particleAngleVariation = 360
            ps.particleColor = UIColor(hex: hex, alpha: additive ? 1 : alpha)
            ps.acceleration = SCNVector3(0, accel, 0)
            ps.dampingFactor = 1.6
            ps.blendMode = additive ? .additive : .alpha
            ps.isLightingEnabled = false
            var controllers: [SCNParticleSystem.ParticleProperty: SCNParticlePropertyController] = [.opacity: World.fade]
            if grow > 1 { controllers[.size] = World.curve([Double(size) * 0.5, Double(size) * grow], [0, 1]) }
            ps.propertyControllers = controllers
            scene.addParticleSystem(ps, transform: SCNMatrix4MakeTranslation(p.x, p.y, p.z))
        }
    }

    /// A short burst of light, so a blast shows on the walls around it.
    private func flash(at p: SIMD3<Float>, strength: CGFloat) {
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(hex: 0xffb35a)
        light.intensity = strength
        light.attenuationStartDistance = 2
        light.attenuationEndDistance = 30
        let n = SCNNode()
        n.light = light
        n.simdPosition = p + SIMD3(0, 1.5, 0)
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([.customAction(duration: 0.28) { node, t in node.light?.intensity = strength * (1 - t / 0.28) }, .removeFromParentNode()]))
    }

    private func splash(at p: SIMD3<Float>, big: Bool) {
        burst(at: SIMD3(p.x, 0.3, p.z), colors: [0x8fc4e6, 0xffffff], count: big ? 80 : 10, speed: big ? 17 : 8, life: 1.0, size: big ? 0.9 : 0.6, accel: -28, cone: true)
        onSplash?()
    }

    // MARK: Per-frame upkeep

    func update(dt: TimeInterval) {
        clock += dt
        sweep -= dt
        guard sweep <= 0 else { return }
        sweep = 0.25
        var keep: [(node: SCNNode, born: TimeInterval, decor: Bool)] = []
        for item in loose {
            let p = item.node.presentation.simdWorldPosition
            let age = clock - item.born
            if p.y < 1.2 && arena.isWater(Double(p.x), Double(p.z)) {              // sank in the water
                burst(at: SIMD3(p.x, 0.3, p.z), colors: [0x8fc4e6, 0xffffff], count: 8, speed: 7, life: 0.8, size: 0.6, accel: -28, cone: true)
                item.node.removeFromParentNode()
            } else if p.y < -3 || age > 30 {
                item.node.removeFromParentNode()
            } else if age > 7 {
                let inside = castleViews.contains { v in
                    let l = v.castle.local(Double(p.x), Double(p.z))
                    return l.x > -1 && l.x < Double(K.gw) + 1 && l.z > -1 && l.z < Double(K.gd) + 1
                }
                if inside || item.decor {
                    // clear rubble off the castle so what is still standing stays readable
                    item.node.physicsBody = nil
                    item.node.runAction(.sequence([.scale(to: 0.01, duration: 0.3), .removeFromParentNode()]))
                } else {
                    item.node.simdTransform = item.node.presentation.simdTransform
                    item.node.physicsBody = nil
                    rubble.append(item.node)
                }
            } else { keep.append(item) }
        }
        loose = keep
        while rubble.count > 140 { rubble.removeFirst().removeFromParentNode() }
    }
}

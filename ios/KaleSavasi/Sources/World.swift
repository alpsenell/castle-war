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
    var scn: SCNVector3 { SCNVector3(Float(x), Float(y), Float(z)) }
}

enum Look {
    static let stone: [[UInt32]] = [[0xb4b9be, 0xa5abb1, 0xc3c7cb], [0xe0cfa8, 0xd0bd92, 0xeadcbb]]
    static let accent: [UInt32] = [0xc62d1f, 0x1f5fc4]
    static let trim: [UInt32] = [0x70767c, 0x9c8b67]
    static let ink: UInt32 = 0x1b2a34

    static func material(_ hex: UInt32, gloss: CGFloat = 0.1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = UIColor(hex: hex)
        m.specular.contents = UIColor(white: gloss, alpha: 1)
        m.shininess = 0.3
        return m
    }
    /// Colours of a castle's mesh elements: three stone shades, team colour, trim.
    static func castleColors(_ side: Int) -> [UInt32] { stone[side] + [accent[side], trim[side]] }
}

/// Collects boxes into one geometry with an element per material.
struct MeshBuilder {
    private var pos: [SCNVector3] = []
    private var nor: [SCNVector3] = []
    private var idx: [[Int32]]

    init(materials: Int) { idx = Array(repeating: [], count: materials) }

    mutating func addBox(center c: SIMD3<Float>, size: SIMD3<Float>, material: Int) {
        let h = size / 2
        // normal, tangent u, bitangent v with u × v = normal
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
        ]
        for (n, u, v) in faces {
            let base = Int32(pos.count)
            let o = c + n * h, du = u * h, dv = v * h
            for p in [o - du - dv, o + du - dv, o + du + dv, o - du + dv] {
                pos.append(SCNVector3(p.x, p.y, p.z))
                nor.append(SCNVector3(n.x, n.y, n.z))
            }
            idx[material].append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
    }

    func geometry(materials: [SCNMaterial]) -> SCNGeometry {
        var elements: [SCNGeometryElement] = [], mats: [SCNMaterial] = []
        for (i, list) in idx.enumerated() where !list.isEmpty {
            elements.append(SCNGeometryElement(indices: list, primitiveType: .triangles))
            mats.append(materials[i])
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor)], elements: elements)
        g.materials = mats
        return g
    }
}

private enum Phys {
    static let fixed = 1, loose = 2
    private static var shapes: [Int: SCNPhysicsShape] = [:]
    static func blockShape(_ len: Int) -> SCNPhysicsShape {
        if let s = shapes[len] { return s }
        let s = SCNPhysicsShape(geometry: SCNBox(width: CGFloat(len) - 0.06, height: CGFloat(K.lh) - 0.06, length: 0.94, chamferRadius: 0), options: nil)
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

    init(castle: Castle) {
        self.castle = castle
        materials = Look.castleColors(castle.side).map { Look.material($0) }
        var rnd = Mulberry32(UInt32(castle.side * 977 + 13))
        colorOf = castle.blocks.map { b in
            if b.mat == 2 { return 3 }
            if b.mat == 3 { return 4 }
            let r = rnd.next()
            return r < 0.5 ? 0 : r < 0.8 ? 1 : 2
        }
        root.addChildNode(meshNode)
        for b in castle.blocks where b.alive {
            let n = SCNNode()
            n.simdPosition = castle.center(of: b).f
            if b.dir == 2 { n.eulerAngles.y = .pi / 2 }
            let body = SCNPhysicsBody(type: .static, shape: Phys.blockShape(b.len))
            body.categoryBitMask = Phys.fixed
            body.collisionBitMask = Phys.loose
            n.physicsBody = body
            root.addChildNode(n)
            fixedBodies[b.id] = n
        }
        let accent = Look.material(Look.accent[castle.side], gloss: 0.25)
        for d in castle.decor {
            let n = SCNNode()
            let roof = SCNNode(geometry: SCNPyramid(width: CGFloat(d.w * 2), height: CGFloat(d.ht), length: CGFloat(d.d * 2)))
            roof.geometry?.materials = [accent]
            n.addChildNode(roof)
            if d.flag {
                let pole = SCNNode(geometry: SCNCylinder(radius: 0.1, height: 3.4))
                pole.geometry?.materials = [Look.material(0xf4f4f4)]
                pole.position = SCNVector3(0, Float(d.ht) + 1.3, 0)
                n.addChildNode(pole)
                let cloth = SCNNode(geometry: SCNBox(width: 2.2, height: 1.3, length: 0.08, chamferRadius: 0))
                cloth.geometry?.materials = [Look.material(0xf2cd37)]
                cloth.position = SCNVector3(Float(castle.s) * 1.15, Float(d.ht) + 2.3, 0)
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
        rebuildMesh()
    }

    func rebuildMesh() {
        var mb = MeshBuilder(materials: materials.count)
        for b in castle.blocks where b.alive {
            let c = castle.center(of: b).f
            let size: SIMD3<Float> = b.dir == 1 ? SIMD3(Float(b.len), Float(K.lh), 1) : SIMD3(1, Float(K.lh), Float(b.len))
            mb.addBox(center: c, size: size, material: colorOf[b.id])
        }
        meshNode.geometry = mb.geometry(materials: materials)
    }

    /// Turns a block that just died into a loose physics body.
    fileprivate func release(_ id: Int) -> SCNNode {
        let b = castle.blocks[id]
        let old = fixedBodies.removeValue(forKey: id)
        old?.removeFromParentNode()
        let key = b.len * 10 + colorOf[id]
        let geo: SCNGeometry
        if let g = looseGeo[key] { geo = g } else {
            let g = SCNBox(width: CGFloat(b.len) - 0.04, height: CGFloat(K.lh) - 0.04, length: 0.96, chamferRadius: 0.07)
            g.materials = [materials[colorOf[id]]]
            looseGeo[key] = g
            geo = g
        }
        let n = SCNNode(geometry: geo)
        n.simdPosition = castle.center(of: b).f
        if b.dir == 2 { n.eulerAngles.y = .pi / 2 }
        let body = SCNPhysicsBody(type: .dynamic, shape: Phys.blockShape(b.len))
        body.mass = CGFloat(b.len)
        body.friction = 0.7
        body.restitution = 0.2
        body.angularDamping = 0.25
        body.categoryBitMask = Phys.loose
        body.collisionBitMask = Phys.fixed | Phys.loose
        n.physicsBody = body
        return n
    }
}

final class CannonView {
    let yawNode = SCNNode()
    private let barrel = SCNNode()
    var kick: Float = 0

    private let side: Int

    init(side: Int, scene: SCNScene) {
        self.side = side
        let root = SCNNode()
        root.position = SCNVector3(side == 0 ? -Float(K.platX) : Float(K.platX), 0, 0)
        let w = CGFloat(K.platHalf * 2)
        let base = SCNNode(geometry: SCNBox(width: w, height: 1.8, length: w, chamferRadius: 0.08))
        base.geometry?.materials = [Look.material(Look.trim[side])]
        base.position = SCNVector3(0, 0.9, 0)
        let top = SCNNode(geometry: SCNBox(width: w + 0.4, height: 0.6, length: w + 0.4, chamferRadius: 0.08))
        top.geometry?.materials = [Look.material(Look.accent[side], gloss: 0.25)]
        top.position = SCNVector3(0, 2.1, 0)
        root.addChildNode(base); root.addChildNode(top)

        yawNode.position = SCNVector3(0, Float(K.platTop), 0)
        root.addChildNode(yawNode)
        let wood = Look.material(0x6b3f1d), dark = Look.material(Look.ink, gloss: 0.5)
        let carriage = SCNNode(geometry: SCNBox(width: 2.6, height: 0.5, length: 1.6, chamferRadius: 0.06))
        carriage.geometry?.materials = [wood]
        carriage.position = SCNVector3(0, 0.75, 0)
        yawNode.addChildNode(carriage)
        for z in [Float(-1.0), 1.0] {
            let wheel = SCNNode(geometry: SCNCylinder(radius: 0.8, height: 0.3))
            wheel.geometry?.materials = [Look.material(0x2b2f33)]
            wheel.eulerAngles.x = .pi / 2
            wheel.position = SCNVector3(0, 0.8, z)
            yawNode.addChildNode(wheel)
            let hub = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 0.36))
            hub.geometry?.materials = [Look.material(0xf2cd37, gloss: 0.4)]
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
        tube.geometry?.materials = [dark]
        tube.eulerAngles.z = -.pi / 2
        tube.position = SCNVector3(0.8, 0, 0)
        let lip = SCNNode(geometry: SCNCylinder(radius: 0.6, height: 0.32))
        lip.geometry?.materials = [dark]
        lip.eulerAngles.z = -.pi / 2
        lip.position = SCNVector3(2.35, 0, 0)
        let knob = SCNNode(geometry: SCNSphere(radius: 0.5))
        knob.geometry?.materials = [dark]
        knob.position = SCNVector3(-0.9, 0, 0)
        barrel.addChildNode(tube); barrel.addChildNode(lip); barrel.addChildNode(knob)
        scene.rootNode.addChildNode(root)
    }

    func pose(yaw: Double, dt: Float) {
        let y = Float(yaw * .pi / 180)
        yawNode.eulerAngles.y = side == 1 ? .pi - y : -y
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
    private let looseRoot = SCNNode()
    private var loose: [(node: SCNNode, born: TimeInterval, decor: Bool)] = []
    private var rubble: [SCNNode] = []
    private var clock: TimeInterval = 0
    private var sweep: TimeInterval = 0
    var onSplash: (() -> Void)?

    init() {
        buildSky()
        buildLights()
        buildTerrain()
        buildScenery()
        cannons = [CannonView(side: 0, scene: scene), CannonView(side: 1, scene: scene)]

        ball.geometry?.materials = [Look.material(Look.ink, gloss: 0.7)]
        ball.isHidden = true
        scene.rootNode.addChildNode(ball)

        let dotGeo = SCNSphere(radius: 0.22)
        dotGeo.segmentCount = 10
        let dm = SCNMaterial()
        dm.lightingModel = .constant
        dm.diffuse.contents = UIColor.white
        dotGeo.materials = [dm]
        for _ in 0..<20 {
            let n = SCNNode(geometry: dotGeo)
            n.isHidden = true
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
            dots.append(n)
        }

        camera.zNear = 0.5
        camera.zFar = 1200
        camera.fieldOfView = 50
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(90, 40, 90)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(looseRoot)
        scene.physicsWorld.gravity = SCNVector3(0, -22, 0)
    }

    // MARK: Setup

    private func buildSky() {
        let size = CGSize(width: 16, height: 512)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hex: 0x3b8fe0).cgColor, UIColor(hex: 0x8fd0ff).cgColor, UIColor(hex: 0xdff2ff).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 0.78])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
        }
        scene.background.contents = img
        scene.fogColor = UIColor(hex: 0xd3ecff)
        scene.fogStartDistance = 220
        scene.fogEndDistance = 620
    }

    private func buildLights() {
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 560
        amb.color = UIColor(hex: 0xe6efff)
        let an = SCNNode(); an.light = amb
        scene.rootNode.addChildNode(an)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 980
        sun.color = UIColor(hex: 0xfff6e8)
        sun.castsShadow = true
        sun.shadowColor = UIColor(white: 0, alpha: 0.36)
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 260
        sun.shadowCascadeCount = 3
        let sn = SCNNode(); sn.light = sun
        sn.position = SCNVector3(30, 90, 60)
        sn.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sn)
    }

    private static func speckled(base: UInt32, marks: [UInt32], streaks: Bool) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        var rnd = Mulberry32(base)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(hex: base).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for i in 0..<(streaks ? 60 : 420) {
                UIColor(hex: marks[i % marks.count], alpha: 0.5).setFill()
                let x = rnd.next() * 256, y = rnd.next() * 256
                let w = streaks ? 18 + rnd.next() * 40 : 3 + rnd.next() * 7, h = streaks ? 3.0 : w
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
        }
    }

    private func slab(width: CGFloat, depth: CGFloat, image: UIImage, tile: CGFloat, y: Float, x: Float = 0) {
        let plane = SCNPlane(width: width, height: depth)
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(width / tile), Float(depth / tile), 1)
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(x, y, 0)
        n.castsShadow = false
        scene.rootNode.addChildNode(n)
    }

    private func buildTerrain() {
        let grass = World.speckled(base: 0x5aa846, marks: [0x6dba58, 0x4c9639, 0x64b04f], streaks: false)
        let yard = World.speckled(base: 0x4a8f3a, marks: [0x58a046, 0x3f7d31], streaks: false)
        let water = World.speckled(base: 0x3a8fdc, marks: [0x6ab2ee, 0x2f7fca], streaks: true)
        slab(width: 1400, depth: 1000, image: grass, tile: 24, y: 0)
        slab(width: CGFloat(K.river * 2), depth: 1000, image: water, tile: 16, y: 0.04)
        let cx = Float(K.front + Double(K.gw) / 2)
        for sx in [-cx, cx] { slab(width: CGFloat(K.gw + 8), depth: CGFloat(K.gd + 8), image: yard, tile: 16, y: 0.03, x: sx) }

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
        let leaf = Look.material(0x2f7f45), bark = Look.material(0x6b3f1d)
        let spots: [(Float, Float)] = [(-92, -44), (-84, 38), (-70, -40), (-48, -36), (-36, 40), (-22, -46), (-18, 34), (18, -40), (24, 46), (36, -42), (46, 38), (72, -40), (86, 34), (96, -14), (-100, 10), (-60, 50), (62, -54), (106, 54), (-112, -60), (14, 66), (-30, -70), (40, 72), (-124, 30), (126, -30)]
        for (i, s) in spots.enumerated() {
            let k = 0.9 + Float((i * 37) % 10) / 16
            // Parts are direct children: flattening does not carry transforms of geometry-less parents.
            let trunk = SCNNode(geometry: SCNCylinder(radius: 0.5, height: 2))
            trunk.geometry?.materials = [bark]
            trunk.position = SCNVector3(s.0, k, s.1)
            trunk.scale = SCNVector3(k, k, k)
            group.addChildNode(trunk)
            for (r, h, y) in [(2.4, 3.0, 3.0), (1.9, 2.7, 4.9), (1.3, 2.4, 6.6)] {
                let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: CGFloat(h)))
                cone.geometry?.materials = [leaf]
                cone.position = SCNVector3(s.0, Float(y) * k, s.1)
                cone.scale = SCNVector3(k, k, k)
                group.addChildNode(cone)
            }
        }
        scene.rootNode.addChildNode(group.flattenedClone())

        let far = SCNNode()
        let hill = Look.material(0x7fae8e, gloss: 0)
        let peaks: [(Float, Float, Float, Float)] = [(-300, -420, 150, 60), (-120, -460, 190, 80), (70, -450, 170, 68), (260, -420, 160, 55), (-330, 420, 170, 62), (-90, 460, 200, 78), (150, 440, 180, 70), (350, 400, 150, 52), (-520, -60, 170, 64), (530, 40, 180, 66)]
        for p in peaks {
            let n = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: CGFloat(p.2), height: CGFloat(p.3)))
            n.geometry?.materials = [hill]
            n.position = SCNVector3(p.0, p.3 / 2 - 2, p.1)
            n.castsShadow = false
            far.addChildNode(n)
        }
        scene.rootNode.addChildNode(far.flattenedClone())

        let sky = SCNNode()
        let cm = SCNMaterial()
        cm.lightingModel = .constant
        cm.diffuse.contents = UIColor.white
        let puffs: [(Float, Float, Float)] = [(-110, 78, -120), (-20, 92, -160), (80, 82, -130), (150, 96, -40), (-160, 86, 40), (40, 100, 150), (-70, 90, 150), (170, 76, 110)]
        for (i, c) in puffs.enumerated() {
            for (dx, dy, dz, r) in [(Float(0), Float(0), Float(0), Float(9)), (9, 1.5, 2, 7), (-9, 1, -2, 6.5), (2, 4, 0, 6)] {
                let s = SCNSphere(radius: CGFloat(r)); s.segmentCount = 14; s.materials = [cm]
                let n = SCNNode(geometry: s)
                n.position = SCNVector3(c.0 + dx, c.1 + dy + Float(i % 3) * 2, c.2 + dz)
                n.scale = SCNVector3(1, 0.55, 0.8)
                n.castsShadow = false
                sky.addChildNode(n)
            }
        }
        scene.rootNode.addChildNode(sky.flattenedClone())
    }

    // MARK: Castles

    func load(_ battle: Battle) {
        castleViews.forEach { $0.root.removeFromParentNode() }
        looseRoot.childNodes.forEach { $0.removeFromParentNode() }
        loose.removeAll(); rubble.removeAll()
        scene.removeAllParticleSystems()
        castleViews = battle.castles.map(CastleView.init)
        castleViews.forEach { scene.rootNode.addChildNode($0.root) }
        ball.isHidden = true
        hidePreview()
        scene.physicsWorld.speed = 1
    }

    /// Shows the outcome of a shot: loose blocks, falling roofs, a rebuilt wall mesh and effects.
    func showImpact(_ res: ShotResult, damage: [Damage]) {
        let sp = max(res.vel.length, 0.001)
        let dir = SIMD3<Float>(Float(res.vel.x / sp), Float(res.vel.y / sp), Float(res.vel.z / sp))
        let c = res.center.f
        var any = false
        for (i, d) in damage.enumerated() where d.cells > 0 {
            any = true
            let view = castleViews[i]
            for id in d.blast {
                let n = view.release(id)
                var o = n.simdPosition - c
                let l = max(simd_length(o), 0.001)
                o /= l
                let k = 7 + 12 * (1 - min(1, l / Float(K.blastR))) + Float.random(in: 0...4)
                let v = o * k + dir * 7 + SIMD3(Float.random(in: -1.5...1.5), Float.random(in: 3...9), Float.random(in: -1.5...1.5))
                n.physicsBody?.velocity = SCNVector3(v.x, v.y, v.z)
                n.physicsBody?.angularVelocity = SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: 2...9))
                looseRoot.addChildNode(n)
                loose.append((n, clock, false))
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
            view.rebuildMesh()
        }
        switch res.kind {
        case .out: break
        case .water: splash(at: res.pos.f, big: true)
        case .ground, .castle:
            burst(at: c, colors: [0xffd84a, 0xff8a1e, 0xffffff], count: any ? 90 : 36, speed: any ? 20 : 11, life: 0.55, size: 1.1, accel: -6, cone: false, additive: true)
            burst(at: c + SIMD3(0, 1, 0), colors: [0x6b7176, 0x969ba0], count: any ? 46 : 18, speed: 5, life: 1.9, size: 3.2, accel: 2.5, cone: false)
            if res.kind == .ground { burst(at: SIMD3(c.x, 0.3, c.z), colors: [0x5aa846, 0x6b3f1d], count: 40, speed: 13, life: 1.0, size: 0.6, accel: -26, cone: true) }
        }
    }

    // MARK: Ball, preview, effects

    func fireBall(from p: Vec3, dir d: Vec3, side: Int) {
        ball.simdPosition = p.f
        ball.isHidden = false
        ball.removeAllParticleSystems()
        ball.addParticleSystem(World.makeTrail())
        cannons[side].kick = 1
        burst(at: p.f, colors: [0xffd84a, 0xff8a1e, 0xffffff], count: 28, speed: 16, life: 0.25, size: 0.9, accel: 0, cone: true, direction: d.f, additive: true)
        burst(at: p.f, colors: [0xe9edf0, 0xb9c0c6], count: 30, speed: 7, life: 1.2, size: 2.2, accel: 1.5, cone: true, direction: d.f)
    }

    func endBall() {
        ball.isHidden = true
        ball.removeAllParticleSystems()
    }

    func showPreview(_ points: [SIMD3<Float>]) {
        for (i, n) in dots.enumerated() {
            if i < points.count {
                n.simdPosition = points[i]
                let k = 1 - Float(i) * 0.03
                n.simdScale = SIMD3(repeating: k)
                n.isHidden = false
            } else { n.isHidden = true }
        }
    }

    func hidePreview() { dots.forEach { $0.isHidden = true } }

    private static let dotImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { ctx in
        UIColor.white.setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 1, y: 1, width: 30, height: 30))
    }

    private static let fade: SCNParticlePropertyController = {
        let a = CAKeyframeAnimation()
        a.values = [1.0, 0.9, 0.0]
        a.keyTimes = [0, 0.45, 1]
        return SCNParticlePropertyController(animation: a)
    }()

    private static func makeTrail() -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = dotImage
        ps.birthRate = 60
        ps.particleLifeSpan = 0.45
        ps.particleSize = 0.34
        ps.particleSizeVariation = 0.1
        ps.particleVelocity = 0.3
        ps.spreadingAngle = 180
        ps.particleColor = UIColor(white: 1, alpha: 0.6)
        ps.isLightingEnabled = false
        ps.propertyControllers = [.opacity: fade]
        return ps
    }

    private func burst(at p: SIMD3<Float>, colors: [UInt32], count: CGFloat, speed: CGFloat, life: CGFloat, size: CGFloat, accel: Float, cone: Bool, direction: SIMD3<Float> = SIMD3(0, 1, 0), additive: Bool = false) {
        for hex in colors {
            let ps = SCNParticleSystem()
            ps.particleImage = World.dotImage
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
            ps.particleColor = UIColor(hex: hex)
            ps.acceleration = SCNVector3(0, accel, 0)
            ps.dampingFactor = 1.6
            ps.blendMode = additive ? .additive : .alpha
            ps.isLightingEnabled = false
            ps.propertyControllers = [.opacity: World.fade]
            scene.addParticleSystem(ps, transform: SCNMatrix4MakeTranslation(p.x, p.y, p.z))
        }
    }

    private func splash(at p: SIMD3<Float>, big: Bool) {
        burst(at: SIMD3(p.x, 0.3, p.z), colors: [0x6ab2ee, 0xffffff], count: big ? 70 : 10, speed: big ? 17 : 8, life: 1.0, size: big ? 0.7 : 0.5, accel: -28, cone: true)
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
            if p.y < 1.2 && abs(p.x) < Float(K.river) {              // sank in the river
                burst(at: SIMD3(p.x, 0.3, p.z), colors: [0x6ab2ee, 0xffffff], count: 8, speed: 7, life: 0.8, size: 0.5, accel: -28, cone: true)
                item.node.removeFromParentNode()
            } else if p.y < -3 || age > 30 {
                item.node.removeFromParentNode()
            } else if age > 7 {
                let ax = abs(p.x)
                let inside = ax > Float(K.front) - 1 && ax < Float(K.xEdge) + 1 && abs(p.z) < Float(K.gd) / 2 + 1
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

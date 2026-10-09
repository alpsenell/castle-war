import SceneKit
import Metal
import UIKit

// The castle builder's 3D canvas: the design being built stands on the left castle's plot,
// over a grid of its footprint. Taps are hit-tested here, ghost bricks preview a placement,
// and Test gravity drops the castle under real physics for a moment.

/// What a touch on the builder canvas landed on, in castle-local world units.
enum BenchHit {
    case ground(SIMD3<Float>)
    case brick(index: Int, point: SIMD3<Float>, normal: SIMD3<Float>)
}

extension World {
    /// Hides the left castle and puts a builder canvas on its plot.
    func openBench() -> BuildBench {
        // Only the merged copy is hidden: nodes with bodies must never be.
        castleViews.first?.flat?.isHidden = true
        let bench = BuildBench(arena: arena)
        bench.style = look(0).style
        scene.rootNode.addChildNode(bench.root)
        scene.rootNode.addChildNode(bench.ghostRoot)
        bench.world = self
        return bench
    }

    /// The SceneKit view showing this world, found once by walking the window hierarchy.
    func findView() -> SCNView? {
        func search(_ v: UIView) -> SCNView? {
            if let s = v as? SCNView, s.scene === scene { return s }
            for c in v.subviews { if let s = search(c) { return s } }
            return nil
        }
        for case let ws as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in ws.windows { if let s = search(w) { return s } }
        }
        return nil
    }
}

final class BuildBench {
    /// Castle-local frame: origin at the back-left ground corner, x toward the enemy, z to the right.
    let root = SCNNode()
    /// Same frame as `root`, kept apart so ghosts never take part in hit tests.
    let ghostRoot = SCNNode()
    weak var world: World?
    private weak var view: SCNView?
    private let bricksNode = SCNNode()
    private let gridNode: SCNNode
    private let ceiling: SCNNode
    private var nodes: [SCNNode] = []
    private var shown = BrickDesign()
    private var marked: Int?
    private var homes: [simd_float4x4] = []
    private(set) var testing = false
    /// The player's skin and heart gem, so the builder shows the castle as it will look in a match.
    var style = BrickStyle.plain

    static let margin: Float = 2.5

    init(arena: Arena) {
        let f = arena.forward(0), r = arena.right(0), c = arena.castleCenter(0)
        let o = SIMD3<Float>(Float(c.x - f.x * Double(K.gw) / 2 - r.x * Double(K.gd) / 2), 0, Float(c.z - f.z * Double(K.gw) / 2 - r.z * Double(K.gd) / 2))
        let m = simd_float4x4(columns: (SIMD4(Float(f.x), 0, Float(f.z), 0), SIMD4(0, 1, 0, 0), SIMD4(Float(r.x), 0, Float(r.z), 0), SIMD4(o.x, o.y, o.z, 1)))
        root.simdTransform = m
        ghostRoot.simdTransform = m
        root.name = "builder"
        gridNode = BuildBench.makeGrid()
        ceiling = BuildBench.makeCeiling()
        root.addChildNode(gridNode)
        root.addChildNode(bricksNode)
        ghostRoot.addChildNode(ceiling)
    }

    var depth: Float { Float(BK.maxX) * Float(BK.step) }
    var width: Float { Float(BK.maxZ) * Float(BK.step) }

    /// World position of a castle-local point.
    func worldPoint(_ p: SIMD3<Float>) -> SIMD3<Float> { root.simdConvertPosition(p, to: nil) }

    func remove() {
        root.removeFromParentNode()
        ghostRoot.removeFromParentNode()
        world?.castleViews.first?.flat?.isHidden = false
    }

    // MARK: Showing the design

    /// Rebuilds the bricks. Levels at or above `layer` (brick units) are hidden; `warn` bricks glow red.
    func show(_ design: BrickDesign, layer: Int, warn: [Int]) {
        guard !testing else { return }
        bricksNode.childNodes.forEach { $0.removeFromParentNode() }
        nodes = design.bricks.enumerated().map { i, b in
            let n = BuildBench.node(for: b, heart: design.heart, style: style)
            n.name = "b\(i)"
            if warn.contains(i) { n.geometry = BuildBench.tinted(b.shape, b.material, warn: true) }
            n.isHidden = b.y >= layer * BK.steps
            bricksNode.addChildNode(n)
            return n
        }
        shown = design
        marked = nil
        let top = Float(layer * BK.steps) * Float(BK.step)
        ceiling.isHidden = layer >= BK.height
        ceiling.simdPosition = SIMD3(depth / 2, top, width / 2)
    }

    /// A brick as the builder draws it: the match look, plus water for moats and a floating gem over crystals.
    static func node(for b: PlacedBrick, heart: HeartKind, style: BrickStyle = .plain) -> SCNNode {
        let n = BrickGeometry.node(for: b, heart: heart, style: style)
        if b.shape == .moat {
            let water = SCNPlane(width: CGFloat(b.extent.x) * CGFloat(BK.step) * 0.96, height: CGFloat(b.extent.z) * CGFloat(BK.step) * 0.96)
            water.materials = [Look.moatWater]
            n.geometry = water
            n.eulerAngles.x = -.pi / 2
            n.simdPosition.y = 0.07
            n.castsShadow = false
        }
        if b.material.isCrystal {
            let gem = SCNNode()
            for flip in [false, true] {
                let half = SCNNode(geometry: SCNPyramid(width: 0.55, height: 0.5, length: 0.55))
                half.geometry?.materials = [Look.heartMaterial(heart, gem: style.gem)]
                if flip { half.eulerAngles.x = .pi }
                gem.addChildNode(half)
            }
            gem.simdPosition = SIMD3(0, Float(b.extent.y) * Float(BK.step) / 2 + 0.9, 0)
            gem.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3)))
            gem.categoryBitMask = 1 << 3
            n.addChildNode(gem)
        }
        return n
    }

    /// Shows the brick under an erase finger in red; nil clears it.
    func mark(_ i: Int?) {
        guard i != marked else { return }
        if let m = marked, m < nodes.count, m < shown.bricks.count {
            let b = shown.bricks[m]
            nodes[m].geometry = b.shape == .moat ? nodes[m].geometry : BrickGeometry.geometry(b.shape, b.material, heart: shown.heart, variant: BrickGeometry.variant(of: b), style: style)
            nodes[m].opacity = 1
        }
        marked = i
        if let i, i < nodes.count {
            let b = shown.bricks[i]
            if b.shape != .moat { nodes[i].geometry = BuildBench.tinted(b.shape, b.material, warn: true) }
            nodes[i].opacity = 0.75
        }
    }

    // MARK: Ghost bricks

    func showGhost(_ bricks: [PlacedBrick], valid: Bool) {
        ghostRoot.childNodes.filter { $0 !== ceiling }.forEach { $0.removeFromParentNode() }
        for (i, b) in bricks.enumerated() {
            let n = BrickGeometry.node(for: b)
            n.geometry = BuildBench.ghost(b.shape, valid: valid)
            n.castsShadow = false
            n.renderingOrder = 10
            ghostRoot.addChildNode(n)
            // A faint shadow square on the ground or the face it rests on.
            if i == 0 {
                let e = b.extent, s = Float(BK.step)
                let pad = SCNNode(geometry: SCNPlane(width: CGFloat(Float(e.x) * s), height: CGFloat(Float(e.z) * s)))
                pad.geometry?.materials = [BuildBench.padMaterial(valid)]
                pad.eulerAngles.x = -.pi / 2
                pad.simdPosition = SIMD3((Float(b.x) + Float(e.x) / 2) * s, Float(b.y) * s + 0.08, (Float(b.z) + Float(e.z) / 2) * s)
                pad.castsShadow = false
                pad.renderingOrder = 9
                ghostRoot.addChildNode(pad)
            }
        }
    }

    func hideGhost() { ghostRoot.childNodes.filter { $0 !== ceiling }.forEach { $0.removeFromParentNode() } }

    // MARK: Hit testing

    /// What lies under a point given in window coordinates: a visible brick or the ground grid.
    func probe(_ windowPoint: CGPoint) -> BenchHit? {
        if view == nil { view = world?.findView() }
        guard let v = view else { return nil }
        let p = v.convert(windowPoint, from: nil)
        let hits = v.hitTest(p, options: [.rootNode: root, .searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true, .categoryBitMask: 1])
        for h in hits {
            var n: SCNNode? = h.node
            while let c = n, c !== root {
                if let name = c.name {
                    let local = root.simdConvertPosition(h.simdWorldCoordinates, from: nil)
                    if name == "grid" { return .ground(local) }
                    if name.hasPrefix("b"), let i = Int(name.dropFirst()), i < shown.bricks.count {
                        let normal = simd_normalize(root.simdConvertVector(h.simdWorldNormal, from: nil))
                        return .brick(index: i, point: local, normal: normal)
                    }
                }
                n = c.parent
            }
        }
        return nil
    }

    // MARK: Test gravity

    /// Lets every visible brick fall under real physics for `seconds`, then eases them all back
    /// home. Reports how many bricks moved away from where they were built.
    func testGravity(seconds: Double, done: @escaping (Int) -> Void) {
        guard !testing, let world else { done(0); return }
        testing = true
        marked = nil
        hideGhost()
        homes = nodes.map { $0.simdTransform }
        let floor = SCNNode()
        floor.name = "testFloor"
        floor.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: SCNBox(width: 400, height: 2, length: 400, chamferRadius: 0), options: nil))
        floor.physicsBody?.categoryBitMask = BuildBench.testCategory
        floor.physicsBody?.friction = 0.9
        floor.simdPosition = SIMD3(depth / 2, -1, width / 2)
        world.lockScene()
        root.addChildNode(floor)
        for (i, n) in nodes.enumerated() where !n.isHidden {
            let b = shown.bricks[i]
            guard let shape = BrickGeometry.physicsShape(b.shape) else { continue }
            let body = SCNPhysicsBody(type: .dynamic, shape: shape)
            body.mass = CGFloat(b.mass)
            body.friction = b.material == .ice ? 0.35 : 0.75
            body.rollingFriction = 0.05
            body.restitution = 0.05
            body.categoryBitMask = BuildBench.testCategory
            body.collisionBitMask = BuildBench.testCategory
            body.contactTestBitMask = 0
            n.physicsBody = body
        }
        world.unlockScene()
        world.scene.physicsWorld.speed = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            var moved = 0
            self.world?.lockScene()
            for (i, n) in self.nodes.enumerated() where n.physicsBody != nil {
                let now = n.presentation.simdTransform
                n.physicsBody = nil
                n.simdTransform = now
                let home = self.homes[i]
                let d = simd_distance(SIMD3(now.columns.3.x, now.columns.3.y, now.columns.3.z), SIMD3(home.columns.3.x, home.columns.3.y, home.columns.3.z))
                if d > 0.45 { moved += 1 }
            }
            floor.removeFromParentNode()
            self.world?.unlockScene()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.8
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (i, n) in self.nodes.enumerated() where i < self.homes.count { n.simdTransform = self.homes[i] }
                SCNTransaction.completionBlock = {
                    self.testing = false
                    done(moved)
                }
                SCNTransaction.commit()
            }
        }
    }

    /// Bodies in a gravity test touch only each other and their own floor.
    static let testCategory = 1 << 6

    // MARK: Looks

    private static var ghostCache: [Int: SCNGeometry] = [:]
    private static var tintCache: [Int: SCNGeometry] = [:]

    static func ghost(_ shape: BrickShape, valid: Bool) -> SCNGeometry {
        let key = shape.rawValue * 2 + (valid ? 1 : 0)
        if let g = ghostCache[key] { return g }
        let g = (shape == .moat ? SCNBox(width: 2, height: 0.12, length: 2, chamferRadius: 0) : BrickGeometry.geometry(shape, .stone).copy() as! SCNGeometry)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: valid ? 0x46e07a : 0xff4b3e).withAlphaComponent(0.5)
        m.emission.contents = UIColor(hex: valid ? 0x1f9d55 : 0xb3261e)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        let pulse = CABasicAnimation(keyPath: "transparency")
        pulse.fromValue = 0.95
        pulse.toValue = 0.6
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        m.addAnimation(pulse, forKey: "pulse")
        g.materials = [m]
        ghostCache[key] = g
        return g
    }

    /// The brick's own look with a red glow, for bricks with nothing under them or about to be erased.
    static func tinted(_ shape: BrickShape, _ material: BrickMaterial, warn: Bool) -> SCNGeometry {
        let key = shape.rawValue * 16 + material.rawValue
        if let g = tintCache[key] { return g }
        let g = BrickGeometry.geometry(shape, material).copy() as! SCNGeometry
        let m = (g.firstMaterial?.copy() as? SCNMaterial) ?? SCNMaterial()
        m.emission.contents = UIColor(hex: 0xff3b2f)
        m.emission.intensity = 0.55
        g.materials = [m]
        tintCache[key] = g
        return g
    }

    private static func padMaterial(_ valid: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: valid ? 0x46e07a : 0xff4b3e).withAlphaComponent(0.35)
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    /// The footprint drawn on the ground: a line every snap step, stronger every brick, and the
    /// front edge (toward the enemy) marked in red.
    private static func makeGrid() -> SCNNode {
        let s = Float(BK.step), d = Float(BK.maxX) * s, w = Float(BK.maxZ) * s, m = margin
        let ppu: CGFloat = 24
        let size = CGSize(width: CGFloat(d + 2 * m) * ppu, height: CGFloat(w + 2 * m) * ppu)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let o = CGPoint(x: CGFloat(m) * ppu, y: CGFloat(m) * ppu)
            let plot = CGRect(x: o.x, y: o.y, width: CGFloat(d) * ppu, height: CGFloat(w) * ppu)
            c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
            c.fill(plot)
            for i in 0...BK.maxX {
                let x = o.x + CGFloat(Float(i) * s) * ppu, major = i % BK.steps == 0
                c.setStrokeColor(UIColor(white: 1, alpha: major ? 0.42 : 0.16).cgColor)
                c.setLineWidth(major ? 2 : 1)
                c.move(to: CGPoint(x: x, y: plot.minY)); c.addLine(to: CGPoint(x: x, y: plot.maxY)); c.strokePath()
            }
            for i in 0...BK.maxZ {
                let y = o.y + CGFloat(Float(i) * s) * ppu, major = i % BK.steps == 0
                c.setStrokeColor(UIColor(white: 1, alpha: major ? 0.42 : 0.16).cgColor)
                c.setLineWidth(major ? 2 : 1)
                c.move(to: CGPoint(x: plot.minX, y: y)); c.addLine(to: CGPoint(x: plot.maxX, y: y)); c.strokePath()
            }
            c.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor)
            c.setLineWidth(4)
            c.stroke(plot)
            // Front edge: a red band with chevrons pointing at the enemy.
            let band = CGRect(x: plot.maxX + 6, y: plot.minY, width: ppu * 1.1, height: plot.height)
            c.setFillColor(UIColor(hex: 0xc62d1f).withAlphaComponent(0.85).cgColor)
            c.fill(band)
            c.setFillColor(UIColor.white.cgColor)
            var y = plot.minY + ppu
            while y < plot.maxY - ppu {
                c.move(to: CGPoint(x: band.minX + 6, y: y - 8)); c.addLine(to: CGPoint(x: band.maxX - 5, y: y)); c.addLine(to: CGPoint(x: band.minX + 6, y: y + 8))
                c.closePath(); c.fillPath()
                y += ppu * 3
            }
            c.setStrokeColor(UIColor(hex: 0xc62d1f).cgColor)
            c.setLineWidth(5)
            c.move(to: CGPoint(x: plot.maxX, y: plot.minY)); c.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY)); c.strokePath()
        }
        let plane = SCNPlane(width: CGFloat(d + 2 * m), height: CGFloat(w + 2 * m))
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = img
        mat.writesToDepthBuffer = false
        mat.blendMode = .alpha
        plane.materials = [mat]
        let n = SCNNode(geometry: plane)
        n.name = "grid"
        // Plane x runs along castle depth, plane y along width (image rows go from z = 0 downward).
        n.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        n.simdPosition = SIMD3(d / 2, 0.06, w / 2)
        n.castsShadow = false
        n.renderingOrder = 5
        return n
    }

    /// A pale sheet at the layer limit, so it is clear where building stops.
    private static func makeCeiling() -> SCNNode {
        let s = Float(BK.step)
        let plane = SCNPlane(width: CGFloat(Float(BK.maxX) * s), height: CGFloat(Float(BK.maxZ) * s))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: 0x8fd0ff).withAlphaComponent(0.16)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        n.castsShadow = false
        n.isHidden = true
        return n
    }
}

// MARK: - Tray icons

/// Small rendered pictures of bricks, stamps and whole castles for the builder tray, made once
/// with an offscreen SceneKit renderer and cached.
enum BrickIcons {
    private static var cache: [String: UIImage] = [:]
    private static let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    static func brick(_ shape: BrickShape, _ material: BrickMaterial) -> UIImage {
        let m = shape.materials.contains(material) || material.isCrystal ? material : .stone
        return image("b\(shape.rawValue)-\(m.rawValue)") { [PlacedBrick(shape: shape, material: m, x: 0, y: 0, z: 0)] }
    }

    static func stamp(_ stamp: Stamp, _ material: BrickMaterial) -> UIImage {
        image("s\(stamp.rawValue)-\(material.rawValue)") { stamp.bricks(x: 0, z: 0, rot: 0, material: material) }
    }

    static func castle(_ key: String, _ design: BrickDesign) -> UIImage {
        image("c" + key, ground: true) { design.bricks }
    }

    private static func image(_ key: String, ground: Bool = false, _ bricks: () -> [PlacedBrick]) -> UIImage {
        if let i = cache[key] { return i }
        let list = bricks()
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let holder = SCNNode()
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for b in list {
            let n = BuildBench.node(for: b, heart: .crystal)
            holder.addChildNode(n)
            let c = b.center, e = b.extent, s = Float(BK.step)
            let half = SIMD3(Float(e.x), Float(max(e.y, 1)), Float(e.z)) * s / 2
            let p = SIMD3(Float(c.x), Float(c.y), Float(c.z))
            lo = simd_min(lo, p - half); hi = simd_max(hi, p + half)
        }
        if list.isEmpty { lo = .zero; hi = SIMD3(Float(BK.maxX), 0.1, Float(BK.maxZ)) * Float(BK.step) }
        if ground {
            lo = simd_min(lo, .zero); hi = simd_max(hi, SIMD3(Float(BK.maxX) * Float(BK.step), 0, Float(BK.maxZ) * Float(BK.step)))
            let plot = SCNNode(geometry: SCNBox(width: CGFloat(BK.maxX) * CGFloat(BK.step), height: 0.3, length: CGFloat(BK.maxZ) * CGFloat(BK.step), chamferRadius: 0.2))
            plot.geometry?.materials = [Look.solid(0x6f9a52, roughness: 1)]
            plot.simdPosition = SIMD3(Float(BK.maxX) * Float(BK.step) / 2, -0.15, Float(BK.maxZ) * Float(BK.step) / 2)
            holder.addChildNode(plot)
        }
        let mid = (lo + hi) / 2, radius = max(simd_length(hi - lo) / 2, 0.8)
        holder.simdPosition = -mid
        scene.rootNode.addChildNode(holder)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 30
        cam.camera?.wantsHDR = false
        // From the front right and above, so the face toward the enemy and the top both show.
        let dir = simd_normalize(SIMD3<Float>(1.0, 0.85, 0.75))
        cam.simdPosition = dir * radius / sin(15 * .pi / 180) * 1.02
        cam.simdLook(at: .zero)
        scene.rootNode.addChildNode(cam)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1400
        sun.simdOrientation = simd_quatf(angle: -0.9, axis: simd_normalize(SIMD3(1, 0.2, -0.6)))
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 650
        scene.rootNode.addChildNode(fill)

        renderer.scene = scene
        renderer.pointOfView = cam
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: 132, height: 132), antialiasingMode: .multisampling4X)
        cache[key] = img
        return img
    }

    /// Drops cached castle pictures (presets may change between builds of the tray).
    static func forgetCastles() { cache = cache.filter { !$0.key.hasPrefix("c") } }
}

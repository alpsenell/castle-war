import SceneKit

// The physics side of a shot. Between shots every brick is a static body and each castle is drawn
// as one flattened copy. When a ball touches down, the castles near it wake up as dynamic bodies,
// a real cannonball takes over from the free flight, and collision impulses crack and break bricks
// into fragments. Once everything has come to rest (or `K.settleSeconds` have passed) the castles
// freeze again and the result goes back to the rules as a `SettleReport`.

/// A cannonball with a body, after the free flight has handed over.
final class BallNode: SCNNode {
    /// Bricks a piercer still goes straight through.
    var pierce = 0
    /// Velocity at the last frame, to carry a piercer on through what it breaks.
    var lastVelocity = SIMD3<Float>(0, 0, 0)
    var born = 0.0
}

/// Contacts arrive on SceneKit's render thread; they wait here for the next frame on the main thread.
final class ContactSink: NSObject, SCNPhysicsContactDelegate {
    struct Knock {
        let brick: BrickNode
        let impulse: Float
        let ball: BallNode?
    }
    private let lock = NSLock()
    private var pending: [Knock] = []
    /// Only a shot being played breaks anything.
    var listening = false

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) { note(contact) }
    func physicsWorld(_ world: SCNPhysicsWorld, didUpdate contact: SCNPhysicsContact) { note(contact) }

    private func note(_ c: SCNPhysicsContact) {
        guard listening else { return }
        let impulse = Float(c.collisionImpulse)
        let a = c.nodeA, b = c.nodeB
        let ball = (a as? BallNode) ?? (b as? BallNode)
        guard impulse > 0.2 || ball != nil else { return }
        var found: [Knock] = []
        for n in [a, b] {
            guard let brick = n as? BrickNode, brick.awake else { continue }
            if ball != nil || impulse >= brick.threshold { found.append(Knock(brick: brick, impulse: impulse, ball: ball)) }
        }
        guard !found.isEmpty else { return }
        lock.lock()
        pending += found
        lock.unlock()
    }

    func drain() -> [Knock] {
        lock.lock()
        defer { lock.unlock() }
        let out = pending
        pending.removeAll(keepingCapacity: true)
        return out
    }
}

/// State of the shot being played, and of the fragments it left.
struct ShotPlay {
    var active = false
    /// Simulated seconds since the ball touched down, and how long everything has been still.
    var t = 0.0, quiet = 0.0
    var timeout = K.settleSeconds
    var done: ((SettleReport) -> Void)?
    /// Castles whose bricks are dynamic now.
    var awake: [Int] = []
    var balls: [BallNode] = []
    var chips: [(node: SCNNode, born: Double, life: Double)] = []
    /// Heaviest ball of the shot and how strongly the castle it lands on is shielded.
    var shielded = Set<Int>()
    var frame = 0
}

extension World: BrickPhysics {
    // MARK: Castles

    func loadCastles(_ designs: [BrickDesign], poses: [CastleSnapshot]?) {
        lockScene(); defer { unlockScene() }
        for v in castleViews { v.root.removeFromParentNode(); v.flat?.removeFromParentNode(); v.gems.forEach { $0.anchor.removeFromParentNode() } }
        castleViews = designs.enumerated().map { i, d in
            makeCastle(i, design: d, poses: poses.flatMap { i < $0.count && $0[i].poses.count == d.bricks.count ? $0[i] : nil } ?? CastleSnapshot(design: d))
        }
    }

    func makeCastle(_ side: Int, design: BrickDesign, poses: CastleSnapshot) -> CastleBricks {
        let v = CastleBricks(side: side, design: design, frame: CastleFrame(seat: side, arena: arena))
        v.nodes = design.bricks.enumerated().map { i, b in
            let pose = poses.poses[i]
            guard !pose.broken else { return nil }
            let n = BrickNode(castle: side, index: i, brick: b, hp: Int(pose.hp), maxHp: design.hp(b))
            let w = v.worldPose(pose)
            n.simdPosition = w.p
            n.simdOrientation = w.q
            if b.shape.isDecal { n.castsShadow = false } else { n.physicsBody = body(for: n, dynamic: false) }
            v.root.addChildNode(n)
            return n
        }
        for (i, b) in design.bricks.enumerated() where b.material.isCrystal {
            if gone(v, i) { v.lostCrystals.insert(i) } else { addGem(v, brick: i) }
        }
        for n in v.nodes.compactMap({ $0 }) { dress(n, in: v) }
        if let top = v.nodes.compactMap({ $0 }).filter({ $0.brick.shape.isTop || $0.brick.shape == .coneRoof }).max(by: { $0.brick.y < $1.brick.y })
            ?? v.nodes.compactMap({ $0 }).max(by: { $0.brick.y + $0.brick.extent.y < $1.brick.y + $1.brick.extent.y }) {
            addFlag(to: top, side: side)
        }
        scene.rootNode.addChildNode(v.root)
        flatten(v)
        return v
    }

    /// Geometry for a brick as it is now: cracked iron and found-out decoys look different.
    private func dress(_ n: BrickNode, in v: CastleBricks) {
        let b = n.brick
        let wear: BrickGeometry.Wear = b.material == .iron && n.hp < n.maxHp ? .cracked : b.material.isCrystal && v.lostCrystals.contains(n.index) ? .revealed : .whole
        n.geometry = BrickGeometry.geometry(b.shape, b.material, heart: v.design.heart, variant: BrickGeometry.variant(of: b), wear: wear)
    }

    /// A heart or decoy that is broken or knocked well away from its spot.
    private func gone(_ v: CastleBricks, _ i: Int) -> Bool {
        guard let n = v.nodes[i] else { return true }
        return simd_distance(v.local(spot(n)), v.home.poses[i].p) > Float(K.heartReach)
    }

    private func body(for n: BrickNode, dynamic: Bool) -> SCNPhysicsBody {
        let body = SCNPhysicsBody(type: dynamic ? .dynamic : .static, shape: BrickGeometry.physicsShape(n.brick.shape))
        if dynamic {
            // Hearts and decoys sit heavy, so a glancing blow cracks them rather than flinging them away.
            body.mass = CGFloat(n.brick.mass * (n.brick.material.isCrystal ? 2 : 1))
            body.contactTestBitMask = Phys.ground | Phys.brick | Phys.ball
        }
        body.friction = n.brick.material == .ice ? 0.35 : n.brick.material.isCrystal ? 1 : 0.75
        body.rollingFriction = 0.05
        body.restitution = 0.05
        body.damping = 0.06
        body.angularDamping = 0.25
        body.categoryBitMask = Phys.brick
        body.collisionBitMask = Phys.ground | Phys.brick | Phys.ball | Phys.chip
        return body
    }

    /// Draws a resting castle as one merged copy, which is far cheaper than a node per brick.
    /// The bricks stay in the scene for their bodies; only the camera and the sun stop seeing
    /// them. (Hiding nodes with bodies, or changing bodies under hidden nodes, upsets SceneKit's physics.)
    func flatten(_ v: CastleBricks) {
        v.flat?.removeFromParentNode()
        drawBricks(v, true)
        let f = v.root.flattenedClone()
        f.physicsBody = nil
        scene.rootNode.addChildNode(f)
        v.flat = f
        drawBricks(v, false)
    }

    private func unflatten(_ v: CastleBricks) {
        v.flat?.removeFromParentNode()
        v.flat = nil
        drawBricks(v, true)
    }

    private func drawBricks(_ v: CastleBricks, _ on: Bool) {
        v.root.enumerateHierarchy { n, _ in
            guard n !== v.root else { return }
            n.categoryBitMask = on ? 1 : World.unseen
            n.castsShadow = on && !((n as? BrickNode)?.brick.shape.isDecal ?? false)
        }
    }

    /// Where a brick is: a sleeping one's own position, a woken one's simulated position.
    private func spot(_ n: BrickNode) -> SIMD3<Float> { n.awake ? n.presentation.simdWorldPosition : n.simdWorldPosition }

    private func addGem(_ v: CastleBricks, brick i: Int) {
        let anchor = SCNNode(), n = SCNNode()
        let crystal = Look.heartMaterial(v.design.heart)
        for flip in [false, true] {
            let half = SCNNode(geometry: SCNPyramid(width: 1.1, height: 1.0, length: 1.1))
            half.geometry?.materials = [crystal]
            if flip { half.eulerAngles.x = .pi }
            n.addChildNode(half)
        }
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(hex: Look.heartColors(v.design.heart).glow)
        light.intensity = 320
        light.attenuationStartDistance = 0.5
        light.attenuationEndDistance = 5
        n.light = light
        n.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4)))
        n.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.4, z: 0, duration: 1.1), .moveBy(x: 0, y: -0.4, z: 0, duration: 1.1)])))
        anchor.addChildNode(n)
        scene.rootNode.addChildNode(anchor)
        v.gems.append((anchor, i))
        placeGems(v)
    }

    private func placeGems(_ v: CastleBricks) {
        for g in v.gems {
            guard let n = v.nodes[g.brick] else { continue }
            let up = Float(n.brick.shape.size.y) * Float(BK.step) / 2
            g.anchor.simdPosition = spot(n) + SIMD3(0, up + 1.8, 0)
        }
    }

    /// A team banner on the castle's highest brick; it falls with it.
    private func addFlag(to n: BrickNode, side: Int) {
        let top = Float(n.brick.shape.size.y) * Float(BK.step) / 2
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 3.2))
        pole.geometry?.materials = [Look.solid(0x3a3d40, roughness: 0.4, metal: 1)]
        pole.position = SCNVector3(0, top + 1.5, 0)
        let cloth = SCNNode(geometry: SCNBox(width: 0.05, height: 1.1, length: 1.9, chamferRadius: 0))
        cloth.geometry?.materials = [Look.solid(Look.accent[side % Look.accent.count], roughness: 0.9)]
        cloth.position = SCNVector3(0, top + 2.5, 0.98)
        n.addChildNode(pole)
        n.addChildNode(cloth)
    }

    // MARK: Playing a shot

    func simulate(_ impact: ShotImpact, timeout: Double, done: @escaping (SettleReport) -> Void) {
        lockScene(); defer { unlockScene() }
        if play.active { finishPlay() }
        play.active = true
        play.t = 0; play.quiet = 0; play.frame = 0
        play.timeout = timeout
        play.done = done
        play.awake = []
        play.balls = []
        let p = impact.point.f
        let near = castleViews.indices.filter { i in
            let l = castleViews[i].local(p)
            return l.x > -9 && l.x < Float(K.gw) + 9 && l.z > -9 && l.z < Float(K.gd) + 9 && l.y < Float(BK.maxY) + 9
        }
        let hit = near.min { simd_distance(castleViews[$0].world(SIMD3(Float(K.gw) / 2, 0, Float(K.gd) / 2)), p) < simd_distance(castleViews[$1].world(SIMD3(Float(K.gw) / 2, 0, Float(K.gd) / 2)), p) }
        for i in near { wake(i, shielded: impact.shielded.indices.contains(i) && impact.shielded[i]) }
        contacts.listening = true
        var mass: Float = K.ballMass * Float(impact.weight)
        if impact.mega { mass *= Float(K.megaBoost) }
        if impact.crit { mass *= Float(K.critBoost) }
        if impact.ammo == .piercer { mass *= 1.8 }
        if let h = hit, impact.shielded.indices.contains(h), impact.shielded[h] { mass *= Float(K.shieldFactor) }
        let v = impact.velocity.f, dir = simd_length(v) > 0.01 ? simd_normalize(v) : SIMD3<Float>(0, -1, 0)
        spawnBall(at: p - dir * 0.2, velocity: v, mass: mass, pierce: impact.ammo == .piercer ? K.pierce : 0)
        for e in impact.extraBalls { spawnBall(at: e.point.f, velocity: e.velocity.f, mass: mass * 0.75, pierce: 0) }
        if impact.mega { shockwave(at: p, radius: 4.8, strength: 9) }
        #if DEBUG
        print("PLAY simulate at \(p) v=\(v) near=\(near) mass=\(mass)")
        #endif
    }

    /// Turns a castle's bricks into dynamic bodies for the shot.
    private func wake(_ c: Int, shielded: Bool) {
        let v = castleViews[c]
        guard !play.awake.contains(c) else { return }
        play.awake.append(c)
        unflatten(v)
        for case let n? in v.nodes where !n.brick.shape.isDecal {
            n.awake = true
            n.threshold = Float(n.brick.material.breakImpulse * n.brick.mass * K.breakScale)
            n.physicsBody = body(for: n, dynamic: true)
        }
    }

    /// Freezes a castle where its bricks came to rest.
    private func freeze(_ c: Int) {
        let v = castleViews[c]
        for case let n? in v.nodes where n.awake {
            n.simdTransform = n.presentation.simdTransform
            n.awake = false
            n.physicsBody = body(for: n, dynamic: false)
        }
        placeGems(v)
        flatten(v)
    }

    private func spawnBall(at p: SIMD3<Float>, velocity: SIMD3<Float>, mass: Float, pierce: Int) {
        let b = BallNode()
        let s = SCNSphere(radius: CGFloat(K.ballR))
        s.segmentCount = 20
        s.materials = ball.geometry?.materials ?? []
        b.geometry = s
        b.simdPosition = p
        b.simdScale = ball.simdScale
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: CGFloat(K.ballR)), options: nil))
        body.mass = CGFloat(mass)
        body.restitution = 0.15
        body.friction = 0.5
        body.rollingFriction = 0.2
        body.damping = 0.05
        body.angularDamping = 0.4
        body.categoryBitMask = Phys.ball
        body.collisionBitMask = Phys.ground | Phys.brick
        body.contactTestBitMask = Phys.brick
        b.physicsBody = body
        b.castsShadow = false    // it can bounce far off the field; see the note on fragments
        b.pierce = pierce
        b.lastVelocity = velocity
        b.born = clock
        if let trail = ball.particleSystems?.first?.copy() as? SCNParticleSystem { b.addParticleSystem(trail) }
        looseRoot.addChildNode(b)
        b.physicsBody?.velocity = SCNVector3(velocity.x, velocity.y, velocity.z)
        play.balls.append(b)
    }

    /// A push outward from a mega shot's landing.
    private func shockwave(at p: SIMD3<Float>, radius: Float, strength: Float) {
        for c in play.awake {
            for case let n? in castleViews[c].nodes where n.awake {
                let d = n.simdWorldPosition - p, dist = simd_length(d)
                guard dist < radius, let body = n.physicsBody else { continue }
                let dir = simd_normalize(d + SIMD3(0, 0.8, 0))
                let k = strength * Float(n.brick.mass) * (1 - dist / radius)
                body.applyForce(SCNVector3(dir.x * k, dir.y * k, dir.z * k), asImpulse: true)
            }
        }
        burst(at: p, colors: [0xd9c9a8, 0xb5a98f], count: 90, speed: 16, life: 1.4, size: 1.8, accel: 1, cone: false, grow: 2.2, alpha: 0.45)
    }

    /// Plays the shot forward one frame: breaks what was struck hard enough, watches the hearts,
    /// and ends the shot once nothing moves.
    func stepPlay(dt: TimeInterval) {
        lockScene(); defer { unlockScene() }
        if play.frame >= 4 { for c in play.awake where !castleViews[c].gems.isEmpty { placeGems(castleViews[c]) } }
        ageChips()
        for k in contacts.drain() { knock(k) }
        if play.frame >= 4 { for b in play.balls { if let v = b.physicsBody?.velocity { b.lastVelocity = SIMD3(v.x, v.y, v.z) } } }
        guard play.active else { return }
        play.t += dt * Double(scene.physicsWorld.speed)
        #if DEBUG
        // A node's presentation must not be read before it has been drawn once: SceneKit then
        // stops simulating its body. Freshly woken bricks and new balls get a few frames first.
        play.frame += 1
        if play.frame < 4 { return }
        #endif
        var moving: Float = 0
        for c in play.awake {
            let v = castleViews[c]
            for case let n? in v.nodes where n.awake {
                let p = n.presentation.simdWorldPosition
                if p.y < -4 || (p.y < 0.8 && arena.isWater(Double(p.x), Double(p.z))) {
                    if p.y > -4 { splash(at: p, big: false) }
                    shatter(n, quiet: true)
                    continue
                }
                if let b = n.physicsBody {
                    let s = SIMD3<Float>(b.velocity.x, b.velocity.y, b.velocity.z), w = b.angularVelocity
                    moving = max(moving, simd_length(s), abs(w.w) * 0.6)
                }
            }
            watchCrystals(v)
        }
        for b in play.balls {
            let p = b.presentation.simdWorldPosition
            if p.y < 0.9 && arena.isWater(Double(p.x), Double(p.z)) && b.parent != nil {
                splash(at: p, big: false)
                b.removeFromParentNode()
                continue
            }
            if b.parent != nil, play.t < 2.5, let v = b.physicsBody?.velocity { moving = max(moving, simd_length(SIMD3<Float>(v.x, v.y, v.z)) * 0.5) }
        }
        play.quiet = moving < 0.35 ? play.quiet + dt * Double(scene.physicsWorld.speed) : 0
        if (play.t > 1.2 && play.quiet > 0.45) || play.t >= play.timeout { finishPlay() }
    }

    private func finishPlay() {
        guard play.active else { return }
        play.active = false
        contacts.listening = false
        for c in play.awake { watchCrystals(castleViews[c]); freeze(c) }
        for b in play.balls where b.parent != nil {
            b.physicsBody = nil
            b.runAction(.sequence([.wait(duration: 0.4), .scale(to: 0.01, duration: 0.35), .removeFromParentNode()]))
        }
        play.balls = []
        play.awake = []
        _ = contacts.drain()
        let report = SettleReport(snapshots: castleViews.map { $0.snapshot })
        #if DEBUG
        print("PLAY settled t=\(play.t) broken=\(castleViews.map { $0.nodes.filter { $0 == nil }.count })")
        #endif
        let done = play.done
        play.done = nil
        done?(report)
    }

    /// Ends whatever is being played without reporting it.
    func endPlay() {
        lockScene(); defer { unlockScene() }
        play.active = false
        play.done = nil
        contacts.listening = false
        for b in play.balls { b.removeFromParentNode() }
        for c in chipsAndAwake() { freeze(c) }
        play.balls = []
        play.awake = []
        for ch in play.chips { ch.node.removeFromParentNode() }
        play.chips = []
        _ = contacts.drain()
    }

    private func chipsAndAwake() -> [Int] { play.awake.filter { $0 < castleViews.count } }

    /// Hearts and decoys knocked off their spot or broken: the gem over them goes.
    private func watchCrystals(_ v: CastleBricks) {
        for (i, b) in v.design.bricks.enumerated() where b.material.isCrystal && !v.lostCrystals.contains(i) && gone(v, i) {
            v.lostCrystals.insert(i)
            let glow = Look.heartColors(v.design.heart).glow
            if let g = v.gems.firstIndex(where: { $0.brick == i }) {
                let p = v.gems[g].anchor.presentation.simdWorldPosition
                v.gems.remove(at: g).anchor.removeFromParentNode()
                if b.material == .heart {
                    burst(at: p, colors: [glow, 0xffffff, 0xffb3d1], count: 160, speed: 22, life: 1.2, size: 0.9, accel: -9, cone: false, additive: true)
                    flash(at: p, strength: 5200)
                } else {
                    burst(at: p, colors: [0x8d8794, 0xc9c3cf], count: 50, speed: 7, life: 1.4, size: 1.6, accel: 2, cone: false, grow: 1.8, alpha: 0.6)
                }
            }
            if let n = v.nodes[i] { dress(n, in: v) }
            onCrystalLost?(v.side, i)
        }
    }

    // MARK: Breaking

    private func knock(_ k: ContactSink.Knock) {
        let n = k.brick
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-knocks") { print("KNOCK \(n.brick.material) \(n.brick.shape) imp=\(k.impulse) thr=\(n.threshold) ball=\(k.ball != nil)") }
        #endif
        guard n.awake, n.parent != nil, n.hp > 0, castleViews.indices.contains(n.castle), castleViews[n.castle].nodes[n.index] === n else { return }
        if let ball = k.ball {
            onKnock?(k.impulse)
            if ball.pierce > 0, ball.parent != nil {
                ball.pierce -= 1
                let v = ball.lastVelocity * 0.85
                ball.physicsBody?.velocity = SCNVector3(v.x, v.y, v.z)
                n.hp = 0
                shatter(n)
                return
            }
        }
        // One knock takes one hit point; a heart or decoy loses at most one per blow.
        guard k.impulse >= n.threshold, clock - n.lastHit > (n.brick.material.isCrystal ? 1.2 : 0.2) else { return }
        n.lastHit = clock
        n.hp -= 1
        if n.hp <= 0 { shatter(n) } else { crack(n) }
    }

    /// A hit that leaves the brick standing: iron shows the crack, crystals flare.
    private func crack(_ n: BrickNode) {
        let v = castleViews[n.castle], p = spot(n)
        dress(n, in: v)
        if n.brick.material.isCrystal {
            let glow = Look.heartColors(v.design.heart).glow
            burst(at: p, colors: [glow, 0xffffff], count: 40, speed: 8, life: 0.7, size: 0.6, accel: -6, cone: false, additive: true)
        } else {
            burst(at: p, colors: [0xffc36b, 0xffffff], count: 24, speed: 9, life: 0.35, size: 0.3, accel: -14, cone: false, additive: true)
            burst(at: p, colors: [0x5c6166, 0x8a8f94], count: 10, speed: 3, life: 1.2, size: 1.2, accel: 1, cone: false, grow: 1.6, alpha: 0.5)
        }
        onBreak?(n.brick.material == .iron ? .iron : n.brick.material)
    }

    /// Breaks a brick into a few chunks that tumble and fade, with dust in its material's colours.
    func shatter(_ n: BrickNode, quiet: Bool = false) {
        let v = castleViews[n.castle]
        guard v.nodes[n.index] === n else { return }
        v.nodes[n.index] = nil
        let live = n.awake ? n.presentation : n
        let t = live.simdWorldTransform, q = live.simdWorldOrientation
        let vel = n.awake ? n.physicsBody.map { SIMD3<Float>($0.velocity.x, $0.velocity.y, $0.velocity.z) } ?? .zero : .zero
        n.removeFromParentNode()
        n.hp = 0
        let b = n.brick, m = b.material
        let p = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        if !quiet { dust(m, at: p, heart: v.design.heart) }
        guard !b.shape.isDecal else { return }
        let s = b.shape.size, k = Float(BK.step)
        let size = SIMD3(Float(s.x), Float(s.y), Float(s.z)) * k * SIMD3(1, Float(b.shape.boxes.count == 1 ? 1 : 0.6), 1)
        let axis = size.x >= size.y && size.x >= size.z ? 0 : size.y >= size.z ? 1 : 2
        let long = size[axis]
        var pieces = long >= 3.5 ? 4 : long >= 2.5 ? 3 : 2
        if m == .ice { pieces = min(4, pieces + 1) }
        let shrink: Float = m == .ice ? 0.7 : 0.86
        let mass = Float(b.mass) / Float(pieces)
        for i in 0..<pieces {
            var piece = size * shrink * Float.random(in: 0.85...1.05)
            piece[axis] = long / Float(pieces) * 0.9
            if m == .ice { piece *= SIMD3(Float.random(in: 0.6...1), Float.random(in: 0.6...1), Float.random(in: 0.6...1)) }
            var off = SIMD3<Float>(0, 0, 0)
            off[axis] = (Float(i) + 0.5) / Float(pieces) * long - long / 2
            let world = t * SIMD4(off.x, off.y, off.z, 1)
            let geo = BrickGeometry.fragment(size: simd_max(piece, SIMD3(repeating: 0.25)), material: m, heart: v.design.heart, variant: BrickGeometry.variant(of: b))
            let chip = SCNNode(geometry: geo)
            // Fragments fly far and fast; as shadow casters they would stretch the sun's shadow
            // map over a much larger area and blur every shadow until they fade.
            chip.castsShadow = false
            chip.simdPosition = SIMD3(world.x, world.y, world.z)
            chip.simdOrientation = q
            let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: geo, options: [.type: SCNPhysicsShape.ShapeType.boundingBox]))
            body.mass = CGFloat(max(0.05, mass))
            body.friction = 0.7
            body.restitution = m == .ice ? 0.2 : 0.08
            body.categoryBitMask = Phys.chip
            body.collisionBitMask = Phys.ground | Phys.brick
            body.contactTestBitMask = 0
            let outward = simd_normalize(SIMD3(world.x, world.y, world.z) - p + SIMD3(0, 0.3, 0))
            let kick = outward * Float.random(in: 1.5...3.5) + SIMD3(Float.random(in: -1...1), Float.random(in: 0.5...2.5), Float.random(in: -1...1))
            chip.physicsBody = body
            looseRoot.addChildNode(chip)
            body.velocity = SCNVector3(vel.x + kick.x, vel.y + kick.y, vel.z + kick.z)
            body.angularVelocity = SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: 2...7))
            play.chips.append((chip, clock, Double.random(in: 2.2...3.4)))
        }
        while play.chips.count > K.maxChips { play.chips.removeFirst().node.removeFromParentNode() }
        if !quiet { onBreak?(m) }
    }

    private func dust(_ m: BrickMaterial, at p: SIMD3<Float>, heart: HeartKind) {
        switch m {
        case .wood:
            burst(at: p, colors: [0x8a5a33, 0xc49a6c], count: 40, speed: 9, life: 0.9, size: 0.32, accel: -18, cone: false)
            burst(at: p, colors: [0xb39b7c], count: 14, speed: 2.5, life: 1.6, size: 1.6, accel: 0.6, cone: false, grow: 1.8, alpha: 0.35)
        case .stone:
            burst(at: p, colors: [0x8d8f8c, 0x6f706d], count: 36, speed: 8, life: 0.9, size: 0.4, accel: -20, cone: false)
            burst(at: p, colors: [0xb5b2aa, 0x9a978f], count: 22, speed: 3.5, life: 2.0, size: 2.4, accel: 1, cone: false, grow: 2, alpha: 0.45)
        case .ice:
            burst(at: p, colors: [0xe6f7ff, 0xffffff], count: 60, speed: 11, life: 0.8, size: 0.35, accel: -22, cone: false, additive: true)
            burst(at: p, colors: [0xcfeeff], count: 16, speed: 2.5, life: 1.4, size: 1.4, accel: 0.4, cone: false, grow: 1.7, alpha: 0.35)
        case .iron:
            burst(at: p, colors: [0xffc36b, 0xffffff], count: 46, speed: 12, life: 0.5, size: 0.25, accel: -16, cone: false, additive: true)
            burst(at: p, colors: [0x55595e], count: 14, speed: 3, life: 1.6, size: 1.8, accel: 1, cone: false, grow: 1.8, alpha: 0.45)
        case .heart, .decoy:
            let glow = Look.heartColors(heart).glow
            burst(at: p, colors: [glow, 0xffffff], count: 70, speed: 13, life: 0.9, size: 0.5, accel: -10, cone: false, additive: true)
        }
    }

    private func ageChips() {
        guard !play.chips.isEmpty else { return }
        play.chips.removeAll { c in
            if c.node.parent == nil { return true }
            guard clock - c.born > c.life else { return false }
            c.node.physicsBody = nil
            c.node.runAction(.sequence([.group([.scale(to: 0.05, duration: 0.5), .fadeOut(duration: 0.5)]), .removeFromParentNode()]))
            return true
        }
    }

    // MARK: Authoritative poses

    func adopt(_ snapshots: [CastleSnapshot], blend: Double) {
        lockScene(); defer { unlockScene() }
        for (c, snap) in snapshots.enumerated() where c < castleViews.count {
            let v = castleViews[c]
            guard snap.poses.count == v.nodes.count else { continue }
            var changed = false
            for i in snap.poses.indices {
                let pose = snap.poses[i], b = v.design.bricks[i]
                if pose.broken {
                    if let n = v.nodes[i] { shatter(n, quiet: true); changed = true }
                    continue
                }
                let w = v.worldPose(pose)
                if let n = v.nodes[i] {
                    if n.hp != Int(pose.hp) { n.hp = Int(pose.hp); dress(n, in: v); changed = true }
                    let dp = simd_distance(n.simdPosition, w.p), dq = abs(simd_dot(n.simdOrientation.vector, w.q.vector))
                    guard dp > 0.03 || dq < 0.9995 else { continue }
                    changed = true
                    move(n, to: w, over: blend, in: v)
                } else {
                    let n = BrickNode(castle: c, index: i, brick: b, hp: Int(pose.hp), maxHp: v.design.hp(b))
                    n.simdPosition = w.p
                    n.simdOrientation = w.q
                    dress(n, in: v)
                    if !b.shape.isDecal { n.physicsBody = body(for: n, dynamic: false) }
                    v.root.addChildNode(n)
                    v.nodes[i] = n
                    if b.material.isCrystal, v.lostCrystals.contains(i), !gone(v, i) {
                        v.lostCrystals.remove(i)
                        addGem(v, brick: i)
                    }
                    if blend > 0 {
                        n.opacity = 0
                        n.runAction(.fadeIn(duration: blend))
                    }
                    changed = true
                }
            }
            if changed {
                unflatten(v)
                DispatchQueue.main.asyncAfter(deadline: .now() + blend + 0.1) { [weak self, weak v] in
                    guard let self, let v, !self.play.awake.contains(v.side), self.castleViews.contains(where: { $0 === v }) else { return }
                self.lockScene(); defer { self.unlockScene() }
                    self.placeGems(v)
                    self.flatten(v)
                }
            }
        }
    }

    private func move(_ n: BrickNode, to w: (p: SIMD3<Float>, q: simd_quatf), over blend: Double, in v: CastleBricks) {
        n.physicsBody = nil
        guard blend > 0 else {
            n.simdPosition = w.p
            n.simdOrientation = w.q
            n.physicsBody = body(for: n, dynamic: false)
            return
        }
        let p0 = n.simdPosition, q0 = n.simdOrientation
        n.runAction(.sequence([
            .customAction(duration: blend) { node, t in
                let k = Float(t / CGFloat(blend)), e = k * k * (3 - 2 * k)
                node.simdPosition = simd_mix(p0, w.p, SIMD3(repeating: e))
                node.simdOrientation = simd_slerp(q0, w.q, e)
            },
            .run { [weak self] node in
                guard let self, let n = node as? BrickNode else { return }
                n.simdPosition = w.p
                n.simdOrientation = w.q
                n.physicsBody = self.body(for: n, dynamic: false)
            },
        ]))
    }
}

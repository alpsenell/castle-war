import SceneKit

// Geometry and looks of single bricks, shared by the match scene and the builder. Meshes are
// cached per shape and material and looks per material, so every brick of a kind shares one
// SCNGeometry.

enum BrickGeometry {
    /// How a brick has been knocked about: iron shows a crack after its first hit, a decoy that
    /// has been found out goes dull.
    enum Wear: Int { case whole = 0, cracked, revealed }

    private static var meshes: [Int: SCNGeometry] = [:]
    private static var cache: [Int: SCNGeometry] = [:]
    private static var looks: [Int: SCNMaterial] = [:]
    private static var shapes: [Int: SCNPhysicsShape] = [:]
    private static var fragments: [Int: SCNGeometry] = [:]

    /// Stone and timber come in a few shades so a wall does not look printed.
    static let variants = 3

    /// Geometry for a brick at rotation 0, centred on its own origin, in world units.
    static func geometry(_ shape: BrickShape, _ material: BrickMaterial, heart: HeartKind = .crystal, variant: Int = 0, wear: Wear = .whole) -> SCNGeometry {
        let v = material == .stone || material == .wood ? variant % variants : 0
        let key = ((shape.rawValue * 8 + material.rawValue) * 8 + heart.rawValue) * 16 + v * 4 + wear.rawValue
        if let g = cache[key] { return g }
        let g = mesh(shape, material).copy() as! SCNGeometry
        g.materials = [look(material, heart: heart, variant: v, wear: wear, roof: shape == .coneRoof || shape == .pyramidRoof, decal: shape.isDecal)]
        cache[key] = g
        return g
    }

    /// A node for a placed brick, positioned and rotated castle-locally.
    static func node(for b: PlacedBrick, heart: HeartKind = .crystal) -> SCNNode {
        let n = SCNNode(geometry: geometry(b.shape, b.material, heart: heart, variant: variant(of: b)))
        let c = b.center
        n.simdPosition = SIMD3(Float(c.x), Float(c.y), Float(c.z))
        n.simdOrientation = simd_quatf(angle: Float(b.rot) * .pi / 2, axis: SIMD3(0, 1, 0))
        if b.shape.isDecal { n.castsShadow = false }
        return n
    }

    /// The shade a brick gets, fixed by where it sits.
    static func variant(of b: PlacedBrick) -> Int { abs(b.x &* 7 &+ b.y &* 13 &+ b.z &* 5) % variants }

    // MARK: Looks

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

    private static let stoneShades: [UInt32] = [0xbfc0bd, 0xcfc3a6, 0xadb4a8]
    private static let woodShades: [UInt32] = [0xa0703f, 0x8b5b34, 0xb08250]

    /// The material of a brick. Hearts and decoys share the castle's heart look until a decoy is found out.
    static func look(_ m: BrickMaterial, heart: HeartKind = .crystal, variant: Int = 0, wear: Wear = .whole, roof: Bool = false, decal: Bool = false) -> SCNMaterial {
        let key = (((m.rawValue * 8 + heart.rawValue) * 4 + variant) * 4 + wear.rawValue) * 4 + (roof ? 1 : 0) + (decal ? 2 : 0)
        if let hit = looks[key] { return hit }
        let mat: SCNMaterial
        if decal {
            mat = Look.moatWater
        } else if roof && m != .ice {
            mat = textured(Textures.tint(Textures.shingles.albedo, "shingles", m == .stone ? 0x667280 : 0x9a4f33), normal: Textures.shingles.normal, roughness: 0.7, bump: 1.1)
        } else {
            switch m {
            case .wood:
                mat = textured(Textures.tint(Textures.timber.albedo, "timber", woodShades[variant % woodShades.count]), normal: Textures.timber.normal, roughness: 0.78, bump: 0.8)
            case .stone:
                mat = textured(Textures.tint(Textures.ashlar.albedo, "ashlar", stoneShades[variant % stoneShades.count]), normal: Textures.ashlar.normal, roughness: 0.9, bump: 1)
            case .ice:
                mat = textured(Textures.tint(Textures.ice.albedo, "ice", 0xe2f4ff), normal: Textures.ice.normal, roughness: 0.06, bump: 0.6)
                mat.transparency = 0.78
                mat.transparencyMode = .dualLayer
                mat.emission.contents = UIColor(hex: 0x2a6f9a)
                mat.emission.intensity = 0.18
                // Brighter and more solid at grazing angles, the way thick ice catches the sky.
                mat.shaderModifiers = [.fragment: """
                    float rim = pow(1.0 - clamp(dot(_surface.normal, _surface.view), 0.0, 1.0), 2.5);
                    _output.color.rgb += rim * vec3(0.32, 0.42, 0.5);
                    """]
            case .iron:
                let t = Textures.ironPlate(cracked: wear == .cracked)
                mat = textured(Textures.tint(t.albedo, wear == .cracked ? "iron-cracked" : "iron", wear == .cracked ? 0x4c5157 : 0x707880), normal: t.normal,
                               roughness: wear == .cracked ? 0.8 : 0.42, metal: wear == .cracked ? 0.35 : 0.75, bump: 1.2)
            case .heart:
                mat = wear == .revealed ? Look.solid(0x4a3a44, roughness: 0.6) : Look.heartMaterial(heart)
            case .decoy:
                mat = wear == .revealed ? Look.solid(0x77707c, roughness: 0.55) : Look.heartMaterial(heart)
            }
        }
        looks[key] = mat
        return mat
    }

    // MARK: Meshes

    private static func mesh(_ shape: BrickShape, _ material: BrickMaterial) -> SCNGeometry {
        let key = shape.rawValue * 8 + material.rawValue
        if let g = meshes[key] { return g }
        let s = shape.size, k = Float(BK.step)
        let h = SIMD3(Float(s.x), Float(s.y), Float(s.z)) * (k / 2)
        let bevel: Float = material == .stone ? 0.11 : material == .wood ? 0.06 : material == .iron ? 0.05 : 0.08
        // Timber grain runs along the brick's longest side.
        let grain: SIMD3<Float> = h.y >= h.z && h.y >= h.x ? SIMD3(0, 1, 0) : h.z >= h.x ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
        var m = Mesh(texel: material == .wood ? 0.22 : material == .iron ? 0.5 : 0.3, grain: grain)
        switch shape {
        case .coneRoof: m.cone(radius: h.x * 1.02, height: h.y * 2)
        case .pyramidRoof: m.pyramid(half: SIMD3(h.x * 1.04, h.y, h.z * 1.04))
        case .wedge: m.wedge(h)
        case .arch: m.arch(h)
        case .moat: m.box(SIMD3(0, 0.05, 0), SIMD3(h.x, 0.05, h.z), bevel: 0)
        case .battlement:
            m.box(SIMD3(0, -h.y * 0.42, 0), SIMD3(h.x, h.y * 0.58, h.z), bevel: bevel)
            m.box(SIMD3(0, h.y * 0.58, 0), SIMD3(h.x * 0.8, h.y * 0.42, h.z * 0.8), bevel: bevel)
        case .window:
            let o = h.z * 0.3
            m.box(SIMD3(0, 0, -(h.z + o) / 2), SIMD3(h.x, h.y, (h.z - o) / 2), bevel: bevel * 0.6)
            m.box(SIMD3(0, 0, (h.z + o) / 2), SIMD3(h.x, h.y, (h.z - o) / 2), bevel: bevel * 0.6)
            m.box(SIMD3(0, -h.y * 0.7, 0), SIMD3(h.x * 0.98, h.y * 0.3, o), bevel: 0.02)
            m.box(SIMD3(0, h.y * 0.75, 0), SIMD3(h.x * 0.98, h.y * 0.25, o), bevel: 0.02)
        case .pillar2 where material == .wood, .pillar3 where material == .wood:
            m.prism(radius: h.x * 0.97, half: h.y, sides: 9, cap: 0.2)
        case .pillar2 where material.isCrystal, .pillar3 where material.isCrystal, .cube where material.isCrystal:
            m.crystal(radius: h.x * 0.92, half: h.y)
        default:
            m.box(.zero, h * 0.992, bevel: bevel)
        }
        let g = m.geometry()
        meshes[key] = g
        return g
    }

    /// The body shape of a brick, without the small gap left between neighbours.
    static func physicsShape(_ shape: BrickShape) -> SCNPhysicsShape? {
        if shape.isDecal { return nil }
        if let s = shapes[shape.rawValue] { return s }
        let s: SCNPhysicsShape
        switch shape {
        case .wedge, .coneRoof, .pyramidRoof:
            s = SCNPhysicsShape(geometry: mesh(shape, .stone), options: [.type: SCNPhysicsShape.ShapeType.convexHull])
        default:
            let parts = shape.boxes.map { b -> (SCNPhysicsShape, NSValue) in
                let box = SCNBox(width: CGFloat(b.h.x * 2 - 0.04), height: CGFloat(b.h.y * 2), length: CGFloat(b.h.z * 2 - 0.04), chamferRadius: 0)
                return (SCNPhysicsShape(geometry: box, options: nil), NSValue(scnMatrix4: SCNMatrix4MakeTranslation(Float(b.c.x), Float(b.c.y), Float(b.c.z))))
            }
            s = parts.count == 1 && shape.boxes[0].c == .zero ? parts[0].0 : SCNPhysicsShape(shapes: parts.map { $0.0 }, transforms: parts.map { $0.1 })
        }
        shapes[shape.rawValue] = s
        return s
    }

    /// A chunk of a broken brick, `size` world units across.
    static func fragment(size: SIMD3<Float>, material: BrickMaterial, heart: HeartKind, variant: Int) -> SCNGeometry {
        let q = SIMD3<Int>(Int(size.x * 4), Int(size.y * 4), Int(size.z * 4))
        let key = ((q.x * 32 + q.y) * 32 + q.z) * 64 + material.rawValue * 8 + variant
        if let g = fragments[key] { return g }
        let g = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: CGFloat(min(size.x, size.y, size.z) * 0.18))
        g.chamferSegmentCount = 1
        g.materials = [look(material, heart: heart, variant: variant)]
        fragments[key] = g
        return g
    }
}

/// Builds one brick's mesh from flat-shaded polygons. Texture coordinates follow position, so
/// the surface pattern keeps its size on long and short bricks alike.
private struct Mesh {
    private var pos: [SCNVector3] = []
    private var nor: [SCNVector3] = []
    private var uv: [CGPoint] = []
    private var tan: [SIMD4<Float>] = []
    private var idx: [Int32] = []
    let texel: Float
    let grain: SIMD3<Float>

    init(texel: Float, grain: SIMD3<Float>) { self.texel = texel; self.grain = grain }

    /// A flat convex polygon facing `n`; the corner order is fixed up to face the right way.
    mutating func poly(_ p: [SIMD3<Float>], _ n: SIMD3<Float>, normals: [SIMD3<Float>]? = nil) {
        guard p.count >= 3 else { return }
        var pts = p, ns = normals
        let face = simd_cross(pts[1] - pts[0], pts[2] - pts[0])
        if simd_dot(face, n) < 0 { pts.reverse(); ns?.reverse() }
        var u = grain - n * simd_dot(grain, n)
        if simd_length_squared(u) < 0.25 {
            let side: SIMD3<Float> = abs(n.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            u = side - n * simd_dot(side, n)
        }
        u = simd_normalize(u)
        let v = simd_cross(n, u)
        let base = Int32(pos.count)
        for (i, q) in pts.enumerated() {
            let nn = ns?[i] ?? n
            pos.append(SCNVector3(q.x, q.y, q.z))
            nor.append(SCNVector3(nn.x, nn.y, nn.z))
            uv.append(CGPoint(x: CGFloat(simd_dot(q, u) * texel), y: CGFloat(simd_dot(q, v) * texel)))
            tan.append(SIMD4(u.x, u.y, u.z, 1))
        }
        for i in 1..<(pts.count - 1) { idx += [base, base + Int32(i), base + Int32(i + 1)] }
    }

    /// A box with its edges and corners cut at 45°.
    mutating func box(_ c: SIMD3<Float>, _ h: SIMD3<Float>, bevel: Float) {
        let b = min(bevel, min(h.x, min(h.y, h.z)) * 0.4), e = h - b
        let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        for a in 0..<3 { for s in [Float(-1), 1] {
            let n = axes[a] * s, u = axes[(a + 1) % 3], v = axes[(a + 2) % 3]
            let face = c + n * h
            let eu = simd_dot(e, u), ev = simd_dot(e, v)
            poly([face - u * eu - v * ev, face + u * eu - v * ev, face + u * eu + v * ev, face - u * eu + v * ev], n)
        } }
        guard b > 0 else { return }
        for a in 0..<3 {
            let i = axes[a], j = axes[(a + 1) % 3], t = axes[(a + 2) % 3]
            for si in [Float(-1), 1] { for sj in [Float(-1), 1] {
                let n = simd_normalize(i * si + j * sj), et = simd_dot(e, t)
                let p1 = c + i * si * simd_dot(h, i) + j * sj * simd_dot(e, j), p2 = c + i * si * simd_dot(e, i) + j * sj * simd_dot(h, j)
                poly([p1 - t * et, p1 + t * et, p2 + t * et, p2 - t * et], n)
            } }
        }
        for sx in [Float(-1), 1] { for sy in [Float(-1), 1] { for sz in [Float(-1), 1] {
            let s = SIMD3(sx, sy, sz)
            poly([c + s * SIMD3(h.x, e.y, e.z), c + s * SIMD3(e.x, h.y, e.z), c + s * SIMD3(e.x, e.y, h.z)], simd_normalize(s))
        } } }
    }

    /// Full height at the back (−x), sloping down to nothing at the front.
    mutating func wedge(_ h: SIMD3<Float>) {
        let a = SIMD3(-h.x, -h.y, -h.z), b = SIMD3(h.x, -h.y, -h.z), c = SIMD3(-h.x, h.y, -h.z)
        let d = SIMD3(-h.x, -h.y, h.z), e = SIMD3(h.x, -h.y, h.z), f = SIMD3(-h.x, h.y, h.z)
        poly([a, b, c], SIMD3(0, 0, -1)); poly([d, e, f], SIMD3(0, 0, 1))
        poly([a, d, e, b], SIMD3(0, -1, 0)); poly([a, c, f, d], SIMD3(-1, 0, 0))
        poly([c, b, e, f], simd_normalize(SIMD3(h.y, h.x, 0)))
    }

    /// Four sloped faces up to a point, the base at the bottom of the brick.
    mutating func pyramid(half h: SIMD3<Float>) {
        let top = SIMD3<Float>(0, h.y, 0)
        let base = [SIMD3(-h.x, -h.y, -h.z), SIMD3(h.x, -h.y, -h.z), SIMD3(h.x, -h.y, h.z), SIMD3(-h.x, -h.y, h.z)]
        poly(base, SIMD3(0, -1, 0))
        for i in 0..<4 {
            let p = base[i], q = base[(i + 1) % 4], mid = (p + q) / 2
            let out = simd_normalize(SIMD3(mid.x, 0, mid.z))
            poly([p, q, top], simd_normalize(out * h.y * 2 + SIMD3(0, simd_length(SIMD3(mid.x, 0, mid.z)), 0)))
        }
    }

    /// A round roof, smooth around and pointed at the top.
    mutating func cone(radius r: Float, height: Float, sides: Int = 16) {
        let y0 = -height / 2, top = SIMD3<Float>(0, height / 2, 0)
        var ring: [SIMD3<Float>] = []
        for i in 0..<sides { let a = Float(i) / Float(sides) * 2 * .pi; ring.append(SIMD3(cos(a) * r, y0, sin(a) * r)) }
        poly(ring, SIMD3(0, -1, 0))
        for i in 0..<sides {
            let p = ring[i], q = ring[(i + 1) % sides]
            func n(_ v: SIMD3<Float>) -> SIMD3<Float> { simd_normalize(SIMD3(v.x * height, r, v.z * height)) }
            let m = (p + q) / 2
            poly([p, q, top], n(m), normals: [n(p), n(q), n(m)])
        }
    }

    /// An upright log: a many-sided prism with bevelled ends.
    mutating func prism(radius r: Float, half: Float, sides: Int, cap: Float) {
        var lo: [SIMD3<Float>] = [], hi: [SIMD3<Float>] = [], lo2: [SIMD3<Float>] = [], hi2: [SIMD3<Float>] = []
        for i in 0..<sides {
            let a = Float(i) / Float(sides) * 2 * .pi, c = cos(a), s = sin(a)
            lo.append(SIMD3(c * r, -half + cap, s * r)); hi.append(SIMD3(c * r, half - cap, s * r))
            lo2.append(SIMD3(c * r * 0.75, -half, s * r * 0.75)); hi2.append(SIMD3(c * r * 0.75, half, s * r * 0.75))
        }
        poly(lo2, SIMD3(0, -1, 0)); poly(hi2, SIMD3(0, 1, 0))
        for i in 0..<sides {
            let j = (i + 1) % sides, m = simd_normalize((lo[i] + lo[j]) * SIMD3(1, 0, 1))
            func out(_ v: SIMD3<Float>) -> SIMD3<Float> { simd_normalize(v * SIMD3(1, 0, 1)) }
            poly([lo[i], lo[j], hi[j], hi[i]], m, normals: [out(lo[i]), out(lo[j]), out(hi[j]), out(hi[i])])
            poly([hi[i], hi[j], hi2[j], hi2[i]], simd_normalize(m + SIMD3(0, 1.2, 0)))
            poly([lo[i], lo[j], lo2[j], lo2[i]], simd_normalize(m + SIMD3(0, -1.2, 0)))
        }
    }

    /// A six-sided crystal column with pointed ends.
    mutating func crystal(radius r: Float, half: Float) {
        let tip = min(0.7, half * 0.4)
        var lo: [SIMD3<Float>] = [], hi: [SIMD3<Float>] = []
        for i in 0..<6 {
            let a = Float(i) / 6 * 2 * .pi + .pi / 6
            lo.append(SIMD3(cos(a) * r, -half + tip * 0.5, sin(a) * r)); hi.append(SIMD3(cos(a) * r, half - tip, sin(a) * r))
        }
        let top = SIMD3<Float>(0, half, 0), bottom = SIMD3<Float>(0, -half, 0)
        for i in 0..<6 {
            let j = (i + 1) % 6, m = simd_normalize((lo[i] + lo[j]) * SIMD3(1, 0, 1))
            poly([lo[i], lo[j], hi[j], hi[i]], m)
            poly([hi[i], hi[j], top], simd_normalize(m * tip + SIMD3(0, r, 0)))
            poly([lo[j], lo[i], bottom], simd_normalize(m * tip - SIMD3(0, r, 0)))
        }
    }

    /// A round arch through the brick along x: two legs and a curved crown.
    mutating func arch(_ h: SIMD3<Float>, segments: Int = 10) {
        let leg = h.z / 3, open = h.z - leg, crown = h.y * 0.2
        let rad = open, yc = h.y - crown - rad
        var arc: [(z: Float, y: Float, a: Float)] = []
        for i in 0...segments {
            let a = Float.pi - Float.pi * Float(i) / Float(segments)
            arc.append((cos(a) * rad, yc + sin(a) * rad, a))
        }
        for sx in [Float(-1), 1] {
            let x = sx * h.x, n = SIMD3<Float>(sx, 0, 0)
            poly([SIMD3(x, -h.y, -h.z), SIMD3(x, -h.y, -open), SIMD3(x, h.y, -open), SIMD3(x, h.y, -h.z)], n)
            poly([SIMD3(x, -h.y, open), SIMD3(x, -h.y, h.z), SIMD3(x, h.y, h.z), SIMD3(x, h.y, open)], n)
            for i in 0..<segments {
                let p = arc[i], q = arc[i + 1]
                poly([SIMD3(x, p.y, p.z), SIMD3(x, q.y, q.z), SIMD3(x, h.y, q.z), SIMD3(x, h.y, p.z)], n)
            }
        }
        poly([SIMD3(-h.x, h.y, -h.z), SIMD3(h.x, h.y, -h.z), SIMD3(h.x, h.y, h.z), SIMD3(-h.x, h.y, h.z)], SIMD3(0, 1, 0))
        for sz in [Float(-1), 1] {
            let z = sz * h.z
            poly([SIMD3(-h.x, -h.y, z), SIMD3(h.x, -h.y, z), SIMD3(h.x, h.y, z), SIMD3(-h.x, h.y, z)], SIMD3(0, 0, sz))
            poly([SIMD3(-h.x, -h.y, sz * open), SIMD3(h.x, -h.y, sz * open), SIMD3(h.x, -h.y, z), SIMD3(-h.x, -h.y, z)], SIMD3(0, -1, 0))
            poly([SIMD3(-h.x, -h.y, sz * open), SIMD3(h.x, -h.y, sz * open), SIMD3(h.x, yc, sz * open), SIMD3(-h.x, yc, sz * open)], SIMD3(0, 0, -sz))
        }
        for i in 0..<segments {
            let p = arc[i], q = arc[i + 1], a = (p.a + q.a) / 2
            poly([SIMD3(-h.x, p.y, p.z), SIMD3(h.x, p.y, p.z), SIMD3(h.x, q.y, q.z), SIMD3(-h.x, q.y, q.z)], SIMD3(0, -sin(a), -cos(a)))
        }
    }

    func geometry() -> SCNGeometry {
        let tanData = tan.withUnsafeBufferPointer { Data(buffer: $0) }
        let tangents = SCNGeometrySource(data: tanData, semantic: .tangent, vectorCount: tan.count, usesFloatComponents: true,
                                         componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor), SCNGeometrySource(textureCoordinates: uv), tangents],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}

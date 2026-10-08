import SceneKit

// Geometry and looks of single bricks, shared by the match scene and the builder. Geometry is
// cached per shape and material, so every brick of a kind shares one SCNGeometry.

enum BrickGeometry {
    private static var cache: [Int: SCNGeometry] = [:]

    /// Geometry for a brick at rotation 0, centred on its own origin, in world units.
    static func geometry(_ shape: BrickShape, _ material: BrickMaterial) -> SCNGeometry {
        let key = shape.rawValue * 16 + material.rawValue
        if let g = cache[key] { return g }
        let s = shape.size, k = CGFloat(BK.step)
        let w = CGFloat(s.x) * k, h = CGFloat(s.y) * k, d = CGFloat(s.z) * k
        let g: SCNGeometry
        switch shape {
        case .coneRoof:
            g = SCNCone(topRadius: 0, bottomRadius: w / 2, height: h)
        case .pyramidRoof:
            g = SCNPyramid(width: w, height: h, length: d)
        case .wedge:
            g = wedge(w, h, d)
        case .moat:
            g = SCNBox(width: w, height: 0.05, length: d, chamferRadius: 0)
        default:
            g = SCNBox(width: w * 0.985, height: h * 0.985, length: d * 0.985, chamferRadius: min(w, h, d) * 0.06)
        }
        g.materials = [look(material)]
        cache[key] = g
        return g
    }

    /// A node for a placed brick, positioned and rotated castle-locally.
    static func node(for b: PlacedBrick) -> SCNNode {
        let n = SCNNode(geometry: geometry(b.shape, b.material))
        let c = b.center
        n.simdPosition = SIMD3(Float(c.x), Float(c.y), Float(c.z))
        n.simdOrientation = simd_quatf(angle: Float(b.rot) * .pi / 2, axis: SIMD3(0, 1, 0))
        // Pyramids sit on their base; SceneKit puts their origin there instead of the centre.
        if b.shape == .pyramidRoof { n.pivot = SCNMatrix4MakeTranslation(0, Float(b.shape.size.y) * Float(BK.step) / 2, 0) }
        return n
    }

    /// Placeholder looks; the physics workstream replaces these with procedural PBR textures.
    static func look(_ m: BrickMaterial) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        switch m {
        case .wood: mat.diffuse.contents = UIColor(red: 0.62, green: 0.42, blue: 0.24, alpha: 1); mat.roughness.contents = 0.8
        case .stone: mat.diffuse.contents = UIColor(white: 0.62, alpha: 1); mat.roughness.contents = 0.9
        case .ice: mat.diffuse.contents = UIColor(red: 0.7, green: 0.88, blue: 1, alpha: 0.75); mat.roughness.contents = 0.15; mat.transparency = 0.8
        case .iron: mat.diffuse.contents = UIColor(white: 0.35, alpha: 1); mat.metalness.contents = 0.8; mat.roughness.contents = 0.4
        case .heart: mat.diffuse.contents = UIColor(red: 1, green: 0.25, blue: 0.45, alpha: 1); mat.emission.contents = UIColor(red: 0.6, green: 0.05, blue: 0.2, alpha: 1)
        case .decoy: mat.diffuse.contents = UIColor(red: 1, green: 0.25, blue: 0.45, alpha: 1); mat.emission.contents = UIColor(red: 0.6, green: 0.05, blue: 0.2, alpha: 1)
        }
        return mat
    }

    /// A ramp: full height at x = 0, sloping down to nothing at x = w.
    private static func wedge(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat) -> SCNGeometry {
        let x0 = Float(-w / 2), x1 = Float(w / 2), y0 = Float(-h / 2), y1 = Float(h / 2), z0 = Float(-d / 2), z1 = Float(d / 2)
        let v: [SCNVector3] = [
            SCNVector3(x0, y0, z0), SCNVector3(x1, y0, z0), SCNVector3(x0, y1, z0),   // left side
            SCNVector3(x0, y0, z1), SCNVector3(x0, y1, z1), SCNVector3(x1, y0, z1),   // right side
            SCNVector3(x0, y0, z0), SCNVector3(x0, y0, z1), SCNVector3(x1, y0, z1), SCNVector3(x1, y0, z0),   // bottom
            SCNVector3(x0, y0, z0), SCNVector3(x0, y1, z0), SCNVector3(x0, y1, z1), SCNVector3(x0, y0, z1),   // back
            SCNVector3(x0, y1, z0), SCNVector3(x1, y0, z0), SCNVector3(x1, y0, z1), SCNVector3(x0, y1, z1),   // slope
        ]
        let idx: [Int32] = [0, 2, 1, 3, 5, 4, 6, 8, 7, 6, 9, 8, 10, 12, 11, 10, 13, 12, 14, 16, 15, 14, 17, 16]
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }
}

import SceneKit
import UIKit

// Castle skins: the same bricks in other materials. Each skin keeps wood, stone, ice and iron
// easy to tell apart (grain, blocks, glass and riveted plate stay where they were), because
// reading the enemy's materials is part of the game. Looks are built from the procedural
// textures and cached per skin and material by `BrickGeometry.look`.

/// The colours a skin gives each material, also used for dust, chips and the shop swatches.
struct SkinPalette {
    /// Three shades each, so a wall does not look printed.
    let stone: [UInt32]
    let wood: [UInt32]
    let ice: UInt32
    let iron: UInt32
    let roof: UInt32
    /// Gold edges on stone (and on wood where `woodTrim` is set).
    var trim: UInt32? = nil
    var woodTrim = false

    static func of(_ s: Skin) -> SkinPalette {
        switch s {
        case .classic:
            return SkinPalette(stone: [0xbfc0bd, 0xcfc3a6, 0xadb4a8], wood: [0xa0703f, 0x8b5b34, 0xb08250], ice: 0xe2f4ff, iron: 0x707880, roof: 0x9a4f33)
        case .gold:
            return SkinPalette(stone: [0xead08a, 0xf2dc9c, 0xdcc174], wood: [0x3c2416, 0x301b10, 0x47291a], ice: 0xffc46b, iron: 0xb9813f, roof: 0xd9a514,
                               trim: 0xf0c050, woodTrim: true)
        case .obsidian:
            return SkinPalette(stone: [0x2f2d33, 0x28262b, 0x37343a], wood: [0x3a271c, 0x2e1f16, 0x443022], ice: 0x8c919e, iron: 0x4c545e, roof: 0x3a393f)
        case .marble:
            return SkinPalette(stone: [0xf6f4f0, 0xebe7e1, 0xf2ece4], wood: [0xe8dece, 0xdcd0bc, 0xf0e8da], ice: 0xf8fcff, iron: 0xd6dce3, roof: 0x8fa3b8)
        case .candy:
            return SkinPalette(stone: [0xffb4cd, 0xb4f0d4, 0xfff09c], wood: [0xdca465, 0xcf9254, 0xe7b678], ice: 0x58bcff, iron: 0x1d1b21, roof: 0xff8fb8)
        case .royal:
            return SkinPalette(stone: [0x5d3c92, 0x503384, 0x68479e], wood: [0x5c2b3e, 0x4c2333, 0x683242], ice: 0xcfa9ff, iron: 0xe2b44c, roof: 0x4b2a85,
                               trim: 0xf2c14e)
        }
    }

    func shade(_ m: BrickMaterial, _ variant: Int = 0) -> UInt32 {
        switch m {
        case .stone: return stone[variant % stone.count]
        case .wood: return wood[variant % wood.count]
        case .ice: return ice
        case .iron: return iron
        case .heart, .decoy: return 0xc2185b
        }
    }

    /// Chips and a dust cloud when a brick of this material breaks.
    func dust(_ m: BrickMaterial) -> (chips: [UInt32], cloud: [UInt32]) {
        let base = shade(m), light = SkinPalette.mix(base, 0xffffff, 0.35)
        switch m {
        case .ice: return ([light, 0xffffff], [SkinPalette.mix(base, 0xffffff, 0.5)])
        case .iron: return ([0xffc36b, 0xffffff], [SkinPalette.mix(base, 0x55595e, 0.5)])
        default: return ([base, shade(m, 1), trim ?? light], [SkinPalette.mix(base, 0xb5b2aa, 0.45)])
        }
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xff) }
        func m(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, (ch(a, s) + (ch(b, s) - ch(a, s)) * t).rounded()))) << s }
        return m(16) | m(8) | m(0)
    }
}

extension BrickGeometry {
    /// Gold on the bevelled edges of a box brick. The brick's own (model-space) normal tells the
    /// flat faces, which point along an axis, from the 45° bevels between them.
    private static func trimmed(_ m: SCNMaterial, _ hex: UInt32) {
        let c = UIColor(hex: hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        m.shaderModifiers = [.surface: """
            float3 n = normalize((scn_node.inverseModelViewTransform * float4(_surface.geometryNormal, 0.0)).xyz);
            float axis = max(abs(n.x), max(abs(n.y), abs(n.z)));
            float edge = 1.0 - smoothstep(0.86, 0.93, axis);
            _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(\(r), \(g), \(b)), edge);
            _surface.metalness = mix(_surface.metalness, 1.0, edge);
            _surface.roughness = mix(_surface.roughness, 0.28, edge);
            """]
    }

    /// Glass: tinted, see-through, brighter at grazing angles.
    private static func glass(_ tint: UInt32, glow: UInt32, glowIntensity: CGFloat, clear: CGFloat, rim: (Double, Double, Double)) -> SCNMaterial {
        let mat = textured(Textures.tint(Textures.ice.albedo, "ice", tint), normal: Textures.ice.normal, roughness: 0.05, bump: 0.6)
        mat.transparency = clear
        mat.transparencyMode = .dualLayer
        mat.emission.contents = UIColor(hex: glow)
        mat.emission.intensity = glowIntensity
        mat.shaderModifiers = [.fragment: """
            float rim = pow(1.0 - clamp(dot(_surface.normal, _surface.view), 0.0, 1.0), 2.5);
            _output.color.rgb += rim * vec3(\(rim.0), \(rim.1), \(rim.2));
            """]
        return mat
    }

    /// A brick's look in a skin other than the classic one.
    static func skinLook(_ m: BrickMaterial, skin: Skin, variant: Int, wear: Wear, roof: Bool) -> SCNMaterial {
        let pal = SkinPalette.of(skin), key = "skin-\(skin.rawValue)"
        if roof && m != .ice {
            let metal: CGFloat = skin == .gold ? 0.65 : 0
            let mat = textured(Textures.tint(Textures.shingles.albedo, key + "-roof", m == .stone ? pal.roof : SkinPalette.mix(pal.roof, pal.wood[0], 0.35)),
                               normal: Textures.shingles.normal, roughness: skin == .gold ? 0.35 : skin == .candy ? 0.45 : 0.7, metal: metal, bump: 1.1)
            if let t = pal.trim, skin == .royal { trimmed(mat, t) }
            return mat
        }
        switch m {
        case .stone:
            let hex = pal.stone[variant % pal.stone.count]
            let mat: SCNMaterial
            switch skin {
            case .marble:
                mat = textured(Textures.tint(Textures.marble.albedo, "marble", hex), normal: Textures.marble.normal, roughness: 0.2, bump: 0.5)
            case .gold:
                mat = textured(Textures.tint(Textures.ashlar.albedo, "ashlar", hex), normal: Textures.ashlar.normal, roughness: 0.42, metal: 0.45, bump: 0.8)
            case .obsidian:
                mat = textured(Textures.tint(Textures.ashlar.albedo, "ashlar", hex), normal: Textures.ashlar.normal, roughness: 0.5, metal: 0.1, bump: 1.1)
                mat.emission.contents = Textures.embers
                mat.emission.wrapS = .repeat; mat.emission.wrapT = .repeat; mat.emission.mipFilter = .linear
                mat.emission.intensity = 0.9
                let pulse = CABasicAnimation(keyPath: "intensity")
                pulse.fromValue = 0.55
                pulse.toValue = 1.15
                pulse.duration = 2.2
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                mat.emission.addAnimation(pulse, forKey: "embers")
            case .candy:
                mat = textured(Textures.tint(Textures.ashlar.albedo, "ashlar", hex), normal: Textures.ashlar.normal, roughness: 0.38, bump: 0.45)
            default:
                mat = textured(Textures.tint(Textures.ashlar.albedo, "ashlar", hex), normal: Textures.ashlar.normal, roughness: 0.62, bump: 0.95)
            }
            if let t = pal.trim { trimmed(mat, t) }
            return mat
        case .wood:
            let hex = pal.wood[variant % pal.wood.count]
            let rough: CGFloat = skin == .gold ? 0.3 : skin == .obsidian ? 0.95 : skin == .royal ? 0.45 : skin == .candy ? 0.85 : 0.72
            let mat = textured(Textures.tint(Textures.timber.albedo, "timber", hex), normal: Textures.timber.normal, roughness: rough,
                               metal: skin == .gold ? 0.12 : 0, bump: skin == .obsidian ? 1.2 : 0.8)
            if skin == .obsidian {
                // Charred: the faintest glow left in the cracks.
                mat.emission.contents = Textures.embers
                mat.emission.wrapS = .repeat; mat.emission.wrapT = .repeat
                mat.emission.intensity = 0.22
            }
            if pal.woodTrim, let t = pal.trim { trimmed(mat, t) }
            return mat
        case .ice:
            switch skin {
            case .gold: return glass(pal.ice, glow: 0x8a4a00, glowIntensity: 0.3, clear: 0.76, rim: (0.5, 0.34, 0.1))
            case .obsidian: return glass(pal.ice, glow: 0x1c1f26, glowIntensity: 0.2, clear: 0.7, rim: (0.25, 0.27, 0.32))
            case .marble: return glass(pal.ice, glow: 0x6a8aa0, glowIntensity: 0.08, clear: 0.6, rim: (0.42, 0.46, 0.5))
            case .candy: return glass(pal.ice, glow: 0x1a5fa0, glowIntensity: 0.32, clear: 0.72, rim: (0.3, 0.5, 0.7))
            case .royal: return glass(pal.ice, glow: 0x4a1f8a, glowIntensity: 0.28, clear: 0.76, rim: (0.42, 0.3, 0.55))
            case .classic: return glass(pal.ice, glow: 0x2a6f9a, glowIntensity: 0.18, clear: 0.78, rim: (0.32, 0.42, 0.5))
            }
        case .iron:
            let cracked = wear == .cracked
            let t = Textures.ironPlate(cracked: cracked)
            let hex = cracked ? SkinPalette.mix(pal.iron, 0x000000, 0.35) : pal.iron
            let rough: CGFloat = skin == .candy ? 0.18 : skin == .marble ? 0.22 : 0.32
            let metal: CGFloat = skin == .candy ? 0.05 : 0.95
            return textured(Textures.tint(t.albedo, cracked ? "iron-cracked" : "iron", hex), normal: t.normal,
                            roughness: cracked ? min(0.85, rough + 0.4) : rough, metal: cracked ? metal * 0.5 : metal, bump: 1.2)
        case .heart, .decoy:
            return Look.heartMaterial()
        }
    }
}

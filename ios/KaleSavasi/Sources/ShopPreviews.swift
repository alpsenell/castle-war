import SceneKit
import SwiftUI
import UIKit

// Previews for the shop: a small castle rendered offscreen in each skin, and cheap animated
// drawings of the trails and the fireworks.

enum ShopPreviews {
    private static var castles: [String: UIImage] = [:]
    private static let renderer: SCNRenderer? = MTLCreateSystemDefaultDevice().map { SCNRenderer(device: $0, options: nil) }

    /// Two towers, a wall with every material in it and the heart on top, built in bricks.
    static let miniCastle: [PlacedBrick] = {
        var b: [PlacedBrick] = []
        for (z, roof) in [(0, BrickShape.coneRoof), (10, BrickShape.pyramidRoof)] {
            for y in stride(from: 0, to: 6, by: 2) {
                for dx in [2, 4] { for dz in [0, 2] {
                    let ice = z == 0 && y == 2 && dx == 4 && dz == 2
                    b.append(PlacedBrick(shape: .cube, material: ice ? .ice : .stone, x: dx, y: y, z: z + dz))
                } }
            }
            b.append(PlacedBrick(shape: roof, material: roof == .coneRoof ? .wood : .stone, x: 2, y: 6, z: z))
        }
        b.append(PlacedBrick(shape: .cube, material: .stone, x: 4, y: 0, z: 4))
        b.append(PlacedBrick(shape: .cube, material: .iron, x: 4, y: 0, z: 6))
        b.append(PlacedBrick(shape: .cube, material: .stone, x: 4, y: 0, z: 8))
        b.append(PlacedBrick(shape: .beam3, material: .wood, x: 4, y: 2, z: 4))
        b.append(PlacedBrick(shape: .battlement, material: .stone, x: 4, y: 4, z: 4))
        b.append(PlacedBrick(shape: .cube, material: .heart, x: 4, y: 4, z: 6))
        b.append(PlacedBrick(shape: .battlement, material: .stone, x: 4, y: 4, z: 8))
        return b
    }()

    private static let backdrop: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 256)).image { ctx in
            let colors = [UIColor(hex: 0x6fb6ef).cgColor, UIColor(hex: 0xcfe6f7).cgColor, UIColor(hex: 0xf3e3c0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
    }()

    /// The mini castle in a skin, with a heart gem and a crest, rendered once and cached.
    static func castle(_ skin: Skin, gem: HeartGem = .none, banner: Banner = .none, size: CGSize = CGSize(width: 360, height: 240)) -> UIImage? {
        let key = "\(skin.rawValue)-\(gem.rawValue)-\(banner.rawValue)-\(Int(size.width))x\(Int(size.height))"
        if let hit = castles[key] { return hit }
        guard let renderer else { return nil }
        let scene = SCNScene()
        scene.background.contents = backdrop
        scene.lightingEnvironment.contents = Textures.sky
        scene.lightingEnvironment.intensity = 1.4
        let style = BrickStyle(skin: skin, gem: gem)
        let root = SCNNode()
        for b in miniCastle {
            let n = BrickGeometry.node(for: b, heart: .crystal, style: style)
            root.addChildNode(n)
            if b.material == .heart {
                let gemNode = SCNNode()
                for flip in [false, true] {
                    let half = SCNNode(geometry: SCNPyramid(width: 0.9, height: 0.8, length: 0.9))
                    half.geometry?.materials = [Look.heartMaterial(.crystal, gem: gem)]
                    if flip { half.eulerAngles.x = .pi }
                    gemNode.addChildNode(half)
                }
                gemNode.simdPosition = n.simdPosition + SIMD3(0, 2.4, 0)
                gemNode.eulerAngles.y = 0.6
                root.addChildNode(gemNode)
            }
        }
        // The crest flies over the left tower (or a plain red flag).
        let flagBase = SCNNode()
        flagBase.simdPosition = SIMD3(4, 10, 2)
        flagBase.eulerAngles.y = -0.35
        for part in World.flagNodes(top: 0, accent: Look.accent[0], banner: banner) { flagBase.addChildNode(part) }
        root.addChildNode(flagBase)
        let ground = SCNNode(geometry: SCNCylinder(radius: 11, height: 0.3))
        ground.geometry?.materials = [Look.solid(0x6a9a45, roughness: 1)]
        ground.position = SCNVector3(3.5, -0.15, 7)
        root.addChildNode(ground)
        scene.rootNode.addChildNode(root)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1300
        sun.color = UIColor(hex: 0xfff1dc)
        sun.castsShadow = true
        sun.shadowRadius = 2
        sun.shadowSampleCount = 8
        sun.shadowColor = UIColor(white: 0, alpha: 0.45)
        let sn = SCNNode()
        sn.light = sun
        sn.position = SCNVector3(30, 40, 20)
        sn.look(at: SCNVector3(3, 0, 7))
        scene.rootNode.addChildNode(sn)

        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.wantsHDR = true
        cam.exposureOffset = 0.3
        cam.bloomIntensity = 0.35
        cam.bloomThreshold = 0.9
        let cn = SCNNode()
        cn.camera = cam
        cn.position = SCNVector3(30, 14, 20)
        cn.look(at: SCNVector3(3, 6.2, 7))
        scene.rootNode.addChildNode(cn)

        renderer.scene = scene
        renderer.pointOfView = cn
        let img = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        castles[key] = img
        return img
    }
}

/// A castle preview that renders once, then stays.
struct CastlePreview: View {
    let skin: Skin
    var gem: HeartGem = .none
    var banner: Banner = .none
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x6fb6ef), Color(hex: 0xf3e3c0)], startPoint: .top, endPoint: .bottom)
                ProgressView().tint(Theme.woodDark)
            }
        }
        .task(id: "\(skin.rawValue)\(gem.rawValue)\(banner.rawValue)") {
            // Let the card appear first; the render takes a moment the first time.
            try? await Task.sleep(nanoseconds: 60_000_000)
            image = ShopPreviews.castle(skin, gem: gem, banner: banner)
        }
    }
}

/// A cannonball flying an arc with its trail, drawn every frame.
struct TrailPreview: View {
    let trail: Trail
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
            Canvas { ctx, size in
                let t = still ? 0.62 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                draw(ctx, size, t: t, clock: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(LinearGradient(colors: [Color(hex: 0x1d2a44), Color(hex: 0x3b4f7a)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }

    private func point(_ s: Double, _ size: CGSize) -> CGPoint {
        let x = 0.08 + 0.84 * s, y = 0.86 - 3.0 * s * (1 - s)
        return CGPoint(x: size.width * x, y: size.height * y)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, t: Double, clock: Double) {
        let head = t
        let span = 0.42
        let r = min(size.width, size.height) * 0.055
        func col(_ h: UInt32, _ a: Double = 1) -> Color { Color(hex: h).opacity(a) }
        var glow = ctx
        glow.blendMode = .plusLighter
        switch trail {
        case .none:
            break
        case .rainbow:
            let bands = Trail.rainbow.colors
            for (i, c) in bands.enumerated() {
                var path = Path()
                let off = (Double(i) - 2.5) * r * 0.42
                for k in 0...30 {
                    let s = max(0, head - span * Double(k) / 30)
                    let p = point(s, size)
                    let q = CGPoint(x: p.x, y: p.y + off)
                    if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                glow.stroke(path, with: .linearGradient(Gradient(colors: [col(c, 0.95), col(c, 0)]), startPoint: point(head, size), endPoint: point(max(0, head - span), size)),
                            style: StrokeStyle(lineWidth: r * 0.48, lineCap: .round))
            }
        case .lightning:
            var path = Path()
            var rng = SplitMix(seed: UInt64(clock * 14))
            for k in 0...14 {
                let s = max(0, head - span * Double(k) / 14)
                var p = point(s, size)
                if k > 0 { p.x += CGFloat(rng.next() - 0.5) * r * 2.6; p.y += CGFloat(rng.next() - 0.5) * r * 2.6 }
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            glow.stroke(path, with: .color(col(0x5fb8ff, 0.55)), style: StrokeStyle(lineWidth: r * 0.9, lineCap: .round, lineJoin: .round))
            glow.stroke(path, with: .color(col(0xffffff, 0.95)), style: StrokeStyle(lineWidth: r * 0.3, lineCap: .round, lineJoin: .round))
            for _ in 0..<10 {
                let s = max(0, head - span * rng.next() * 0.6), p = point(s, size)
                let d = CGRect(x: p.x + CGFloat(rng.next() - 0.5) * r * 5, y: p.y + CGFloat(rng.next() - 0.5) * r * 5, width: r * 0.35, height: r * 0.35)
                glow.fill(Path(ellipseIn: d), with: .color(col(0xe8f6ff)))
            }
        case .starfall, .royal:
            let royal = trail == .royal
            var path = Path()
            for k in 0...24 {
                let p = point(max(0, head - span * 0.7 * Double(k) / 24), size)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            glow.stroke(path, with: .linearGradient(Gradient(colors: [col(royal ? 0x8a3cff : 0xffd34d, 0.85), col(royal ? 0x8a3cff : 0xffd34d, 0)]),
                                                    startPoint: point(head, size), endPoint: point(max(0, head - span * 0.7), size)),
                        style: StrokeStyle(lineWidth: r * (royal ? 1.4 : 0.9), lineCap: .round))
            for k in 0..<14 {
                let born = head - Double(k) * 0.035
                guard born > 0 else { continue }
                let age = head - born, p = point(born, size)
                let fall = CGFloat(age * age) * size.height * 3.2
                let q = CGPoint(x: p.x + CGFloat(sin(Double(k) * 2.3)) * r * 1.2, y: p.y + fall + CGFloat(cos(Double(k) * 1.7)) * r)
                let a = max(0, 1 - age * 2.2)
                let sz = r * (0.9 - CGFloat(age))
                guard sz > 0 else { continue }
                glow.fill(SparkleShape().path(in: CGRect(x: q.x - sz, y: q.y - sz, width: sz * 2, height: sz * 2)),
                          with: .color(col(royal && k % 2 == 0 ? 0xf2c14e : royal ? 0xd8b4ff : 0xffe27a, a)))
            }
        }
        // The ball itself.
        let p = point(head, size)
        let ball = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(ball, with: .radialGradient(Gradient(colors: [Color(hex: 0x6b7a86), Color(hex: 0x1b2a34)]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35),
                                             startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(ball, with: .color(.black.opacity(0.6)), lineWidth: 1)
    }
}

/// Fireworks bursting over a little castle silhouette.
struct FireworksPreview: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
            Canvas { ctx, size in
                let clock = still ? 0.9 : tl.date.timeIntervalSinceReferenceDate
                var glow = ctx
                glow.blendMode = .plusLighter
                let shells: [(x: Double, y: Double, c: UInt32, c2: UInt32, phase: Double)] = [
                    (0.3, 0.32, 0xff3b5c, 0xffd34d, 0), (0.68, 0.26, 0x3fa8ff, 0xffffff, 0.45), (0.5, 0.45, 0x4ed96a, 0xfff2b0, 0.9), (0.8, 0.5, 0xb57dff, 0xff8ad8, 1.3),
                ]
                for s in shells {
                    let t = (clock + s.phase).truncatingRemainder(dividingBy: 1.8) / 1.8
                    let c = CGPoint(x: size.width * s.x, y: size.height * s.y)
                    let rmax = min(size.width, size.height) * 0.3
                    let a = max(0, 1 - t * 1.25)
                    for k in 0..<18 {
                        let ang = Double(k) / 18 * 2 * .pi
                        let rad = rmax * CGFloat(sqrt(t))
                        let p = CGPoint(x: c.x + CGFloat(cos(ang)) * rad, y: c.y + CGFloat(sin(ang)) * rad + CGFloat(t * t) * size.height * 0.18)
                        let d = 2.6 * (1 - t * 0.5)
                        glow.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)), with: .color(Color(hex: k % 2 == 0 ? s.c : s.c2).opacity(a)))
                    }
                }
                // Castle silhouette.
                var castle = Path()
                let w = size.width, h = size.height, base = h * 0.98
                castle.move(to: CGPoint(x: w * 0.18, y: base))
                for (x, y) in [(0.18, 0.72), (0.24, 0.72), (0.24, 0.68), (0.28, 0.68), (0.28, 0.72), (0.34, 0.72), (0.34, 0.8), (0.66, 0.8), (0.66, 0.72), (0.72, 0.72),
                               (0.72, 0.68), (0.76, 0.68), (0.76, 0.72), (0.82, 0.72), (0.82, 0.98)] as [(CGFloat, CGFloat)] {
                    castle.addLine(to: CGPoint(x: w * x, y: h * y))
                }
                castle.closeSubpath()
                ctx.fill(castle, with: .color(Color(hex: 0x141b2c)))
            }
        }
        .background(LinearGradient(colors: [Color(hex: 0x10162a), Color(hex: 0x2b3560)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }
}

struct SparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2, inner = R * 0.22
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2, rad = i % 2 == 0 ? R : inner
            let pt = CGPoint(x: c.x + rad * CGFloat(cos(a)), y: c.y + rad * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// A cut gem in a heart gem's colours, glowing.
struct HeartGemIcon: View {
    let gem: HeartGem
    var size: CGFloat = 40
    var body: some View {
        let c = gem.colors
        ZStack {
            GemCut().fill(LinearGradient(colors: [Color(hex: c.glow).lighter(0.35), Color(hex: c.glow), Color(hex: c.body), Color(hex: c.body).darker(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            GemFacets().stroke(Color.white.opacity(0.45), lineWidth: max(0.8, size * 0.025))
            GemCut().stroke(Theme.ink, lineWidth: max(1.2, size * 0.04))
        }
        .frame(width: size * 0.82, height: size)
        .shadow(color: Color(hex: c.glow).opacity(0.75), radius: size * 0.16)
    }
}

private struct GemCut: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.36))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.36))
        p.closeSubpath()
        return p
    }
}

private struct GemFacets: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.minY + r.height * 0.36
        p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + r.width * 0.3, y: y)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - r.width * 0.3, y: y)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

/// A banner crest on its flag, for the shop.
struct BannerFlag: View {
    let banner: Banner
    var color: UInt32 = Look.accent[0]
    var height: CGFloat = 44
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule().fill(LinearGradient(colors: [Theme.goldLight, Theme.goldDark], startPoint: .leading, endPoint: .trailing))
                .frame(width: height * 0.08, height: height * 1.25)
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
            Image(uiImage: Emblem.flag(banner, color: color))
                .resizable()
                .frame(width: height * 1.6, height: height)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
                .padding(.top, height * 0.04)
        }
    }
}

/// The Supporter crown worn beside a name.
struct CrownBadge: View {
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: "crown.fill").font(.system(size: size.u, weight: .black))
            .foregroundStyle(LinearGradient(colors: [Theme.goldLight, Theme.gold, Theme.goldDark], startPoint: .top, endPoint: .bottom))
            .embossed(width: 0.8, drop: 1.2)
            .accessibilityLabel(Tx.supporter)
    }
}

/// Swatches of a skin's four materials.
struct SkinSwatch: View {
    let skin: Skin
    var size: CGFloat = 12
    var body: some View {
        let p = SkinPalette.of(skin)
        HStack(spacing: 2) {
            ForEach(Array([p.stone[0], p.wood[0], p.ice, p.iron].enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: size * 0.25).fill(Color(hex: hex))
                    .frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(Theme.ink.opacity(0.8), lineWidth: 1))
            }
        }
    }
}

private struct SplitMix {
    var s: UInt64
    init(seed: UInt64) { s = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        s = s &+ 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(UInt64(1) << 53)
    }
}

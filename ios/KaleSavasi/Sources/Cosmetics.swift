import UIKit

// Cosmetics bought in the shop: castle skins, cannonball trails, an impact effect, heart gem
// colours, banner crests and the Supporter Pack. They only change how things look. Nothing here
// is read by the rules or the physics, so online matches between players with different
// cosmetics play out exactly the same (`K.rulesVersion` is untouched).

// MARK: - Products

/// App Store product IDs, one non-consumable each.
enum Catalog {
    static let gold = "com.alpsenel.kalesavasi.skin.gold"
    static let obsidian = "com.alpsenel.kalesavasi.skin.obsidian"
    static let marble = "com.alpsenel.kalesavasi.skin.marble"
    static let candy = "com.alpsenel.kalesavasi.skin.candy"
    static let rainbow = "com.alpsenel.kalesavasi.trail.rainbow"
    static let lightning = "com.alpsenel.kalesavasi.trail.lightning"
    static let starfall = "com.alpsenel.kalesavasi.trail.starfall"
    static let fireworks = "com.alpsenel.kalesavasi.impact.fireworks"
    static let hearts = "com.alpsenel.kalesavasi.pack.hearts"
    static let banners = "com.alpsenel.kalesavasi.pack.banners"
    static let supporter = "com.alpsenel.kalesavasi.supporter"

    static let all = [gold, obsidian, marble, candy, rainbow, lightning, starfall, fireworks, hearts, banners, supporter]
}

/// One thing for sale, in shop order.
enum ShopItem: String, CaseIterable, Identifiable {
    case supporter, gold, obsidian, marble, candy, rainbow, lightning, starfall, fireworks, hearts, banners
    var id: String { rawValue }

    var productID: String {
        switch self {
        case .supporter: return Catalog.supporter
        case .gold: return Catalog.gold
        case .obsidian: return Catalog.obsidian
        case .marble: return Catalog.marble
        case .candy: return Catalog.candy
        case .rainbow: return Catalog.rainbow
        case .lightning: return Catalog.lightning
        case .starfall: return Catalog.starfall
        case .fireworks: return Catalog.fireworks
        case .hearts: return Catalog.hearts
        case .banners: return Catalog.banners
        }
    }

    static func with(productID id: String) -> ShopItem? { allCases.first { $0.productID == id } }

    /// The list price in US dollars, as set up in App Store Connect and `Products.storekit`. Only
    /// shown in debug builds when StoreKit has not delivered the product (the simulator launched
    /// outside Xcode has no StoreKit configuration).
    var referencePrice: String {
        switch self {
        case .gold, .obsidian: return "$2.99"
        case .marble, .candy, .hearts: return "$1.99"
        case .rainbow, .lightning, .starfall, .fireworks, .banners: return "$0.99"
        case .supporter: return "$4.99"
        }
    }

    var skin: Skin? {
        switch self {
        case .gold: return .gold
        case .obsidian: return .obsidian
        case .marble: return .marble
        case .candy: return .candy
        default: return nil
        }
    }

    var trail: Trail? {
        switch self {
        case .rainbow: return .rainbow
        case .lightning: return .lightning
        case .starfall: return .starfall
        default: return nil
        }
    }
}

/// A cosmetic that may need a product. `nil` products means it is free (the defaults).
protocol Cosmetic {
    /// Any one of these products unlocks it.
    var products: [String] { get }
}

extension Cosmetic {
    func unlocked(by owned: Set<String>) -> Bool { products.isEmpty || products.contains(where: owned.contains) }
}

// MARK: - The cosmetics

enum Skin: String, CaseIterable, Identifiable, Cosmetic {
    case classic, gold, obsidian, marble, candy, royal
    var id: String { rawValue }
    var index: Int { Skin.allCases.firstIndex(of: self) ?? 0 }
    var products: [String] {
        switch self {
        case .classic: return []
        case .gold: return [Catalog.gold]
        case .obsidian: return [Catalog.obsidian]
        case .marble: return [Catalog.marble]
        case .candy: return [Catalog.candy]
        case .royal: return [Catalog.supporter]
        }
    }
}

enum Trail: String, CaseIterable, Identifiable, Cosmetic {
    case none, rainbow, lightning, starfall, royal
    var id: String { rawValue }
    var products: [String] {
        switch self {
        case .none: return []
        case .rainbow: return [Catalog.rainbow]
        case .lightning: return [Catalog.lightning]
        case .starfall: return [Catalog.starfall]
        case .royal: return [Catalog.supporter]
        }
    }
    /// Main colours, for previews and the shop.
    var colors: [UInt32] {
        switch self {
        case .none: return [0xffffff]
        case .rainbow: return [0xff3b3b, 0xff9a1f, 0xffe14a, 0x4ed96a, 0x3fa8ff, 0x9a5cff]
        case .lightning: return [0xffffff, 0xbfe6ff, 0x5fb8ff]
        case .starfall: return [0xfff2b0, 0xffd34d, 0xf2a516]
        case .royal: return [0x8a3cff, 0xb57dff, 0xf2c14e]
        }
    }
}

enum ImpactEffect: String, CaseIterable, Identifiable, Cosmetic {
    case none, fireworks
    var id: String { rawValue }
    var products: [String] { self == .fireworks ? [Catalog.fireworks] : [] }
}

enum HeartGem: String, CaseIterable, Identifiable, Cosmetic {
    case none, emerald, sapphire, amethyst, sunfire
    var id: String { rawValue }
    var index: Int { HeartGem.allCases.firstIndex(of: self) ?? 0 }
    var products: [String] { self == .none ? [] : [Catalog.hearts] }
    /// Crystal body and glow.
    var colors: (body: UInt32, glow: UInt32) {
        switch self {
        case .none: return (0xc2185b, 0xff2f7d)
        case .emerald: return (0x0b8a4c, 0x3dffa6)
        case .sapphire: return (0x1840c8, 0x5ab0ff)
        case .amethyst: return (0x7426c0, 0xc58bff)
        case .sunfire: return (0xd8500c, 0xffc23a)
        }
    }
}

enum Banner: String, CaseIterable, Identifiable, Cosmetic {
    case none, lion, dragon, eagle, wolf
    var id: String { rawValue }
    /// The Supporter Pack includes every crest.
    var products: [String] { self == .none ? [] : [Catalog.banners, Catalog.supporter] }
}

/// What one player's castle and shots look like.
struct Cosmetics: Equatable, Codable {
    var skin = Skin.classic
    var trail = Trail.none
    var impact = ImpactEffect.none
    var gem = HeartGem.none
    var banner = Banner.none
    /// Owns the Supporter Pack: a crown on their name plates.
    var supporter = false

    static let plain = Cosmetics()

    var style: BrickStyle { BrickStyle(skin: skin, gem: gem) }

    enum CodingKeys: String, CodingKey { case skin, trail, impact, gem, banner, supporter }

    init() {}

    init(skin: Skin = .classic, trail: Trail = .none, impact: ImpactEffect = .none, gem: HeartGem = .none, banner: Banner = .none, supporter: Bool = false) {
        self.skin = skin; self.trail = trail; self.impact = impact; self.gem = gem; self.banner = banner; self.supporter = supporter
    }

    /// Reads what another device sent. Unknown or malformed values fall back to the defaults, so a
    /// newer build's cosmetics never break an older one's message, nor the other way round.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        self.init(raw: s(.skin), trail: s(.trail), impact: s(.impact), gem: s(.gem), banner: s(.banner),
                  supporter: ((try? c.decodeIfPresent(Bool.self, forKey: .supporter)) ?? nil) ?? false)
    }

    init(raw skin: String?, trail: String?, impact: String?, gem: String?, banner: String?, supporter: Bool?) {
        self.skin = skin.flatMap(Skin.init(rawValue:)) ?? .classic
        self.trail = trail.flatMap(Trail.init(rawValue:)) ?? .none
        self.impact = impact.flatMap(ImpactEffect.init(rawValue:)) ?? .none
        self.gem = gem.flatMap(HeartGem.init(rawValue:)) ?? .none
        self.banner = banner.flatMap(Banner.init(rawValue:)) ?? .none
        self.supporter = supporter ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(skin.rawValue, forKey: .skin)
        try c.encode(trail.rawValue, forKey: .trail)
        try c.encode(impact.rawValue, forKey: .impact)
        try c.encode(gem.rawValue, forKey: .gem)
        try c.encode(banner.rawValue, forKey: .banner)
        try c.encode(supporter, forKey: .supporter)
    }
}

/// The part of a player's cosmetics that changes how bricks look; looks are cached per style.
struct BrickStyle: Hashable {
    var skin = Skin.classic
    var gem = HeartGem.none
    static let plain = BrickStyle()
    /// Small, unique per style: fits the brick look caches' keys.
    var key: Int { skin.index * 8 + gem.index }
}

// MARK: - Profile: what the player has equipped

extension Profile {
    /// What the player has picked, limited to what the store says they own. Something no longer
    /// owned (a refund, a family share that ended) quietly falls back to the default.
    func cosmetics(owned: Set<String>) -> Cosmetics {
        var c = Cosmetics()
        if let s = Skin(rawValue: equipSkin), s.unlocked(by: owned) { c.skin = s }
        if let t = Trail(rawValue: equipTrail), t.unlocked(by: owned) { c.trail = t }
        if let i = ImpactEffect(rawValue: equipImpact), i.unlocked(by: owned) { c.impact = i }
        if let g = HeartGem(rawValue: equipGem), g.unlocked(by: owned) { c.gem = g }
        if let b = Banner(rawValue: equipBanner), b.unlocked(by: owned) { c.banner = b }
        c.supporter = owned.contains(Catalog.supporter)
        return c
    }
}

// MARK: - Net

extension NetMessage {
    /// The sender's cosmetics, sent with "hello" as optional fields that older builds ignore.
    var cosmetics: Cosmetics { Cosmetics(raw: skin, trail: trail, impact: impact, gem: gem, banner: banner, supporter: supporter) }

    mutating func attach(_ c: Cosmetics) {
        skin = c.skin.rawValue; trail = c.trail.rawValue; impact = c.impact.rawValue
        gem = c.gem.rawValue; banner = c.banner.rawValue; supporter = c.supporter
    }
}

// MARK: - Banner crests

/// The crests on a castle's flag, drawn in code: a lion's head, a dragon, a spread eagle and a wolf's head.
enum Emblem {
    private static var cache: [String: UIImage] = [:]

    /// The flag cloth: the team colour with the crest in gold, framed by a gold border.
    static func flag(_ b: Banner, color: UInt32, size: CGSize = CGSize(width: 256, height: 160)) -> UIImage {
        let key = "flag-\(b.rawValue)-\(color)-\(Int(size.width))"
        if let hit = cache[key] { return hit }
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let g = ctx.cgContext, r = CGRect(origin: .zero, size: size)
            g.setFillColor(UIColor(hex: color).cgColor)
            g.fill(r)
            // Soft fold shading so the cloth does not look flat.
            let folds = 3
            for i in 0..<folds {
                let x = r.width * CGFloat(i) / CGFloat(folds)
                let space = CGColorSpaceCreateDeviceRGB()
                let grad = CGGradient(colorsSpace: space, colors: [UIColor(white: 0, alpha: 0.18).cgColor, UIColor(white: 1, alpha: 0.08).cgColor, UIColor(white: 0, alpha: 0.18).cgColor] as CFArray, locations: [0, 0.5, 1])!
                g.saveGState()
                g.clip(to: CGRect(x: x, y: 0, width: r.width / CGFloat(folds), height: r.height))
                g.drawLinearGradient(grad, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + r.width / CGFloat(folds), y: 0), options: [])
                g.restoreGState()
            }
            let gold = UIColor(hex: 0xf2c14e)
            g.setStrokeColor(gold.cgColor)
            g.setLineWidth(size.height * 0.05)
            g.stroke(r.insetBy(dx: size.height * 0.06, dy: size.height * 0.06))
            if b != .none {
                let side = min(r.width, r.height) * 0.78
                draw(b, in: CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side), ctx: g, fill: gold, line: UIColor(hex: 0x3a2205))
            }
        }
        cache[key] = img
        return img
    }

    /// The crest alone on a clear ground, for the shop.
    static func crest(_ b: Banner, size: CGFloat = 160, fill: UIColor = UIColor(hex: 0xf2c14e)) -> UIImage {
        let key = "crest-\(b.rawValue)-\(Int(size))-\(fill.hashValue)"
        if let hit = cache[key] { return hit }
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            draw(b, in: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.04, dy: size * 0.04), ctx: ctx.cgContext, fill: fill, line: UIColor(hex: 0x2a1a0e))
        }
        cache[key] = img
        return img
    }

    /// Draws a crest into `r`, built from points on a 100 × 100 grid.
    static func draw(_ b: Banner, in r: CGRect, ctx g: CGContext, fill: UIColor, line: UIColor) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x / 100, y: r.minY + r.height * y / 100) }
        func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: pts.map { p($0.0, $0.1) })
            path.closeSubpath()
            return path
        }
        let lw = r.width * 0.025
        func paint(_ path: CGPath, _ color: UIColor = fill) {
            g.addPath(path); g.setFillColor(color.cgColor); g.fillPath()
            g.addPath(path); g.setStrokeColor(line.cgColor); g.setLineWidth(lw); g.setLineJoin(.round); g.strokePath()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) {
            g.setFillColor(line.cgColor)
            g.fillEllipse(in: CGRect(x: p(x, y).x - r.width * rad / 100, y: p(x, y).y - r.width * rad / 100, width: r.width * rad / 50, height: r.width * rad / 50))
        }
        let dark = fill.blended(0.28)
        switch b {
        case .none:
            break
        case .lion:
            // A mane of flame-like points round a broad face.
            var mane: [(CGFloat, CGFloat)] = []
            for i in 0..<28 {
                let a = Double(i) / 28 * 2 * .pi - .pi / 2, rad: CGFloat = i % 2 == 0 ? 48 : 36
                mane.append((50 + rad * CGFloat(cos(a)), 52 + rad * CGFloat(sin(a))))
            }
            paint(poly(mane), dark)
            paint(poly([(30, 30), (36, 18), (44, 28)]))
            paint(poly([(70, 30), (64, 18), (56, 28)]))
            paint(poly([(26, 46), (34, 28), (50, 24), (66, 28), (74, 46), (72, 66), (60, 80), (50, 84), (40, 80), (28, 66)]))
            paint(poly([(42, 60), (58, 60), (50, 70)]), line)
            paint(poly([(38, 72), (50, 70), (62, 72), (50, 78)]), fill)
            dot(39, 48, 3.6); dot(61, 48, 3.6)
            g.setStrokeColor(line.cgColor); g.setLineWidth(lw)
            g.move(to: p(33, 42)); g.addLine(to: p(44, 44)); g.move(to: p(67, 42)); g.addLine(to: p(56, 44)); g.strokePath()
        case .dragon:
            // A rearing dragon in profile: bat wings, a curled tail and a spiked head.
            paint(poly([(46, 40), (30, 10), (26, 26), (14, 18), (16, 36), (4, 34), (18, 52), (40, 54)]), dark)
            paint(poly([(54, 40), (74, 8), (76, 24), (90, 16), (86, 34), (98, 34), (82, 50), (60, 54)]), dark)
            paint(poly([(40, 86), (36, 66), (40, 48), (48, 36), (54, 28), (60, 20), (72, 16), (80, 22), (74, 26), (82, 30), (70, 32), (62, 40), (60, 54), (64, 70), (60, 86),
                        (54, 80), (50, 92), (44, 82)]))
            paint(poly([(60, 86), (72, 90), (84, 84), (78, 80), (70, 84)]))
            paint(poly([(60, 20), (58, 10), (64, 16)]))
            paint(poly([(66, 17), (68, 6), (71, 15)]))
            dot(70, 22, 2.4)
            paint(poly([(82, 30), (92, 26), (88, 32), (96, 34), (86, 36)]), UIColor(hex: 0xff7a1e))
        case .eagle:
            // A heraldic eagle displayed: wings spread, head turned.
            var left: [(CGFloat, CGFloat)] = [(44, 40)]
            var right: [(CGFloat, CGFloat)] = [(56, 40)]
            for i in 0..<5 {
                let t = CGFloat(i)
                left += [(36 - t * 7, 22 + t * 4), (40 - t * 7, 34 + t * 5)]
                right += [(64 + t * 7, 22 + t * 4), (60 + t * 7, 34 + t * 5)]
            }
            left += [(10, 66), (44, 56)]
            right += [(90, 66), (56, 56)]
            paint(poly(left), dark)
            paint(poly(right), dark)
            paint(poly([(42, 36), (50, 30), (58, 36), (60, 58), (56, 70), (62, 88), (54, 82), (50, 92), (46, 82), (38, 88), (44, 70), (40, 58)]))
            paint(poly([(44, 34), (46, 18), (54, 12), (62, 16), (68, 22), (60, 24), (58, 32), (50, 36)]))
            paint(poly([(62, 16), (72, 18), (66, 26), (64, 21)]), UIColor(hex: 0xffd34d))
            dot(56, 19, 2.2)
            paint(poly([(40, 88), (34, 96), (44, 92)]), fill)
            paint(poly([(60, 88), (66, 96), (56, 92)]), fill)
        case .wolf:
            // A wolf's head, front on: tall ears, a long muzzle and narrowed eyes.
            paint(poly([(22, 44), (18, 8), (40, 28)]), dark)
            paint(poly([(78, 44), (82, 8), (60, 28)]), dark)
            paint(poly([(22, 44), (34, 26), (50, 22), (66, 26), (78, 44), (84, 60), (70, 64), (62, 76), (50, 94), (38, 76), (30, 64), (16, 60)]))
            paint(poly([(26, 38), (22, 16), (34, 30)]), dark.blended(0.2))
            paint(poly([(74, 38), (78, 16), (66, 30)]), dark.blended(0.2))
            paint(poly([(40, 58), (50, 50), (60, 58), (56, 78), (50, 90), (44, 78)]), fill.withAlphaComponent(1).blended(-0.25))
            paint(poly([(44, 80), (56, 80), (50, 90)]), line)
            paint(poly([(32, 48), (44, 50), (40, 54)]), line)
            paint(poly([(68, 48), (56, 50), (60, 54)]), line)
        }
    }
}

private extension UIColor {
    /// Darker for a positive amount, lighter for a negative one.
    func blended(_ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        if k >= 0 { return UIColor(red: r * (1 - k), green: g * (1 - k), blue: b * (1 - k), alpha: a) }
        let t = -k
        return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: a)
    }
}

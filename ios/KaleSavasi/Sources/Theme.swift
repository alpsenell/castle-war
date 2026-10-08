import SwiftUI
import UIKit

// The Keepfall 2.0 look: carved wood, chiselled stone, iron rivets, torchlit gold and parchment.
// Every texture is drawn in code once and cached; there are no image assets.

// MARK: - Tokens

enum Theme {
    /// Scale for theme sizes: 1 on an iPhone in landscape, up to 1.45 on a large iPad.
    static let unit: CGFloat = {
        let b = UIScreen.main.bounds
        let w = max(b.width, b.height), h = min(b.width, b.height)
        return min(1.45, max(0.8, min(w / 844, h / 390)))
    }()
    static var roomy: Bool { unit > 1.2 }

    static let ink = Color(hex: 0x2a1a0e)
    static let text = Color(hex: 0x3d2914)
    static let muted = Color(hex: 0x86684a)
    static let cream = Color(hex: 0xfff3d6)
    static let woodLight = Color(hex: 0xc98f52), wood = Color(hex: 0x98612f), woodDark = Color(hex: 0x5a3519)
    static let stoneLight = Color(hex: 0xc4beb2), stone = Color(hex: 0x8d877c), stoneDark = Color(hex: 0x58534b)
    static let parchment = Color(hex: 0xf7e8c6), parchmentDark = Color(hex: 0xe6cf9f), parchmentEdge = Color(hex: 0xb88c50)
    static let iron = Color(hex: 0x45474c), ironLight = Color(hex: 0xa3a7ad)
    static let gold = Color(hex: 0xf6b928), goldLight = Color(hex: 0xffe38a), goldDark = Color(hex: 0xb06c06)
    static let red = Color(hex: 0xd63a2c), redDark = Color(hex: 0x8a1c13)
    static let blue = Color(hex: 0x2e7fd9), blueDark = Color(hex: 0x1a4b8f)
    static let green = Color(hex: 0x55b232), greenDark = Color(hex: 0x2c6d17)
    static let orange = Color(hex: 0xea6a1f), orangeDark = Color(hex: 0x9a3b0b)
    static let purple = Color(hex: 0x8a4fd0), purpleDark = Color(hex: 0x4f2683)
    static let teal = Color(hex: 0x23a596), tealDark = Color(hex: 0x10635a)
    static let heart = Color(hex: 0xe83372)
    static let shield = Color(hex: 0x4aa3f0)

    static func team(_ side: Int) -> Color { [red, blue, Color(hex: 0x3f9e3a), gold][max(0, side) % 4] }

    /// Titles and numbers.
    static func display(_ size: CGFloat) -> Font { .system(size: size * unit, weight: .black, design: .rounded) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size * unit, weight: weight, design: .rounded) }
    static func icon(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size * unit, weight: weight) }
}

extension Int { var u: CGFloat { CGFloat(self) * Theme.unit } }
extension Double { var u: CGFloat { CGFloat(self) * Theme.unit } }
extension CGFloat { var u: CGFloat { self * Theme.unit } }

extension Color {
    func mix(_ other: Color, _ t: Double) -> Color {
        var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), b = a
        UIColor(self).getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
        UIColor(other).getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
        let k = CGFloat(t)
        return Color(red: Double(a.0 + (b.0 - a.0) * k), green: Double(a.1 + (b.1 - a.1) * k),
                     blue: Double(a.2 + (b.2 - a.2) * k), opacity: Double(a.3 + (b.3 - a.3) * k))
    }
    func lighter(_ t: Double = 0.3) -> Color { mix(.white, t) }
    func darker(_ t: Double = 0.3) -> Color { mix(.black, t) }
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b < 0.55
    }
}

/// Light taps on the main buttons, following the player's vibration setting.
enum Haptics {
    static var enabled = true
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        if enabled { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }
}

// MARK: - The old names, now drawn with the theme

/// The 1.x palette names, mapped onto the theme so older call sites pick up the new look.
enum Paint {
    static let ink = Theme.ink, muted = Theme.muted, track = Theme.parchmentDark
    static let red = Theme.red, redDark = Theme.redDark
    static let blue = Theme.blue, blueDark = Theme.blueDark
    static let yellow = Theme.gold, yellowDark = Theme.goldDark
    static let heart = Theme.heart
    static let green = Theme.green, gold = Theme.gold
    static func team(_ side: Int) -> Color { Theme.team(side) }
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// A raised surface: parchment by default, or a bevelled face in the given colour.
struct Plate: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = .white
    func body(content: Content) -> some View {
        content.background {
            if fill == .white { ParchmentPanel(radius: radius, drop: 4, burn: false) } else { Bevel(face: fill, radius: radius, depth: 4) }
        }
    }
}

/// A bevelled button in any two colours; `ThemeButtonStyle` with a custom tone.
struct ChunkyButton: ButtonStyle {
    var color: Color
    var dark: Color
    var fg: Color = .white
    var size: CGFloat = 18
    var fill = true
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        ThemeButtonStyle(tone: Tone(face: color, edge: dark, fg: fg), size: size, fill: fill, compact: compact).makeBody(configuration: configuration)
    }
}

/// A progress bar: a dark wooden groove with a glossy jewel fill.
struct Meter: View {
    var value: Double
    var color: Color
    var track: Color = Paint.track
    var height: CGFloat = 6
    var body: some View {
        let h = max(4, height.u)
        GeometryReader { g in
            let v = min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule().fill(track == Paint.track ? Theme.woodDark : track)
                    .overlay(Capsule().stroke(Color.black.opacity(0.35), lineWidth: 2).offset(y: 1).clipShape(Capsule()))
                if v > 0 { JewelFill(color: color).frame(width: max(h, g.size.width * v)) }
            }
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: h >= 8 ? 1.5 : 1))
        }
        .frame(height: h)
    }
}

/// A glossy capsule of colour, like a cut gem.
struct JewelFill: View {
    let color: Color
    var body: some View {
        Capsule().fill(LinearGradient(stops: [
            .init(color: color.lighter(0.6), location: 0),
            .init(color: color.lighter(0.25), location: 0.38),
            .init(color: color, location: 0.5),
            .init(color: color.darker(0.3), location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Text treatments

/// A heavy outline and a hard drop shadow, for titles and numbers that sit on busy backgrounds.
struct Embossed: ViewModifier {
    var color: Color = Theme.ink
    var width: CGFloat = 1.5
    var drop: CGFloat = 3
    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: -width)
            .shadow(color: color, radius: 0, x: 0, y: drop)
    }
}

extension View {
    func embossed(_ color: Color = Theme.ink, width: CGFloat = 1.5, drop: CGFloat = 3) -> some View {
        modifier(Embossed(color: color, width: width, drop: drop))
    }
    /// Cut into a light surface: a pale highlight under the letters.
    func engraved() -> some View { shadow(color: .white.opacity(0.55), radius: 0, x: 0, y: 1) }
    func panel(_ surface: Surface, radius: CGFloat = 16) -> some View { background(SurfacePanel(surface: surface, radius: radius)) }
}

// MARK: - Procedural textures

private struct Rng {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double(s >> 11) / Double(UInt64(1) << 53)
    }
    mutating func r(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

/// Seamless tiles drawn once with Core Graphics.
enum Texture {
    static let wood = make(CGSize(width: 192, height: 72), seed: 7) { ctx, s, rng in
        fill(ctx, CGRect(origin: .zero, size: s), Theme.wood)
        let plank = s.height / 2
        for p in 0..<2 {
            let y0 = CGFloat(p) * plank
            let tint = rng.r(-0.08, 0.08)
            fill(ctx, CGRect(x: 0, y: y0, width: s.width, height: plank), tint > 0 ? .white : .black, abs(tint))
            for _ in 0..<18 {
                let y = y0 + CGFloat(rng.r(2, Double(plank) - 2)), amp = CGFloat(rng.r(0.3, 2.4))
                let k = Double(Int(rng.r(1, 3.99))), ph = rng.r(0, 2 * .pi)
                let path = CGMutablePath()
                for i in 0...48 {
                    let x = s.width * CGFloat(i) / 48
                    let pt = CGPoint(x: x, y: y + amp * CGFloat(sin(2 * .pi * k * Double(x / s.width) + ph)))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.addPath(path)
                let light = rng.next() < 0.3
                ctx.setStrokeColor(UIColor(light ? Theme.woodLight : Theme.woodDark).withAlphaComponent(rng.r(0.12, 0.38)).cgColor)
                ctx.setLineWidth(CGFloat(rng.r(0.4, 1.5)))
                ctx.strokePath()
            }
            if rng.next() < 0.8 {
                let c = CGPoint(x: rng.r(24, Double(s.width) - 24), y: Double(y0 + plank / 2) + rng.r(-6, 6))
                for ring in 0..<4 {
                    let w = CGFloat(4 + ring * 3), h = 2 + CGFloat(ring) * 1.4
                    ctx.setStrokeColor(UIColor(Theme.woodDark).withAlphaComponent(0.35 - Double(ring) * 0.06).cgColor)
                    ctx.setLineWidth(1)
                    ctx.strokeEllipse(in: CGRect(x: c.x - w, y: c.y - h, width: w * 2, height: h * 2))
                }
            }
            fill(ctx, CGRect(x: 0, y: y0, width: s.width, height: 1.2), .black, 0.45)
            fill(ctx, CGRect(x: 0, y: y0 + 1.2, width: s.width, height: 0.8), .white, 0.14)
        }
    }

    static let stone = make(CGSize(width: 128, height: 96), seed: 11) { ctx, s, rng in
        fill(ctx, CGRect(origin: .zero, size: s), Theme.stoneDark)
        let rowH: CGFloat = 24, blockW: CGFloat = 64
        for row in 0..<4 {
            let y = CGFloat(row) * rowH
            let shift: CGFloat = row % 2 == 0 ? 0 : -blockW / 2
            var shades: [Double] = []
            for _ in 0..<2 { shades.append(rng.r(-0.12, 0.12)) }
            for i in 0..<3 {
                let x = shift + CGFloat(i) * blockW
                guard x < s.width else { continue }
                let shade = shades[(i + 2) % 2]
                let r = CGRect(x: x, y: y, width: blockW, height: rowH).insetBy(dx: 1.4, dy: 1.4)
                let path = UIBezierPath(roundedRect: r, cornerRadius: 3).cgPath
                ctx.addPath(path)
                ctx.setFillColor(UIColor(Theme.stone.mix(shade > 0 ? .white : .black, abs(shade))).cgColor)
                ctx.fillPath()
                fill(ctx, CGRect(x: r.minX + 2, y: r.minY, width: r.width - 4, height: 1.4), .white, 0.28)
                fill(ctx, CGRect(x: r.minX + 2, y: r.maxY - 1.6, width: r.width - 4, height: 1.6), .black, 0.3)
                for _ in 0..<26 {
                    let d = CGFloat(rng.r(0.6, 1.8))
                    let pt = CGPoint(x: Double(r.minX) + rng.r(2, Double(r.width) - 2), y: Double(r.minY) + rng.r(2, Double(r.height) - 2))
                    ctx.setFillColor(UIColor(rng.next() < 0.5 ? .black : .white).withAlphaComponent(rng.r(0.06, 0.2)).cgColor)
                    ctx.fillEllipse(in: CGRect(x: pt.x, y: pt.y, width: d, height: d))
                }
            }
        }
    }

    static let parchment = make(CGSize(width: 160, height: 160), seed: 23) { ctx, s, rng in
        fill(ctx, CGRect(origin: .zero, size: s), Theme.parchment)
        let space = CGColorSpaceCreateDeviceRGB()
        for _ in 0..<26 {
            let c = CGPoint(x: rng.r(0, Double(s.width)), y: rng.r(0, Double(s.height)))
            let rad = CGFloat(rng.r(10, 46))
            let tone = UIColor(rng.next() < 0.75 ? Theme.parchmentDark : Theme.cream)
            let a = rng.r(0.15, 0.5)
            guard let grad = CGGradient(colorsSpace: space, colors: [tone.withAlphaComponent(a).cgColor, tone.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) else { continue }
            for dx in [-s.width, 0, s.width] {
                for dy in [-s.height, 0, s.height] {
                    let p = CGPoint(x: c.x + dx, y: c.y + dy)
                    ctx.drawRadialGradient(grad, startCenter: p, startRadius: 0, endCenter: p, endRadius: rad, options: [])
                }
            }
        }
        for _ in 0..<70 {
            let x = rng.r(0, Double(s.width)), y = rng.r(0, Double(s.height)), len = rng.r(2, 7), ang = rng.r(0, .pi)
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + len * cos(ang), y: y + len * sin(ang)))
            ctx.setStrokeColor(UIColor(Theme.parchmentEdge).withAlphaComponent(rng.r(0.08, 0.22)).cgColor)
            ctx.setLineWidth(0.6)
            ctx.strokePath()
        }
    }

    private static func fill(_ ctx: CGContext, _ r: CGRect, _ c: Color, _ alpha: Double = 1) {
        ctx.setFillColor(UIColor(c).withAlphaComponent(alpha).cgColor)
        ctx.fill(r)
    }

    private static func make(_ size: CGSize, seed: UInt64, _ draw: (CGContext, CGSize, inout Rng) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 2
        f.opaque = true
        var rng = Rng(s: seed)
        return UIGraphicsImageRenderer(size: size, format: f).image { draw($0.cgContext, size, &rng) }
    }
}

// MARK: - Materials

enum Surface {
    case wood, darkWood, stone, parchment
    var image: UIImage {
        switch self {
        case .wood, .darkWood: return Texture.wood
        case .stone: return Texture.stone
        case .parchment: return Texture.parchment
        }
    }
}

struct SurfaceFill: View {
    let surface: Surface
    var body: some View {
        Image(uiImage: surface.image).resizable(resizingMode: .tile)
            .overlay(surface == .darkWood ? Color.black.opacity(0.42) : .clear)
    }
}

/// A slab of material with a bevel, a dark outline and a hard drop edge.
struct SurfacePanel: View {
    var surface: Surface
    var radius: CGFloat = 16
    var drop: CGFloat = 4
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if drop > 0 { shape.fill(Theme.ink).offset(y: drop) }
            SurfaceFill(surface: surface).clipShape(shape)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.05), .black.opacity(0.32)], startPoint: .top, endPoint: .bottom),
                               lineWidth: min(5, max(2, radius * 0.2)))
            shape.strokeBorder(Theme.ink, lineWidth: 2.5)
        }
    }
}

struct WoodPanel: View {
    var radius: CGFloat = 16
    var dark = false
    var drop: CGFloat = 4
    var body: some View { SurfacePanel(surface: dark ? .darkWood : .wood, radius: radius, drop: drop) }
}

struct StonePanel: View {
    var radius: CGFloat = 16
    var drop: CGFloat = 4
    var body: some View { SurfacePanel(surface: .stone, radius: radius, drop: drop) }
}

/// Parchment with a darker, slightly burnt edge.
struct ParchmentPanel: View {
    var radius: CGFloat = 16
    var drop: CGFloat = 4
    var burn = true
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if drop > 0 { shape.fill(Theme.ink).offset(y: drop) }
            SurfaceFill(surface: .parchment).clipShape(shape)
            if burn {
                shape.stroke(Theme.parchmentEdge.opacity(0.75), lineWidth: 10).blur(radius: 6).clipShape(shape)
            }
            shape.strokeBorder(Theme.ink, lineWidth: 2.5)
        }
    }
}

/// A recessed area in parchment, for stats and tables.
struct InsetWell: View {
    var radius: CGFloat = 12
    var body: some View {
        let s = RoundedRectangle(cornerRadius: radius, style: .continuous)
        s.fill(Theme.parchmentDark.opacity(0.7))
            .overlay(s.stroke(Theme.woodDark.opacity(0.4), lineWidth: 3).blur(radius: 1.5).offset(y: 1.5).clipShape(s))
            .overlay(s.strokeBorder(Theme.parchmentEdge.opacity(0.8), lineWidth: 1))
    }
}

struct Rivet: View {
    var size: CGFloat = 7
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.ironLight, Theme.iron], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            .overlay(Circle().strokeBorder(Theme.ink.opacity(0.85), lineWidth: 1))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 1)
    }
}

/// Four iron rivets near the corners of whatever they cover.
struct Rivets: View {
    var inset: CGFloat
    var corner: CGFloat
    var size: CGFloat = 7
    var body: some View {
        ZStack {
            Rivet(size: size).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, corner).padding(.top, inset)
            Rivet(size: size).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.trailing, corner).padding(.top, inset)
            Rivet(size: size).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, corner).padding(.bottom, inset)
            Rivet(size: size).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, corner).padding(.bottom, inset)
        }
        .allowsHitTesting(false)
    }
}

/// A carved wooden frame round a parchment sheet, held by iron rivets: the background of every card.
struct FramedPanel: View {
    var radius: CGFloat = 22
    var body: some View {
        let band = 9.u, r = radius.u
        ZStack {
            WoodPanel(radius: r, drop: 5)
            ParchmentPanel(radius: max(4, r - band * 0.7), drop: 0)
                .overlay(RoundedRectangle(cornerRadius: max(4, r - band * 0.7), style: .continuous)
                    .stroke(Color.black.opacity(0.35), lineWidth: 3).blur(radius: 1).offset(y: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: max(4, r - band * 0.7), style: .continuous)))
                .padding(band)
            Rivets(inset: band / 2 - 3.5.u, corner: r + 4.u, size: 7.u)
        }
    }
}

// MARK: - Buttons

/// The colours of a bevelled control: its face, the darker side edge and the label.
struct Tone {
    var face: Color
    var edge: Color
    var fg: Color = .white
    static let gold = Tone(face: Theme.gold, edge: Theme.goldDark)
    static let green = Tone(face: Theme.green, edge: Theme.greenDark)
    static let red = Tone(face: Theme.red, edge: Theme.redDark)
    static let blue = Tone(face: Theme.blue, edge: Theme.blueDark)
    static let orange = Tone(face: Theme.orange, edge: Theme.orangeDark)
    static let purple = Tone(face: Theme.purple, edge: Theme.purpleDark)
    static let teal = Tone(face: Theme.teal, edge: Theme.tealDark)
    static let stone = Tone(face: Theme.stone, edge: Theme.stoneDark)
    static let wood = Tone(face: Theme.wood, edge: Theme.woodDark)
    static let dark = Tone(face: Color(hex: 0x3e2c1f), edge: Theme.ink, fg: Theme.gold)
    static let parchment = Tone(face: Theme.parchment, edge: Theme.parchmentEdge, fg: Theme.text)
}

/// The raised face behind every button: gradient, gloss, outline and a side edge that the face sinks onto.
struct Bevel: View {
    var face: Color
    var edge: Color?
    var radius: CGFloat = 14
    var depth: CGFloat = 5
    var pressed = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(edge ?? face.darker(0.45))
                .overlay(shape.strokeBorder(Theme.ink, lineWidth: 2))
                .offset(y: pressed ? 1 : depth)
            shape.fill(LinearGradient(colors: [face.lighter(0.3), face, face.darker(0.1)], startPoint: .top, endPoint: .bottom))
            shape.inset(by: 3).fill(LinearGradient(stops: [.init(color: .white.opacity(0.38), location: 0), .init(color: .white.opacity(0.08), location: 0.5),
                                                          .init(color: .clear, location: 0.52)], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(Theme.ink, lineWidth: 2)
        }
    }
}

struct ThemeButtonStyle: ButtonStyle {
    var tone: Tone = .gold
    var size: CGFloat = 18
    var fill = true
    var compact = false
    var radius: CGFloat = 14
    func makeBody(configuration: Configuration) -> some View {
        BevelButton(configuration: configuration, tone: tone, size: size, fill: fill, compact: compact, radius: radius)
    }
}

private struct BevelButton: View {
    let configuration: ButtonStyleConfiguration
    let tone: Tone
    let size: CGFloat
    let fill: Bool
    let compact: Bool
    let radius: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        let down = configuration.isPressed, depth = (compact ? 4 : 5).u
        let light = !tone.fg.isDark
        configuration.label
            .font(Theme.display(size))
            .foregroundStyle(tone.fg)
            .modifier(Embossed(color: light ? Theme.ink.opacity(0.8) : .clear, width: light ? 1 : 0, drop: light ? 2 : 0))
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, (compact ? 12 : 18).u).padding(.vertical, (compact ? 7 : 11).u)
            .frame(maxWidth: fill ? .infinity : nil)
            .background { Bevel(face: tone.face, edge: tone.edge, radius: radius.u, depth: depth, pressed: down) }
            .offset(y: down ? depth - 1 : 0)
            .scaleEffect(down && !still ? 0.98 : 1)
            .saturation(enabled ? 1 : 0.25).opacity(enabled ? 1 : 0.75)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: down)
            .onChange(of: down) { _, now in if now { Haptics.tap() } }
    }
}

/// A round bevelled button holding an icon.
struct RoundButtonStyle: ButtonStyle {
    var tone: Tone = .stone
    var size: CGFloat = 40
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed, depth = 4.u
        configuration.label
            .foregroundStyle(tone.fg)
            .modifier(Embossed(color: Theme.ink.opacity(tone.fg.isDark ? 0 : 0.8), width: tone.fg.isDark ? 0 : 1, drop: tone.fg.isDark ? 0 : 1.5))
            .frame(width: size.u, height: size.u)
            .background { Bevel(face: tone.face, edge: tone.edge, radius: size.u, depth: depth, pressed: down) }
            .offset(y: down ? depth - 1 : 0)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: down)
            .contentShape(Circle())
    }
}

/// A small capsule toggle: gold when picked, parchment otherwise.
struct PillStyle: ButtonStyle {
    var selected: Bool
    var size: CGFloat = 13
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Theme.body(size, .heavy))
            .foregroundStyle(selected ? .white : Theme.text)
            .modifier(Embossed(color: selected ? Theme.ink.opacity(0.75) : .clear, width: selected ? 0.8 : 0, drop: selected ? 1.5 : 0))
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 12.u).padding(.vertical, 6.u)
            .background {
                if selected {
                    Bevel(face: Theme.gold, edge: Theme.goldDark, radius: 100, depth: 3.u, pressed: down)
                } else {
                    Capsule().fill(Theme.parchment.opacity(0.9)).overlay(Capsule().strokeBorder(Theme.woodDark.opacity(0.7), lineWidth: 1.5))
                }
            }
            .scaleEffect(down ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: down)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(PillStyle(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "xmark").font(Theme.icon(15, .black)) }
            .buttonStyle(RoundButtonStyle(tone: .red, size: 38))
            .accessibilityLabel(Tx.close)
    }
}

// MARK: - Cards and headers

/// A modal card over a dimmed scene. Springs in when it appears.
struct Card<Content: View>: View {
    var width: CGFloat = 680
    var inset: CGFloat = 19
    @ViewBuilder var content: Content
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.38 : 0).ignoresSafeArea()
            content
                .padding(.horizontal, 24.u).padding(.vertical, inset.u)
                .frame(maxWidth: width.u)
                .background(FramedPanel())
                .padding(12)
                .scaleEffect(shown || still ? 1 : 0.86)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(still ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.68)) { shown = true }
        }
    }
}

/// A card title with the close button, shared by the menu's side panels.
struct PanelHeader: View {
    @EnvironmentObject var game: GameController
    let title: String
    var close: (() -> Void)?
    var body: some View {
        HStack(spacing: 10.u) {
            CardTitle(text: title)
            Spacer(minLength: 8)
            CloseButton { if let close { close() } else { game.panel = .home } }
        }
    }
}

struct CardTitle: View {
    let text: String
    var size: CGFloat = 26
    var body: some View {
        Text(text).font(Theme.display(size)).foregroundStyle(Theme.woodDark).engraved()
            .lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A cloth banner with notched tails.
struct Ribbon<Label: View>: View {
    var tone: Tone = .red
    @ViewBuilder var label: Label
    var body: some View {
        label
            .padding(.horizontal, 34.u).padding(.vertical, 8.u)
            .background { GeometryReader { g in cloth(g.size) } }
    }

    private func cloth(_ s: CGSize) -> some View {
        let tail = s.height * 1.1, drop = s.height * 0.26
        return ZStack {
            RibbonTail().fill(tone.edge).overlay(RibbonTail().stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineJoin: .round)))
                .frame(width: tail, height: s.height * 0.86)
                .position(x: tail * 0.3, y: s.height / 2 + drop)
            RibbonTail().fill(tone.edge).overlay(RibbonTail().stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineJoin: .round)))
                .frame(width: tail, height: s.height * 0.86)
                .scaleEffect(x: -1)
                .position(x: s.width - tail * 0.3, y: s.height / 2 + drop)
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [tone.face.lighter(0.3), tone.face, tone.face.darker(0.12)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 5).inset(by: 4).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.ink, lineWidth: 2.5))
                .frame(width: s.width - tail * 0.7, height: s.height)
                .position(x: s.width / 2, y: s.height / 2)
        }
    }
}

struct RibbonTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.3, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Badges and icons

struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY + r.height * 0.05), outer = min(r.width, r.height) / 2, inner = outer * 0.5
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5, rad = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + rad * CGFloat(cos(a)), y: c.y + rad * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// A chunky gold star, or an empty socket when not earned.
struct GemStar: View {
    var lit: Bool
    var size: CGFloat
    var body: some View {
        ZStack {
            StarShape().fill(Theme.ink).offset(y: size * 0.07)
            StarShape().fill(lit ? LinearGradient(colors: [Theme.goldLight, Theme.gold, Theme.goldDark], startPoint: .top, endPoint: .bottom)
                                 : LinearGradient(colors: [Theme.parchmentDark.darker(0.15), Theme.parchmentEdge.darker(0.1)], startPoint: .top, endPoint: .bottom))
            if lit { StarShape().fill(Color.white.opacity(0.45)).scaleEffect(0.4).offset(x: -size * 0.08, y: -size * 0.1) }
            StarShape().stroke(Theme.ink, style: StrokeStyle(lineWidth: max(1.2, size * 0.07), lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

struct StarRow: View {
    let earned: Int
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: size * 0.12) {
            ForEach(0..<3, id: \.self) { i in GemStar(lit: i < earned, size: (size * 1.25).u) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned)/3")
    }
}

struct ShieldShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: CGPoint(x: x, y: y + h * 0.14))
        p.addQuadCurve(to: CGPoint(x: x + w / 2, y: y), control: CGPoint(x: x + w * 0.28, y: y + h * 0.12))
        p.addQuadCurve(to: CGPoint(x: x + w, y: y + h * 0.14), control: CGPoint(x: x + w * 0.72, y: y + h * 0.12))
        p.addLine(to: CGPoint(x: x + w, y: y + h * 0.5))
        p.addQuadCurve(to: CGPoint(x: x + w / 2, y: y + h), control: CGPoint(x: x + w, y: y + h * 0.84))
        p.addQuadCurve(to: CGPoint(x: x, y: y + h * 0.5), control: CGPoint(x: x, y: y + h * 0.84))
        p.closeSubpath()
        return p
    }
}

/// A heraldic shield in a colour, rimmed in gold.
struct Crest<Content: View>: View {
    var color: Color
    var size: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            ShieldShape().fill(Theme.ink).offset(y: size * 0.05)
            ShieldShape().fill(LinearGradient(colors: [color.lighter(0.3), color, color.darker(0.3)], startPoint: .top, endPoint: .bottom))
            ShieldShape().stroke(LinearGradient(colors: [Theme.goldLight, Theme.goldDark], startPoint: .top, endPoint: .bottom), lineWidth: size * 0.08)
                .padding(size * 0.04)
            ShieldShape().stroke(Theme.ink, lineWidth: 1.5)
            content.offset(y: -size * 0.04)
        }
        .frame(width: size * 0.86, height: size)
    }
}

struct LevelBadge: View {
    let level: Int
    var size: CGFloat = 34
    var body: some View {
        Crest(color: Theme.blue, size: size.u) {
            Text("\(level)").font(.system(size: size.u * 0.42, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white).embossed(width: 1, drop: 1.5)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
    }
}

/// A round emblem: a symbol on a jewel face in a metal rim. Dull stone when not earned.
struct Medallion: View {
    let symbol: String
    var tone: Tone = .gold
    var size: CGFloat = 44
    var lit = true
    var body: some View {
        let s = size.u
        ZStack {
            Circle().fill(Theme.ink).offset(y: s * 0.05)
            Circle().fill(RadialGradient(colors: lit ? [tone.face.lighter(0.4), tone.face, tone.edge] : [Theme.stoneLight, Theme.stone, Theme.stoneDark],
                                         center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: s * 0.62))
            Circle().strokeBorder(LinearGradient(colors: lit ? [Theme.goldLight, Theme.goldDark] : [Theme.ironLight, Theme.iron], startPoint: .top, endPoint: .bottom),
                                  lineWidth: s * 0.1)
            Circle().strokeBorder(Theme.ink, lineWidth: 1.5)
            Image(systemName: symbol).font(.system(size: s * 0.4, weight: .heavy))
                .foregroundStyle(lit ? Color.white : Theme.stoneLight.lighter(0.3))
                .embossed(Theme.ink.opacity(lit ? 0.8 : 0.4), width: 0.8, drop: 1.5)
        }
        .frame(width: s, height: s)
    }
}

/// Light rays fanning out from the centre, for illustrated tiles.
struct Sunburst: Shape {
    var rays = 14
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), len = hypot(r.width, r.height)
        for i in 0..<rays {
            let a0 = 2 * Double.pi * Double(i) / Double(rays), a1 = a0 + .pi / Double(rays)
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + len * CGFloat(cos(a0)), y: c.y + len * CGFloat(sin(a0))))
            p.addLine(to: CGPoint(x: c.x + len * CGFloat(cos(a1)), y: c.y + len * CGFloat(sin(a1))))
            p.closeSubpath()
        }
        return p
    }
}

/// A dark capsule with a coloured icon and number, for counts on busy backgrounds.
struct Pill: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.gold
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 4.u) {
            if let icon { Image(systemName: icon).font(Theme.icon(size * 0.95, .heavy)) }
            Text(text).font(Theme.body(size, .heavy)).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9.u).padding(.vertical, 4.u)
        .background(Capsule().fill(Color(hex: 0x24170d).opacity(0.85)).overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5)))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Theme.display(19)).monospacedDigit().foregroundStyle(Theme.text).engraved().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.body(11, .bold)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10.u).padding(.vertical, 6.u)
        .background(InsetWell(radius: 10.u))
    }
}

import UIKit

// Procedural surfaces. Everything the scene shows is generated at launch from a few noise
// fields, so the app ships no image files.

/// Smooth value noise that wraps at the edges, so textures built from it tile without seams.
struct TileNoise {
    private let size: Int
    private let grid: [Float]

    init(cells: Int, seed: UInt32) {
        size = cells
        var r = Mulberry32(seed)
        grid = (0..<cells * cells).map { _ in Float(r.next()) }
    }

    /// Value in 0...1 at a point given in 0...1 texture space.
    func value(_ u: Float, _ v: Float) -> Float {
        let x = u * Float(size), y = v * Float(size)
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        var fx = x - Float(x0), fy = y - Float(y0)
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        let xa = ((x0 % size) + size) % size, xb = (xa + 1) % size
        let ya = ((y0 % size) + size) % size, yb = (ya + 1) % size
        let a = grid[ya * size + xa], b = grid[ya * size + xb], c = grid[yb * size + xa], d = grid[yb * size + xb]
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }
}

/// Several noise layers summed, each finer and fainter than the last.
struct Fractal {
    private let layers: [TileNoise]

    init(base: Int, octaves: Int, seed: UInt32) {
        layers = (0..<octaves).map { TileNoise(cells: base << $0, seed: seed &+ UInt32($0) &* 7919) }
    }

    func value(_ u: Float, _ v: Float) -> Float {
        var sum: Float = 0, amp: Float = 0.5, total: Float = 0
        for l in layers { sum += l.value(u, v) * amp; total += amp; amp *= 0.5 }
        return sum / total
    }
}

enum Textures {
    private static func image(_ w: Int, _ h: Int, _ fill: (Int, Int) -> (Float, Float, Float)) -> UIImage {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let c = fill(x, y), i = (y * w + x) * 4
            px[i] = UInt8(max(0, min(255, c.0 * 255)))
            px[i + 1] = UInt8(max(0, min(255, c.1 * 255)))
            px[i + 2] = UInt8(max(0, min(255, c.2 * 255)))
        } }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }

    /// Tangent-space normal map from a wrapping height field.
    private static func normalMap(_ n: Int, strength: Float, _ height: (Int, Int) -> Float) -> UIImage {
        var hs = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n { hs[y * n + x] = height(x, y) } }
        return image(n, n) { x, y in
            let l = hs[y * n + (x + n - 1) % n], r = hs[y * n + (x + 1) % n]
            let u = hs[((y + n - 1) % n) * n + x], d = hs[((y + 1) % n) * n + x]
            var nx = (l - r) * strength, ny = (u - d) * strength
            let len = (nx * nx + ny * ny + 1).squareRoot()
            nx /= len; ny /= len
            return (nx * 0.5 + 0.5, ny * 0.5 + 0.5, 1 / len * 0.5 + 0.5)
        }
    }

    /// Weathered stone: near-white so the block colour can be multiplied in.
    static let stone: (albedo: UIImage, normal: UIImage) = {
        let n = 256, broad = Fractal(base: 4, octaves: 4, seed: 11), grain = Fractal(base: 32, octaves: 3, seed: 23), pits = TileNoise(cells: 64, seed: 31)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        let albedo = image(n, n) { x, y in
            let b = broad.value(u(x), u(y)), g = grain.value(u(x), u(y))
            var v = 0.78 + (b - 0.5) * 0.3 + (g - 0.5) * 0.22
            if pits.value(u(x), u(y)) > 0.82 { v -= 0.12 }
            return (v, v * 0.99, v * 0.97)
        }
        let normal = normalMap(n, strength: 5) { x, y in
            broad.value(u(x), u(y)) * 0.5 + grain.value(u(x), u(y)) * 0.35 - (pits.value(u(x), u(y)) > 0.82 ? 0.25 : 0)
        }
        return (albedo, normal)
    }()

    static let grass: (albedo: UIImage, normal: UIImage) = {
        let n = 256, broad = Fractal(base: 4, octaves: 3, seed: 41), blades = Fractal(base: 48, octaves: 2, seed: 47)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        let albedo = image(n, n) { x, y in
            let b = broad.value(u(x), u(y)), g = blades.value(u(x), u(y))
            let v = 0.72 + (b - 0.5) * 0.36 + (g - 0.5) * 0.3
            return (0.36 * v + 0.06 * g, 0.60 * v, 0.20 * v)
        }
        let normal = normalMap(n, strength: 3) { x, y in blades.value(u(x), u(y)) * 0.6 + broad.value(u(x), u(y)) * 0.4 }
        return (albedo, normal)
    }()

    /// Broad light and dark patches laid over the grass so the field does not look tiled.
    static let fieldPatches: UIImage = {
        let n = 128, f = Fractal(base: 3, octaves: 4, seed: 53)
        return image(n, n) { x, y in
            let v = 0.82 + (f.value(Float(x) / Float(n), Float(y) / Float(n)) - 0.5) * 0.5
            return (v, v, v * 0.94)
        }
    }()

    static let waterNormal: UIImage = {
        let n = 256, a = Fractal(base: 8, octaves: 3, seed: 61), b = Fractal(base: 14, octaves: 2, seed: 67)
        return normalMap(n, strength: 4) { x, y in
            let u = Float(x) / Float(n), v = Float(y) / Float(n)
            return a.value(u, v) * 0.6 + b.value(u, v) * 0.4
        }
    }()

    /// Rows of overlapping roof slates.
    static let roof: (albedo: UIImage, normal: UIImage) = {
        let n = 128, rows = 8, wear = Fractal(base: 8, octaves: 3, seed: 71)
        func slate(_ x: Int, _ y: Int) -> (edge: Float, shade: Float) {
            let row = y * rows / n, fy = Float(y * rows % n) / Float(n)
            let shifted = x + (row % 2 == 0 ? 0 : n / (rows * 2)), fx = Float(shifted * rows % n) / Float(n)
            let edge: Float = (fx < 0.08 || fy < 0.1) ? 0 : 1
            return (edge, 0.86 + fy * 0.14)
        }
        let albedo = image(n, n) { x, y in
            let s = slate(x, y), w = wear.value(Float(x) / Float(n), Float(y) / Float(n))
            let v = (0.55 + s.edge * 0.4) * s.shade * (0.85 + w * 0.3)
            return (v, v, v)
        }
        let normal = normalMap(n, strength: 6) { x, y in
            let s = slate(x, y)
            return s.edge * s.shade
        }
        return (albedo, normal)
    }()

    static let wood: UIImage = {
        let n = 128, grain = Fractal(base: 4, octaves: 3, seed: 83)
        return image(n, n) { x, y in
            let g = grain.value(Float(x) / Float(n) * 0.25, Float(y) / Float(n))
            let line: Float = abs(sin((Float(y) / Float(n) * 22 + g * 5))) * 0.18
            let v = 0.75 + (g - 0.5) * 0.3 - line
            return (v, v * 0.92, v * 0.85)
        }
    }()

    // MARK: Bricks

    /// Distance to the nearest and second-nearest of a jittered grid of points that wraps at the
    /// edges: the cells of cracked ice and the chips in worn stone.
    private struct Cells {
        let n: Int
        let pts: [(Float, Float)]
        init(cells: Int, seed: UInt32) {
            n = cells
            var r = Mulberry32(seed)
            pts = (0..<cells * cells).map { _ in (Float(r.next()), Float(r.next())) }
        }
        func value(_ u: Float, _ v: Float) -> (f1: Float, f2: Float) {
            let x = u * Float(n), y = v * Float(n), cx = Int(x.rounded(.down)), cy = Int(y.rounded(.down))
            var f1: Float = 9, f2: Float = 9
            for dy in -1...1 { for dx in -1...1 {
                let gx = cx + dx, gy = cy + dy
                let p = pts[((gy % n + n) % n) * n + ((gx % n + n) % n)]
                let px = Float(gx) + p.0 - x, py = Float(gy) + p.1 - y
                let d = (px * px + py * py).squareRoot()
                if d < f1 { f2 = f1; f1 = d } else if d < f2 { f2 = d }
            } }
            return (f1, f2)
        }
    }

    /// A timber's face: long grain along u, a few knots, near-white so a stain can be multiplied in.
    static let timber: (albedo: UIImage, normal: UIImage) = {
        let n = 256, grain = Fractal(base: 4, octaves: 4, seed: 101), fine = Fractal(base: 64, octaves: 2, seed: 103), knots = Cells(cells: 3, seed: 107)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        func height(_ x: Int, _ y: Int) -> Float {
            let g = grain.value(u(x) * 0.25, u(y))
            let k = knots.value(u(x), u(y)).f1
            let warp = max(0, 0.22 - k) * 30
            let ring = sin((u(y) * 34 + g * 6 + warp) * .pi)
            return ring * 0.5 + 0.5 - max(0, 0.06 - k) * 6
        }
        let albedo = image(n, n) { x, y in
            let h = height(x, y), f = fine.value(u(x) * 0.2, u(y))
            let v = 0.7 + h * 0.18 + (f - 0.5) * 0.16
            return (v, v * 0.9, v * 0.8)
        }
        let normal = normalMap(n, strength: 2.2) { x, y in height(x, y) * 0.6 + fine.value(u(x) * 0.2, u(y)) * 0.4 }
        return (albedo, normal)
    }()

    /// A dressed stone block: broad mottling, chisel marks and chipped hollows.
    static let ashlar: (albedo: UIImage, normal: UIImage) = {
        let n = 256, broad = Fractal(base: 3, octaves: 4, seed: 113), grit = Fractal(base: 48, octaves: 3, seed: 127), chips = Cells(cells: 7, seed: 131)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        func height(_ x: Int, _ y: Int) -> Float {
            let c = chips.value(u(x), u(y))
            let hollow = max(0, 0.12 - (c.f2 - c.f1)) * 2.5
            return broad.value(u(x), u(y)) * 0.45 + grit.value(u(x), u(y)) * 0.4 - hollow
        }
        let albedo = image(n, n) { x, y in
            let b = broad.value(u(x), u(y)), g = grit.value(u(x), u(y)), h = height(x, y)
            var v = 0.8 + (b - 0.5) * 0.28 + (g - 0.5) * 0.2
            v -= max(0, 0.35 - h) * 0.25
            return (v, v * 0.98, v * 0.95)
        }
        let normal = normalMap(n, strength: 4.5) { x, y in height(x, y) }
        return (albedo, normal)
    }()

    /// Clear ice with a web of frozen cracks and a few trapped bubbles.
    static let ice: (albedo: UIImage, normal: UIImage) = {
        let n = 256, web = Cells(cells: 5, seed: 137), cloud = Fractal(base: 4, octaves: 3, seed: 139), bubbles = Cells(cells: 14, seed: 149)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        func crack(_ x: Int, _ y: Int) -> Float { let c = web.value(u(x), u(y)); return max(0, 1 - (c.f2 - c.f1) * 22) }
        let albedo = image(n, n) { x, y in
            let k = crack(x, y), c = cloud.value(u(x), u(y)), b = bubbles.value(u(x), u(y)).f1
            let v = 0.78 + (c - 0.5) * 0.2 + k * 0.22 + (b < 0.06 ? 0.15 : 0)
            return (v * 0.86, v * 0.95, v)
        }
        let normal = normalMap(n, strength: 3) { x, y in cloud.value(u(x), u(y)) * 0.4 - crack(x, y) * 0.5 }
        return (albedo, normal)
    }()

    /// Dark iron plate in bands, studded with rivets; `cracked` splits it with jagged fractures.
    static func ironPlate(cracked: Bool) -> (albedo: UIImage, normal: UIImage) {
        let n = 128, rust = Fractal(base: 4, octaves: 4, seed: 151), split = Cells(cells: 3, seed: 157)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        func height(_ x: Int, _ y: Int) -> Float {
            let fy = u(y) * 2, band = fy - fy.rounded(.down)
            var h: Float = band < 0.06 || band > 0.94 ? 0 : 0.6
            let rx = u(x) * 4, ry = u(y) * 2 * 1 + 0.5
            let dx = rx - rx.rounded(.down) - 0.5, dy = ry - ry.rounded(.down) - 0.5
            if band > 0.06 && band < 0.94, dx * dx + dy * dy * 4 < 0.02 { h = 1 }
            if cracked { let c = split.value(u(x), u(y)); if c.f2 - c.f1 < 0.035 { h -= 0.8 } }
            return h
        }
        let albedo = image(n, n) { x, y in
            let r = rust.value(u(x), u(y)), h = height(x, y)
            let v = 0.55 + h * 0.2 + (r - 0.5) * 0.25
            let rusty = max(0, r - 0.6) * 1.2
            return (v + rusty * 0.25, v * (1 - rusty * 0.2), v * (1 - rusty * 0.45))
        }
        let normal = normalMap(n, strength: 3) { x, y in height(x, y) }
        return (albedo, normal)
    }

    /// Overlapping wooden shingles for roofs.
    static let shingles: (albedo: UIImage, normal: UIImage) = {
        let n = 128, rows = 6, wear = Fractal(base: 8, octaves: 3, seed: 163)
        func cell(_ x: Int, _ y: Int) -> (edge: Float, shade: Float) {
            let row = y * rows / n, fy = Float(y * rows % n) / Float(n)
            let shifted = x + (row % 2 == 0 ? 0 : n / 8), fx = Float(shifted * 4 % n) / Float(n)
            let edge: Float = fx < 0.06 || fy > 0.92 ? 0 : 1
            return (edge, 0.8 + fy * 0.2)
        }
        let albedo = image(n, n) { x, y in
            let c = cell(x, y), w = wear.value(Float(x) / Float(n), Float(y) / Float(n))
            let v = (0.5 + c.edge * 0.45) * c.shade * (0.82 + w * 0.36)
            return (v, v, v)
        }
        let normal = normalMap(n, strength: 5) { x, y in let c = cell(x, y); return c.edge * c.shade }
        return (albedo, normal)
    }()

    /// Polished marble: near-white with soft grey veins that wander across the block.
    static let marble: (albedo: UIImage, normal: UIImage) = {
        let n = 256, warp = Fractal(base: 3, octaves: 4, seed: 211), cloud = Fractal(base: 6, octaves: 3, seed: 223), fine = Fractal(base: 24, octaves: 2, seed: 227)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        func vein(_ x: Int, _ y: Int) -> Float {
            let w = warp.value(u(x), u(y))
            let a = abs(sin((u(x) * 2 + u(y) * 3 + w * 4.5) * .pi))
            let b = abs(sin((u(x) * 5 - u(y) * 2 + w * 7) * .pi))
            return pow(1 - a, 9) * 0.9 + pow(1 - b, 14) * 0.5
        }
        let albedo = image(n, n) { x, y in
            let v = vein(x, y), c = cloud.value(u(x), u(y)), f = fine.value(u(x), u(y))
            let base = 0.93 + (c - 0.5) * 0.08 + (f - 0.5) * 0.04
            let k = max(0, base - v * 0.42)
            return (k, k * 0.995, k * 0.99)
        }
        let normal = normalMap(n, strength: 1.2) { x, y in cloud.value(u(x), u(y)) * 0.3 - vein(x, y) * 0.2 }
        return (albedo, normal)
    }()

    /// Hot cracks on black, as an emission map: the ember veins of obsidian stone.
    static let embers: UIImage = {
        let n = 256, web = Cells(cells: 6, seed: 233), heat = Fractal(base: 4, octaves: 3, seed: 239)
        func u(_ i: Int) -> Float { Float(i) / Float(n) }
        return image(n, n) { x, y in
            let c = web.value(u(x), u(y)), h = heat.value(u(x), u(y))
            let crack = min(1, max(0, 1 - (c.f2 - c.f1) * 16) * max(0, h * 1.8 - 0.25) * 1.4)
            return (crack * 1.0, crack * 0.36, crack * 0.06)
        }
    }()

    /// A four-pointed sparkle, white on clear, for starry trails and fireworks.
    static let sparkle: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
        let g = ctx.cgContext
        let colors = [UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        g.drawRadialGradient(glow, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 14, options: [])
        let path = CGMutablePath()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2, r: Double = i % 2 == 0 ? 31 : 6
            let p = CGPoint(x: 32 + r * cos(a), y: 32 + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        g.addPath(path)
        g.setFillColor(UIColor.white.cgColor)
        g.fillPath()
    }

    private static var tinted: [String: UIImage] = [:]

    /// A near-white texture with a colour multiplied in, cached per colour.
    static func tint(_ base: UIImage, _ key: String, _ hex: UInt32) -> UIImage {
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

    /// Where the sun sits: azimuth as a fraction of the panorama's width, elevation in radians.
    /// It is off to one side and a little behind the left-hand player, so both castles show lit and shaded faces.
    static let sunU: Float = 0.42, sunElevation: Float = 0.9

    /// The whole sky as one 2:1 panorama: haze at the horizon, deep blue overhead, sun and soft cloud.
    /// It is both what the player sees and what lights the scene.
    static let sky: UIImage = {
        let w = 1024, h = 512
        let cloud = Fractal(base: 6, octaves: 5, seed: 97)
        let sunU = Textures.sunU, sunEl = Textures.sunElevation
        return image(w, h) { x, y in
            let u = Float(x) / Float(w), el = (0.5 - Float(y) / Float(h)) * Float.pi      // +pi/2 straight up
            if el < 0 {
                // Below the horizon: the hazy green-grey of distant land, so light bounced from below stays natural.
                let t = min(1, -el / 0.5)
                return (0.62 - t * 0.3, 0.70 - t * 0.28, 0.60 - t * 0.34)
            }
            let t = min(1, el / (Float.pi / 2))
            let k = pow(1 - t, 3)                                  // haze gathers near the horizon
            var r = 0.16 + k * 0.66, g = 0.42 + k * 0.44, b = 0.90 + k * 0.08
            // Sun: angular distance from the pixel direction.
            let dAz = min(abs(u - sunU), 1 - abs(u - sunU)) * 2 * Float.pi
            let cosAng = sin(el) * sin(sunEl) + cos(el) * cos(sunEl) * cos(dAz)
            let ang = acos(max(-1, min(1, cosAng)))
            let glow = exp(-ang * 5) * 0.55 + (ang < 0.045 ? 3 : 0)
            r += glow; g += glow * 0.95; b += glow * 0.8
            // Cloud: thicker in a band above the horizon, thinning overhead.
            let c = cloud.value(u, Float(y) / Float(h) * 2.2)
            let cover = max(0, c - 0.52) * 3.2 * min(1, el / 0.12) * (1 - t * 0.6)
            let a = min(0.9, cover)
            r = r + (1.0 - r) * a; g = g + (1.0 - g) * a; b = b + (1.02 - b) * a
            return (r, g, b)
        }
    }()

    /// Soft round sprite for smoke, fire and dust.
    static let puff: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
        let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    /// Gold bullseye that marks the critical-hit target.
    static let bullseye: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
        let g = ctx.cgContext
        let rings: [(Double, UInt32, Double)] = [(58, 0x1b2a34, 0), (52, 0xf2cd37, 0), (34, 0x1b2a34, 9), (14, 0x1b2a34, 0)]
        for (r, hex, width) in rings {
            let rect = CGRect(x: 64 - r, y: 64 - r, width: r * 2, height: r * 2)
            if width > 0 { g.setStrokeColor(UIColor(hex: hex).cgColor); g.setLineWidth(width); g.strokeEllipse(in: rect) }
            else { g.setFillColor(UIColor(hex: hex).cgColor); g.fillEllipse(in: rect) }
        }
    }

    /// White symbol on a clear ground, for the balloon badges.
    static func symbol(_ name: String) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: 72, weight: .black)
        let base = UIImage(systemName: name, withConfiguration: cfg) ?? UIImage()
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { _ in
            let s = base.size, k = min(96 / max(s.width, 1), 96 / max(s.height, 1))
            let rect = CGRect(x: 64 - s.width * k / 2, y: 64 - s.height * k / 2, width: s.width * k, height: s.height * k)
            base.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: rect)
        }
    }
}

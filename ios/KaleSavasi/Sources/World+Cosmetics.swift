import SceneKit
import UIKit

// Shop effects in the match scene: premium cannonball trails and the fireworks impact. They are
// particles only, with no bodies, so they cannot change how a shot plays out.

extension World {
    /// Particle systems for a shop trail. `size` scales them (a mega ball is bigger).
    static func makeTrail(_ trail: Trail, size k: CGFloat) -> [SCNParticleSystem] {
        func base(_ image: UIImage, rate: CGFloat, life: CGFloat, size: CGFloat) -> SCNParticleSystem {
            let ps = SCNParticleSystem()
            ps.particleImage = image
            ps.birthRate = rate
            ps.particleLifeSpan = life
            ps.particleLifeSpanVariation = life * 0.2
            ps.particleSize = size * k
            ps.particleSizeVariation = size * k * 0.3
            ps.blendMode = .additive
            ps.isLightingEnabled = false
            ps.propertyControllers = [.opacity: fade]
            return ps
        }
        switch trail {
        case .none:
            return [makeTrail(color: 0xffffff, size: 0.5 * k, plain: true)]
        case .rainbow:
            // Each puff runs through the spectrum as it ages, so the trail lays out a rainbow behind the ball.
            let band = base(Textures.puff, rate: 150, life: 1.3, size: 0.62)
            band.particleVelocity = 0.2
            band.spreadingAngle = 180
            // The colour controller multiplies the particle colour, so it starts from white.
            band.particleColor = UIColor(white: 1, alpha: 0.85)
            band.blendMode = .alpha
            let spectrum = CAKeyframeAnimation()
            // The whole spectrum within the first part of a puff's life, so it shows close behind the ball.
            spectrum.values = (Trail.rainbow.colors + [Trail.rainbow.colors[5]]).map { UIColor(hex: $0) }
            spectrum.keyTimes = (0..<6).map { NSNumber(value: Double($0) / 5 * 0.42) } + [1]
            band.propertyControllers = [.opacity: curve([1, 1, 0.8, 0], [0, 0.45, 0.8, 1]), .color: SCNParticlePropertyController(animation: spectrum)]
            let core = base(Textures.puff, rate: 60, life: 0.2, size: 0.4)
            core.particleColor = UIColor(white: 1, alpha: 0.9)
            return [band, core]
        case .lightning:
            let glow = base(Textures.puff, rate: 90, life: 0.35, size: 0.45)
            glow.particleColor = UIColor(hex: 0x8fd0ff, alpha: 0.9)
            let sparks = base(Textures.puff, rate: 260, life: 0.22, size: 0.16)
            sparks.particleColor = UIColor(hex: 0xe8f6ff)
            sparks.particleVelocity = 9
            sparks.particleVelocityVariation = 6
            sparks.spreadingAngle = 180
            sparks.stretchFactor = 0.09
            // A flicker: sparks blink on and off as they fly.
            sparks.propertyControllers = [.opacity: curve([1, 0.15, 1, 0.3, 0.9, 0], [0, 0.18, 0.36, 0.55, 0.75, 1])]
            let arcs = base(Textures.puff, rate: 40, life: 0.12, size: 0.8)
            arcs.particleColor = UIColor(hex: 0x5fb8ff, alpha: 0.45)
            arcs.particleVelocity = 2
            arcs.spreadingAngle = 180
            return [glow, sparks, arcs]
        case .starfall:
            let glow = base(Textures.puff, rate: 80, life: 0.6, size: 0.55)
            glow.particleColor = UIColor(hex: 0xffd34d, alpha: 0.8)
            let stars = base(Textures.sparkle, rate: 70, life: 1.3, size: 0.55)
            stars.particleColor = UIColor(hex: 0xffe27a)
            stars.particleColorVariation = SCNVector4(0.04, 0.2, 0.1, 0)
            stars.particleVelocity = 1.4
            stars.particleVelocityVariation = 1
            stars.spreadingAngle = 180
            stars.acceleration = SCNVector3(0, -7, 0)
            stars.particleAngleVariation = 180
            stars.particleAngularVelocity = 160
            stars.particleAngularVelocityVariation = 120
            return [glow, stars]
        case .royal:
            let plume = base(Textures.puff, rate: 120, life: 0.75, size: 0.6)
            plume.particleColor = UIColor(hex: 0x8a3cff, alpha: 0.85)
            plume.particleVelocity = 0.3
            plume.spreadingAngle = 180
            let gold = base(Textures.sparkle, rate: 55, life: 1.0, size: 0.45)
            gold.particleColor = UIColor(hex: 0xf2c14e)
            gold.particleVelocity = 1.2
            gold.spreadingAngle = 180
            gold.acceleration = SCNVector3(0, -4, 0)
            gold.particleAngleVariation = 180
            gold.particleAngularVelocity = 120
            return [plume, gold]
        }
    }

    /// Fireworks on top of the normal dust: a few shells rise from the impact and burst in colour.
    func fireworks(at p: SIMD3<Float>) {
        let palette: [[UInt32]] = [[0xff3b5c, 0xffd34d], [0x3fa8ff, 0xffffff], [0x4ed96a, 0xfff2b0], [0xb57dff, 0xff8ad8], [0xffa51f, 0xff3b3b]]
        var rng = SystemRandomNumberGenerator()
        let pick = palette.shuffled(using: &rng)
        for i in 0..<4 {
            let delay = 0.08 + Double(i) * 0.22
            let at = p + SIMD3(Float.random(in: -3.5...3.5), Float.random(in: 3.5...6.5), Float.random(in: -3.5...3.5))
            let colors = pick[i % pick.count]
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                // The shell's climb, then the burst, its glitter falling, and a pop of light.
                self.burst(at: p + SIMD3(0, 0.6, 0), colors: [0xfff2b0], count: 18, speed: at.y - p.y > 5 ? 13 : 10, life: 0.35, size: 0.3,
                           accel: -4, cone: true, direction: simd_normalize(at - p), additive: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.burst(at: at, colors: colors, count: 240, speed: 17, life: 1.4, size: 0.75, accel: -5, cone: false, additive: true)
                    self.burst(at: at, colors: [0xffffff], count: 40, speed: 6, life: 1.6, size: 0.3, accel: -7, cone: false, additive: true)
                    self.flash(at: at, strength: 1400)
                }
            }
        }
    }
}

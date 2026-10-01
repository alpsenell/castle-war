import AVFoundation

/// Short synthesized sound effects; nothing is loaded from disk.
final class Sfx {
    enum Sound: CaseIterable { case fire, hit, thud, splash, win, lose, tick, crit, charged }

    var enabled = true
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var next = 0
    private let rate = 44100.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<5 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        for s in Sound.allCases { buffers[s] = make(s) }
        try? engine.start()
    }

    func play(_ s: Sound) {
        guard enabled, let b = buffers[s] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.scheduleBuffer(b, at: nil, options: [])
        p.play()
    }

    private func buffer(_ dur: Double, _ gen: (Double) -> Double) -> AVAudioPCMBuffer {
        let n = Int(dur * rate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        b.frameLength = AVAudioFrameCount(n)
        let d = b.floatChannelData![0]
        for i in 0..<n { d[i] = Float(max(-1, min(1, gen(Double(i) / rate)))) }
        return b
    }

    /// Filtered noise whose cutoff slides from f0 to f1, with an exponential fade.
    private func noise(_ dur: Double, _ f0: Double, _ f1: Double, _ gain: Double, highpass: Bool = false) -> (Double) -> Double {
        var lp = 0.0, hp = 0.0
        return { t in
            let fc = f0 * pow(f1 / f0, min(1, t / dur))
            let a = 1 - exp(-2 * Double.pi * fc / self.rate)
            var x = Double.random(in: -1...1)
            if highpass { hp += 0.05 * (x - hp); x -= hp }
            lp += a * (x - lp)
            return lp * gain * 2.2 * exp(-t * 6.9 / dur)
        }
    }

    private func sweep(_ dur: Double, _ f0: Double, _ f1: Double, _ gain: Double, delay: Double = 0, triangle: Bool = false) -> (Double) -> Double {
        var phase = 0.0
        return { t in
            let u = t - delay
            if u < 0 || u > dur { return 0 }
            let f = f0 * pow(f1 / f0, u / dur)
            phase += 2 * Double.pi * f / self.rate
            let w = triangle ? asin(sin(phase)) * 2 / Double.pi : sin(phase)
            return w * gain * exp(-u * 6.9 / dur)
        }
    }

    private func mix(_ dur: Double, _ parts: [(Double) -> Double]) -> AVAudioPCMBuffer {
        buffer(dur) { t in parts.reduce(0) { $0 + $1(t) } }
    }

    private func make(_ s: Sound) -> AVAudioPCMBuffer {
        switch s {
        case .fire: return mix(0.55, [noise(0.5, 900, 90, 0.7), sweep(0.45, 140, 38, 0.8)])
        case .hit: return mix(1.0, [noise(0.9, 2200, 120, 0.9), sweep(0.6, 90, 30, 0.7)])
        case .thud: return mix(0.4, [noise(0.35, 500, 80, 0.5), sweep(0.3, 80, 40, 0.4)])
        case .splash: return mix(0.6, [noise(0.6, 1800, 500, 0.6, highpass: true)])
        case .win: return mix(0.9, [523.0, 659, 784, 1047].enumerated().map { sweep(0.26, $0.element, $0.element, 0.25, delay: Double($0.offset) * 0.14, triangle: true) })
        case .lose: return mix(0.95, [392.0, 330, 262].enumerated().map { sweep(0.32, $0.element, $0.element, 0.25, delay: Double($0.offset) * 0.2, triangle: true) })
        case .tick: return mix(0.05, [sweep(0.04, 1200, 900, 0.12)])
        case .crit: return mix(0.5, [sweep(0.16, 880, 880, 0.22, triangle: true), sweep(0.3, 1320, 1320, 0.22, delay: 0.1, triangle: true)])
        case .charged: return mix(0.45, [sweep(0.4, 220, 880, 0.2, triangle: true)])
        }
    }
}

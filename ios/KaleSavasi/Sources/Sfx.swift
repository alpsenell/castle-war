import AVFoundation

/// Short synthesized sound effects; nothing is loaded from disk.
final class Sfx {
    enum Sound: CaseIterable {
        case fire, hit, thud, splash, win, lose, tick, crit, charged, woodBreak, stoneBreak, iceBreak, ironClang

        /// Higher-ranked sounds may take over a voice from lower-ranked ones, never the reverse.
        var rank: Int {
            switch self {
            case .thud: return 0
            case .woodBreak, .stoneBreak, .iceBreak, .ironClang: return 1
            case .splash: return 2
            default: return 3
            }
        }
        /// Shortest time between two plays of the same sound; contacts can ask every frame.
        var gap: Double {
            switch self {
            case .thud: return 0.22
            case .woodBreak, .stoneBreak, .iceBreak: return 0.09
            case .ironClang, .splash: return 0.15
            case .tick: return 0.03
            default: return 0
            }
        }
        var volume: Float {
            switch self {
            case .thud: return 0.55
            case .woodBreak, .stoneBreak, .iceBreak, .ironClang: return 0.75
            default: return 1
            }
        }
    }

    var enabled = true
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    /// Per voice: when its sound ends and how much that sound matters.
    private var busyUntil: [Double] = []
    private var rank: [Int] = []
    private var lastPlayed: [Sound: Double] = [:]
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private let rate = 44100.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<12 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        // Many voices at once would add up past full scale and crackle; a limiter keeps the sum clean.
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        engine.attach(limiter)
        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)
        busyUntil = Array(repeating: 0, count: players.count)
        rank = Array(repeating: 0, count: players.count)
        for s in Sound.allCases { buffers[s] = make(s) }
        try? engine.start()
    }

    /// Plays a sound on a free voice. When every voice is busy it takes over the oldest voice
    /// playing something less important; a burst of brick sounds never cuts off a shot or a fanfare.
    func play(_ s: Sound) {
        guard enabled, let b = buffers[s] else { return }
        let now = CACurrentMediaTime()
        guard now - (lastPlayed[s] ?? -1) >= s.gap else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let free = busyUntil.indices.filter { busyUntil[$0] <= now }
        let i: Int
        if let f = free.first {
            i = f
        } else if let low = rank.indices.filter({ rank[$0] < s.rank }).min(by: { busyUntil[$0] < busyUntil[$1] }) {
            i = low
        } else {
            return
        }
        lastPlayed[s] = now
        let p = players[i]
        p.stop()
        p.volume = s.volume
        p.scheduleBuffer(b, at: nil, options: [])
        p.play()
        busyUntil[i] = now + Double(b.frameLength) / rate
        rank[i] = s.rank
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
        case .woodBreak: return mix(0.45, [crackle(0.35, 2600, 0.7, grains: 7), noise(0.3, 1400, 260, 0.35), sweep(0.18, 210, 120, 0.3)])
        case .stoneBreak: return mix(0.6, [crackle(0.5, 1200, 0.55, grains: 14), noise(0.55, 900, 90, 0.55), sweep(0.3, 70, 38, 0.45)])
        case .iceBreak: return mix(0.6, [crackle(0.45, 6500, 0.45, grains: 18), chime(0.5, [2350, 3170, 4430, 5210], 0.12), noise(0.25, 5000, 2500, 0.2, highpass: true)])
        case .ironClang: return mix(0.7, [chime(0.65, [440, 1187, 1693, 2531], 0.16), noise(0.12, 3000, 800, 0.25)])
        }
    }

    /// A burst of short clicks spread over the start of the sound: wood splitting, stone crumbling, ice cracking.
    private func crackle(_ dur: Double, _ tone: Double, _ gain: Double, grains: Int) -> (Double) -> Double {
        var starts: [Double] = []
        for i in 0..<grains { starts.append(Double(i) / Double(grains) * dur * 0.55 + Double.random(in: 0...0.02)) }
        var lp = 0.0
        let a = 1 - exp(-2 * Double.pi * tone / rate)
        return { t in
            var x = 0.0
            for s in starts where t >= s && t < s + 0.012 { x += Double.random(in: -1...1) * exp(-(t - s) * 300) }
            lp += a * (x - lp)
            return (x - lp * 0.6) * gain * exp(-t * 4 / dur)
        }
    }

    /// Bell-like partials with a quick fade: ice ringing, iron struck.
    private func chime(_ dur: Double, _ freqs: [Double], _ gain: Double) -> (Double) -> Double {
        { t in freqs.enumerated().reduce(0) { $0 + sin(2 * Double.pi * $1.element * t) * exp(-t * (5 + Double($1.offset) * 3) / dur) } * gain }
    }
}

import SwiftUI
import SceneKit

@main
struct KaleSavasiApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

enum Paint {
    static let ink = Color(hex: 0x1b2a34), muted = Color(hex: 0x566772), track = Color(hex: 0xdfe6ea)
    static let red = Color(hex: 0xc62d1f), redDark = Color(hex: 0x8e1f15)
    static let blue = Color(hex: 0x1f5fc4), blueDark = Color(hex: 0x143f85)
    static let yellow = Color(hex: 0xf2cd37), yellowDark = Color(hex: 0xc49a0c)
    static let heart = Color(hex: 0xd8246e)
    static let green = Color(hex: 0x2f9e55), gold = Color(hex: 0xd9a514)
    static func team(_ side: Int) -> Color { [red, blue, Color(hex: 0x2f8f3e), gold][max(0, side) % 4] }
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// White card with an ink outline and a hard drop edge.
struct Plate: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = .white
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                RoundedRectangle(cornerRadius: radius).fill(Paint.ink).offset(y: 4)
                RoundedRectangle(cornerRadius: radius).fill(fill)
                RoundedRectangle(cornerRadius: radius).strokeBorder(Paint.ink, lineWidth: 3)
            }
        }
    }
}

struct ChunkyButton: ButtonStyle {
    var color: Color
    var dark: Color
    var fg: Color = .white
    var size: CGFloat = 18
    var fill = true
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Paint.heavy(size))
            .foregroundStyle(fg)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 6 : 11)
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(dark).offset(y: down ? 1 : 5)
                    RoundedRectangle(cornerRadius: 12).fill(color)
                }
            }
            .offset(y: down ? 4 : 0)
            .animation(.easeOut(duration: 0.08), value: down)
    }
}

/// A thin capsule progress bar.
struct Meter: View {
    var value: Double
    var color: Color
    var track: Color = Paint.track
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(0, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

struct SceneContainer: UIViewRepresentable {
    let world: World
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = world.scene
        v.pointOfView = world.cameraNode
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = UIColor(hex: 0x8fd0ff)
        #if DEBUG
        v.showsStatistics = ProcessInfo.processInfo.arguments.contains("-stats")
        #endif
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct RootView: View {
    @StateObject private var game = GameController()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SceneContainer(world: game.world)
                    .ignoresSafeArea()
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { game.drag(start: $0.startLocation, location: $0.location) }
                        .onEnded { _ in game.dragEnded() })
                    .simultaneousGesture(MagnificationGesture()
                        .onChanged { game.pinch($0) }
                        .onEnded { _ in game.pinchEnded() })
                if game.screen == .playing || game.screen == .over {
                    PullOverlay().ignoresSafeArea().allowsHitTesting(false)
                    HUDView().opacity(game.finale ? 0 : 1)
                }
                if game.finale { FinaleBars().transition(.opacity) }
                switch game.screen {
                case .menu:
                    switch game.panel {
                    case .home: MenuView()
                    case .profile: ProfileView()
                    case .settings: SettingsView()
                    case .howTo: HowToView()
                    case .campaign: CampaignView()
                    case .achievements: AchievementsView()
                    case .party: PartyView()
                    }
                case .lobby: LobbyView()
                case .over: if game.over != nil { OverView() }
                case .builder: BuilderView()
                case .playing: if game.confirmQuit { QuitView() }
                }
                // Last, so a message is never hidden behind a card.
                if let t = game.toast { ToastView(text: t).transition(.opacity.combined(with: .scale(scale: 0.9))) }
            }
            .animation(.easeOut(duration: 0.2), value: game.toast)
            .animation(.easeInOut(duration: 0.35), value: game.finale)
            .onAppear { game.viewSize = geo.size }
            .onChange(of: geo.size) { _, new in game.viewSize = new }
        }
        .environmentObject(game)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - In-game HUD

/// The mega meter and streak badge shared by the health and score plates.
struct ChargeRow: View {
    let charge: Double
    let streak: Int
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .black)).foregroundStyle(charge >= 1 ? Paint.yellowDark : Paint.muted)
            Meter(value: charge, color: Paint.yellow, height: 5)
            if streak >= 2 {
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold))
                    Text("×\(streak)").font(Paint.text(11, .heavy)).monospacedDigit()
                }
                .foregroundStyle(Paint.red)
            }
        }
    }
}

struct HealthPlate: View {
    let name: String
    let pct: Double
    let heart: Double
    let color: Color
    let charge: Double
    let streak: Int
    let shielded: Bool
    var body: some View {
        let whole = Int((pct * 100 + 1e-9).rounded(.down))
        let core = Int((heart * 100 + 1e-9).rounded(.up))
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(name).font(Paint.heavy(16)).foregroundStyle(color).lineLimit(1)
                if shielded {
                    Image(systemName: "shield.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x3a8fdc))
                        .accessibilityLabel(Tx.pickup(.shield))
                }
                Spacer(minLength: 8)
                Label(Tx.pct(whole), systemImage: "building.columns.fill").font(Paint.text(11, .heavy)).monospacedDigit().foregroundStyle(Paint.muted)
                Label(Tx.pct(core), systemImage: heart > 0 ? "heart.fill" : "heart.slash.fill")
                    .font(Paint.heavy(17)).monospacedDigit().foregroundStyle(Paint.heart)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Paint.track)
                    Capsule().fill(color.opacity(0.35)).frame(width: max(0, g.size.width * pct))
                    Capsule().fill(Paint.heart).frame(width: max(0, g.size.width * heart)).frame(height: 6)
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 2))
            }
            .frame(height: 12)
            ChargeRow(charge: charge, streak: streak)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(width: 216)
        .modifier(Plate())
        .animation(.easeOut(duration: 0.6), value: pct)
        .animation(.easeOut(duration: 0.6), value: heart)
        .animation(.easeOut(duration: 0.6), value: charge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Tx.health(name, core, whole))
    }
}

/// One castle of four: name, heart bar and how much still stands. Dimmed once its heart is gone.
struct SeatPlate: View {
    let name: String
    let heart: Double
    let pct: Double
    let color: Color
    let out: Bool
    let active: Bool
    let mine: Bool
    let shielded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(name).font(Paint.heavy(12)).foregroundStyle(Paint.ink).lineLimit(1).minimumScaleFactor(0.7)
                if shielded { Image(systemName: "shield.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x3a8fdc)) }
                Spacer(minLength: 2)
                Image(systemName: out ? "heart.slash.fill" : "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Paint.heart)
                Text(Tx.pct(Int((heart * 100 + 1e-9).rounded(.up)))).font(Paint.text(11, .heavy)).monospacedDigit().foregroundStyle(Paint.heart)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Paint.track)
                    Capsule().fill(color.opacity(0.35)).frame(width: max(0, g.size.width * pct))
                    Capsule().fill(Paint.heart).frame(width: max(0, g.size.width * heart)).frame(height: 4)
                }
                .clipShape(Capsule())
            }
            .frame(height: 7)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(width: 168)
        .modifier(Plate(radius: 11, fill: active ? Paint.yellow.opacity(0.9) : .white))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(mine ? color : .clear, lineWidth: 3))
        .opacity(out ? 0.45 : 1)
        .animation(.easeOut(duration: 0.6), value: heart)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Tx.health(name, Int((heart * 100).rounded(.up)), Int((pct * 100).rounded(.down))))
    }
}

/// Four castles: which enemy castle the cannon points at.
struct TargetPicker: View {
    @EnvironmentObject var game: GameController
    let targets: [Int]
    let current: Int
    let names: [String]
    var body: some View {
        HStack(spacing: 8) {
            Text(Tx.target).font(Paint.text(12, .heavy)).foregroundStyle(.white)
            ForEach(targets, id: \.self) { t in
                Button { game.selectTarget(t) } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Paint.team(t)).frame(width: 10, height: 10)
                        Text(names.indices.contains(t) ? names[t] : Tx.seatName(t)).font(Paint.text(12, .heavy)).lineLimit(1)
                    }
                    .foregroundStyle(Paint.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .modifier(Plate(radius: 10, fill: t == current ? Paint.yellow : .white))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(t == current ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Paint.ink.opacity(0.7)))
    }
}

/// Daily siege: the running score and one pip per shot.
struct ScorePlate: View {
    let score: Int
    let taken: Int
    let charge: Double
    let streak: Int
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Tx.score).font(Paint.heavy(16)).foregroundStyle(Paint.red)
                Spacer(minLength: 8)
                Text("\(score)").font(Paint.heavy(19)).monospacedDigit().foregroundStyle(Paint.ink)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 3) {
                ForEach(0..<Challenge.shots, id: \.self) { i in
                    Capsule().fill(i < taken ? Paint.ink : Paint.track).frame(height: 12)
                        .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 2))
                }
            }
            ChargeRow(charge: charge, streak: streak)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(width: 216)
        .modifier(Plate())
        .animation(.easeOut(duration: 0.4), value: score)
        .animation(.easeOut(duration: 0.6), value: charge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tx.score) \(score), \(taken)/\(Challenge.shots)")
    }
}

struct ToolButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Paint.ink)
                .frame(width: 40, height: 36)
                .modifier(Plate(radius: 10))
        }
        .accessibilityLabel(label)
    }
}

/// Arms the charged shot. The ring shows how full the meter is.
struct MegaButton: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let ready = game.hud.megaReady, armed = game.megaArmed
        Button { game.toggleMega() } label: {
            ZStack {
                Circle().fill(Paint.ink).offset(y: 4)
                Circle().fill(armed ? Paint.red : ready ? Paint.yellow : .white)
                if !ready {
                    Circle().trim(from: 0, to: game.hud.megaCharge)
                        .stroke(Paint.yellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(7)
                }
                Circle().strokeBorder(Paint.ink, lineWidth: 3)
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill").font(.system(size: 17, weight: .black))
                    Text("MEGA").font(Paint.heavy(11))
                }
                .foregroundStyle(armed ? .white : Paint.ink)
                .opacity(ready ? 1 : 0.4)
            }
            .frame(width: 64, height: 64)
        }
        .disabled(!ready)
        .phaseAnimator([false, true]) { view, up in
            view.scaleEffect(ready && !armed && up ? 1.09 : 1)
        } animation: { _ in .easeInOut(duration: 0.55) }
        .animation(.easeOut(duration: 0.5), value: game.hud.megaCharge)
        .accessibilityLabel(ready ? Tx.megaReady : Tx.megaCharging)
    }
}

enum Icons {
    static func ammo(_ a: Ammo) -> String {
        switch a {
        case .standard: return "circle.fill"
        case .cluster: return "circle.hexagongrid.fill"
        case .piercer: return "arrowshape.right.fill"
        case .homing: return "location.north.line.fill"
        }
    }
    static func modifier(_ m: Modifier) -> String {
        switch m {
        case .none: return "equal"
        case .storm: return "wind"
        case .calm: return "sun.max.fill"
        case .lowGravity: return "arrow.up.to.line"
        case .megaRush: return "bolt.fill"
        case .bigBlast: return "burst.fill"
        }
    }
    static func pickup(_ k: PickupKind) -> String { World.symbol(of: k) }
}

/// The three special shots. Each can be used once a match.
struct AmmoBar: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Ammo.specials) { a in
                let left = game.hud.stock[a.rawValue], on = game.ammo == a
                Button { game.select(a) } label: {
                    VStack(spacing: 1) {
                        Image(systemName: Icons.ammo(a)).font(.system(size: 17, weight: .bold))
                        Text(Tx.ammo(a)).font(Paint.text(10, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Paint.ink)
                    .frame(width: 58, height: 46)
                    .modifier(Plate(radius: 11, fill: on ? Paint.yellow : .white))
                    .opacity(left > 0 ? 1 : 0.35)
                }
                .disabled(left == 0)
                .accessibilityLabel(Tx.ammoHint(a))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct HUDView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let h = game.hud
        VStack(spacing: 10) {
            if h.names.count > 2 { partyTop(h) } else { duelTop(h) }
            HStack(spacing: 10) {
                Spacer()
                if h.canInspect {
                    ToolButton(icon: h.inspecting ? "scope" : "binoculars.fill", label: h.inspecting ? Tx.backToAim : Tx.inspect) { game.toggleInspect() }
                }
                ToolButton(icon: game.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", label: game.soundOn ? Tx.mute : Tx.unmute) { game.soundOn.toggle() }
                ToolButton(icon: "house.fill", label: Tx.mainMenu) { game.askToQuit() }
            }
            Spacer()
            if h.targets.count > 1 && h.canAim { TargetPicker(targets: h.targets, current: h.target, names: h.names) }
            ZStack(alignment: .bottom) {
                hint(h).allowsHitTesting(false)
                if h.megaVisible {
                    HStack(alignment: .bottom) { AmmoBar(); Spacer(); MegaButton() }
                }
            }
        }
        .padding(.top, 10).padding(.bottom, 6).padding(.horizontal, 8)
    }

    /// Four castles: two small plates on each side of the turn plate.
    private func partyTop(_ h: HUD) -> some View {
        HStack(alignment: .top) {
            VStack(spacing: 6) { ForEach([0, 1], id: \.self) { seatPlate(h, $0) } }
            Spacer(minLength: 8)
            turnPlate(h)
            Spacer(minLength: 8)
            VStack(spacing: 6) { ForEach([2, 3], id: \.self) { seatPlate(h, $0) } }
        }
    }

    @ViewBuilder private func seatPlate(_ h: HUD, _ i: Int) -> some View {
        if i < h.names.count {
            SeatPlate(name: h.names[i], heart: h.heart[i], pct: h.pct[i], color: Paint.team(i), out: h.out.indices.contains(i) && h.out[i],
                      active: h.turnSide == i && !h.finished, mine: h.me == i, shielded: h.shield.indices.contains(i) && h.shield[i])
                .allowsHitTesting(false)
        }
    }

    private func duelTop(_ h: HUD) -> some View {
        HStack(alignment: .top) {
            if let score = h.score {
                ScorePlate(score: score, taken: h.shotsTaken, charge: h.charge[0], streak: h.streak[0]).allowsHitTesting(false)
            } else {
                HealthPlate(name: h.names[0], pct: h.pct[0], heart: h.heart[0], color: Paint.red, charge: h.charge[0], streak: h.streak[0], shielded: h.shield[0]).allowsHitTesting(false)
            }
            Spacer(minLength: 8)
            turnPlate(h)
            Spacer(minLength: 8)
            HealthPlate(name: h.names[1], pct: h.pct[1], heart: h.heart[1], color: Paint.blue, charge: h.charge[1], streak: h.streak[1], shielded: h.shield[1]).allowsHitTesting(false)
        }
    }

    private func turnPlate(_ h: HUD) -> some View {
            VStack(spacing: 2) {
                Text(h.turnText).font(Paint.heavy(16)).lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .black)).rotationEffect(.degrees(h.windAngle))
                    Text(Tx.wind(h.windPower)).font(Paint.text(13, .semibold)).monospacedDigit()
                    if h.modifier != .none {
                        Text("·").font(Paint.text(13, .heavy))
                        Label(Tx.modifier(h.modifier), systemImage: Icons.modifier(h.modifier)).font(Paint.text(12, .heavy)).foregroundStyle(Paint.yellow)
                    }
                }
                if let t = game.timeLeft {
                    HStack(spacing: 5) {
                        Meter(value: Double(t) / K.turnSeconds, color: t <= 5 ? Paint.yellow : .white, track: .white.opacity(0.3), height: 5)
                            .frame(width: 84)
                            .animation(.linear(duration: 1), value: t)
                        Text("\(t)").font(Paint.text(12, .heavy)).monospacedDigit().foregroundStyle(t <= 5 ? Paint.yellow : .white)
                            .frame(width: 18, alignment: .trailing)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .modifier(Plate(fill: h.finished ? Paint.ink : Paint.team(h.turnSide)))
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func hint(_ h: HUD) -> some View {
        if h.canAim && game.pull == nil {
            VStack(spacing: 1) {
                Text(game.megaArmed ? Tx.megaArmedHint : Tx.pullHint).font(Paint.heavy(15)).foregroundStyle(.white)
                if game.ammo != .standard {
                    Text(Tx.ammoHint(game.ammo)).font(Paint.text(12, .bold)).foregroundStyle(Paint.yellow)
                } else if let k = h.pickup, !game.megaArmed {
                    Text(Tx.balloonHint(k)).font(Paint.text(12, .bold)).foregroundStyle(Color(hex: World.tint(of: k)))
                } else if h.hasTarget && !game.megaArmed {
                    Text(Tx.goldHint).font(Paint.text(12, .bold)).foregroundStyle(Paint.yellow)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 18).fill(Paint.ink.opacity(0.78)))
        } else if h.inspecting {
            Text(Tx.inspectHint).font(Paint.heavy(14)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Paint.ink.opacity(0.78)))
        }
    }
}

/// Draws the slingshot pull: anchor, band, current grip and where the previous shot was released.
struct PullOverlay: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Canvas { ctx, _ in
            guard let p = game.pull else { return }
            let ink = Paint.ink
            if let g = game.ghost {
                let c = CGPoint(x: p.start.x + g.width, y: p.start.y + g.height)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30)), with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
            }
            var band = Path()
            band.move(to: p.start)
            band.addLine(to: p.current)
            ctx.stroke(band, with: .color(ink), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            ctx.stroke(band, with: .color(p.armed ? Paint.yellow : .white.opacity(0.7)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.start.x - 9, y: p.start.y - 9, width: 18, height: 18)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: p.start.x - 5, y: p.start.y - 5, width: 10, height: 10)), with: .color(.white))
            let r: CGFloat = 20
            let grip = CGRect(x: p.current.x - r, y: p.current.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: grip), with: .color(p.armed ? Paint.team(game.hud.turnSide) : Paint.muted))
            ctx.stroke(Path(ellipseIn: grip), with: .color(ink), lineWidth: 3)
            let label = p.armed ? Tx.pullLabel(power: Int(p.power.rounded()), yaw: p.yaw) : Tx.pullMore
            let text = ctx.resolve(Text(label).font(Paint.heavy(15)).foregroundColor(.white))
            let size = text.measure(in: CGSize(width: 400, height: 50))
            let box = CGRect(x: p.start.x - size.width / 2 - 12, y: p.start.y - 46, width: size.width + 24, height: size.height + 10)
            ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(ink.opacity(0.85)))
            ctx.draw(text, at: CGPoint(x: box.midX, y: box.midY))
        }
    }
}

/// Cinema bars and a title while the shot that breaks a heart plays out in slow motion.
struct FinaleBars: View {
    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                Color.black.frame(height: g.size.height * 0.13)
                Spacer()
                ZStack {
                    Color.black
                    Text(Tx.finalShot).font(.system(size: 22, weight: .black, design: .rounded)).tracking(6).foregroundStyle(Paint.heart)
                }
                .frame(height: g.size.height * 0.13)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        VStack {
            Text(text)
                .font(Paint.heavy(30))
                .foregroundStyle(.white)
                .shadow(color: Paint.ink, radius: 0, x: 0, y: 3)
                .shadow(color: Paint.ink, radius: 0, x: 2, y: 0)
                .shadow(color: Paint.ink, radius: 0, x: -2, y: 0)
                .shadow(color: Paint.ink, radius: 0, x: 0, y: -2)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
                .padding(.horizontal, 60)
                .padding(.top, 100)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// Asked before walking out of a match in progress.
struct QuitView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 420) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Tx.quitTitle).font(Paint.heavy(24)).foregroundStyle(Paint.ink)
                Text(game.quitWarning)
                    .font(Paint.text(14)).foregroundStyle(Paint.muted)
                HStack(spacing: 14) {
                    Button(Tx.stay) { game.confirmQuit = false }
                        .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark, size: 16))
                    Button(Tx.leave) { game.showMenu() }
                        .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, size: 16))
                }
                .padding(.top, 6)
            }
        }
    }
}

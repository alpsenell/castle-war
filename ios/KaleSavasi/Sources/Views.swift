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
                if let t = game.toast { ToastView(text: t).transition(.opacity.combined(with: .scale(scale: 0.7))) }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.toast)
            .animation(.easeInOut(duration: 0.35), value: game.finale)
            .onAppear {
                game.viewSize = geo.size
                Haptics.enabled = game.profile.haptics
                #if DEBUG
                DebugJump.run(game)
                #endif
            }
            .onChange(of: geo.size) { _, new in game.viewSize = new }
            .onChange(of: game.profile.haptics) { _, on in Haptics.enabled = on }
        }
        .environmentObject(game)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - In-game HUD

/// Shrinks a little while held down.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Text that reads on wood: cream with a dark outline.
private extension View {
    func onWood(_ size: CGFloat = 1) -> some View { foregroundStyle(Theme.cream).embossed(width: size, drop: size * 1.6) }
}

/// The mega meter and streak badge shared by the health and score plates.
struct ChargeRow: View {
    let charge: Double
    let streak: Int
    var body: some View {
        HStack(spacing: 5.u) {
            Image(systemName: "bolt.fill").font(Theme.icon(10, .black))
                .foregroundStyle(charge >= 1 ? Theme.goldLight : Theme.cream.opacity(0.6))
                .embossed(width: 0.8, drop: 1)
            Meter(value: charge, color: Theme.gold, height: 6)
            if streak >= 2 {
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill").font(Theme.icon(10, .bold))
                    Text("×\(streak)").font(Theme.body(11, .black)).monospacedDigit()
                }
                .foregroundStyle(Theme.orange.lighter(0.25))
                .embossed(width: 0.8, drop: 1.2)
            }
        }
    }
}

/// The castle bar: how much still stands behind, the heart as a jewel in front, with notches every tenth.
struct HeartBar: View {
    let heart: Double
    let pct: Double
    let color: Color
    var height: CGFloat = 14
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x24150a))
                if pct > 0 { JewelFill(color: color).opacity(0.5).frame(width: max(height, w * min(1, pct))) }
                if heart > 0 {
                    JewelFill(color: Theme.heart).frame(width: max(height * 0.7, w * min(1, heart)), height: height * 0.62)
                        .padding(.leading, 0)
                }
                ForEach(1..<10, id: \.self) { i in
                    Rectangle().fill(Color.black.opacity(0.28)).frame(width: 1, height: height * 0.5).offset(x: w * CGFloat(i) / 10)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5))
        }
        .frame(height: height)
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
        let core = min(100, Int((heart * 100 - 1e-9).rounded(.up)))
        VStack(spacing: 5.u) {
            HStack(alignment: .center, spacing: 6.u) {
                Crest(color: color, size: 24.u) {
                    Image(systemName: "flag.fill").font(.system(size: 9.u, weight: .black)).foregroundStyle(.white)
                }
                Text(name).font(Theme.display(16)).onWood().lineLimit(1).minimumScaleFactor(0.6)
                if shielded {
                    Image(systemName: "shield.fill").font(Theme.icon(13, .bold)).foregroundStyle(Theme.shield).embossed(width: 0.8, drop: 1)
                        .accessibilityLabel(Tx.pickup(.shield))
                }
                Spacer(minLength: 4)
                HStack(spacing: 3.u) {
                    Image(systemName: heart > 0 ? "heart.fill" : "heart.slash.fill").font(Theme.icon(14, .black))
                    Text(Tx.pct(core)).font(Theme.display(17)).monospacedDigit().contentTransition(.numericText())
                }
                .foregroundStyle(Theme.heart.lighter(0.15))
                .embossed(width: 1, drop: 2)
            }
            HeartBar(heart: heart, pct: pct, color: color, height: 14.u)
            HStack(spacing: 8.u) {
                Label(Tx.pct(whole), systemImage: "building.columns.fill").labelStyle(.titleAndIcon)
                    .font(Theme.body(11, .heavy)).monospacedDigit().foregroundStyle(Theme.cream.opacity(0.9))
                    .fixedSize()
                ChargeRow(charge: charge, streak: streak)
            }
        }
        .padding(.horizontal, 11.u).padding(.vertical, 8.u)
        .frame(width: 236.u)
        .background(WoodPanel(radius: 13.u))
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
        VStack(alignment: .leading, spacing: 4.u) {
            HStack(spacing: 5.u) {
                Crest(color: color, size: 17.u) { EmptyView() }
                Text(name).font(Theme.display(12)).onWood(0.8).lineLimit(1).minimumScaleFactor(0.6)
                if shielded { Image(systemName: "shield.fill").font(Theme.icon(10, .bold)).foregroundStyle(Theme.shield) }
                Spacer(minLength: 2)
                Image(systemName: out ? "heart.slash.fill" : "heart.fill").font(Theme.icon(10, .black))
                Text(Tx.pct(min(100, Int((heart * 100 - 1e-9).rounded(.up))))).font(Theme.display(12)).monospacedDigit()
            }
            .foregroundStyle(Theme.heart.lighter(0.15))
            HeartBar(heart: heart, pct: pct, color: color, height: 9.u)
        }
        .padding(.horizontal, 9.u).padding(.vertical, 6.u)
        .frame(width: 176.u)
        .background(WoodPanel(radius: 11.u, dark: !active, drop: 3))
        .overlay {
            if active {
                RoundedRectangle(cornerRadius: 11.u, style: .continuous).strokeBorder(Theme.goldLight, lineWidth: 2.5)
                    .shadow(color: Theme.gold, radius: 6)
            } else if mine {
                RoundedRectangle(cornerRadius: 11.u, style: .continuous).strokeBorder(color.lighter(0.2), lineWidth: 2.5)
            }
        }
        .grayscale(out ? 1 : 0)
        .opacity(out ? 0.55 : 1)
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
        HStack(spacing: 8.u) {
            Image(systemName: "scope").font(Theme.icon(13, .black)).foregroundStyle(Theme.goldLight)
            Text(Tx.target).font(Theme.display(13)).onWood(0.8)
            ForEach(targets, id: \.self) { t in
                let on = t == current
                Button { game.selectTarget(t) } label: {
                    HStack(spacing: 5.u) {
                        Crest(color: Theme.team(t), size: 15.u) { EmptyView() }
                        Text(names.indices.contains(t) ? names[t] : Tx.seatName(t)).font(Theme.body(13, .heavy)).lineLimit(1)
                    }
                    .foregroundStyle(on ? .white : Theme.text)
                    .modifier(Embossed(color: on ? Theme.ink.opacity(0.8) : .clear, width: on ? 0.8 : 0, drop: on ? 1.5 : 0))
                    .padding(.horizontal, 10.u).padding(.vertical, 6.u)
                    .background {
                        if on { Bevel(face: Theme.gold, edge: Theme.goldDark, radius: 10.u, depth: 3) } else { ParchmentPanel(radius: 10.u, drop: 3, burn: false) }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12.u).padding(.vertical, 7.u)
        .background(WoodPanel(radius: 100, dark: true, drop: 3))
    }
}

/// Daily siege: the running score and one pip per shot.
struct ScorePlate: View {
    let score: Int
    let taken: Int
    let charge: Double
    let streak: Int
    var body: some View {
        VStack(spacing: 5.u) {
            HStack(alignment: .firstTextBaseline) {
                Label(Tx.score, systemImage: "scope").font(Theme.display(15)).onWood()
                Spacer(minLength: 8)
                Text("\(score)").font(Theme.display(22)).monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                    .embossed(width: 1.2, drop: 2)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 4.u) {
                ForEach(0..<Challenge.shots, id: \.self) { i in
                    Group {
                        if i < taken { JewelFill(color: Theme.stone) } else { JewelFill(color: Theme.gold) }
                    }
                    .frame(height: 11.u)
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5))
                }
            }
            ChargeRow(charge: charge, streak: streak)
        }
        .padding(.horizontal, 11.u).padding(.vertical, 8.u)
        .frame(width: 236.u)
        .background(WoodPanel(radius: 13.u))
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
            Image(systemName: icon).font(Theme.icon(16, .heavy))
        }
        .buttonStyle(RoundButtonStyle(tone: .stone, size: 42))
        .accessibilityLabel(label)
    }
}

/// Arms the charged shot: an iron-rimmed jewel whose rim fills as the meter does.
struct MegaButton: View {
    @EnvironmentObject var game: GameController
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        let ready = game.hud.megaReady, armed = game.megaArmed, s = 78.u
        Button { game.toggleMega() } label: {
            ZStack {
                Circle().fill(Theme.ink).offset(y: 4.u)
                Circle().fill(LinearGradient(colors: [Theme.ironLight, Theme.iron, Color(hex: 0x26272a)], startPoint: .top, endPoint: .bottom))
                Circle().trim(from: 0, to: ready ? 1 : game.hud.megaCharge)
                    .stroke(LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 6.u, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(4.u)
                ForEach(0..<8, id: \.self) { i in
                    Rivet(size: 4.u).offset(y: -s * 0.455).rotationEffect(.degrees(Double(i) * 45 + 22.5))
                }
                Circle().fill(RadialGradient(colors: core, center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: s * 0.4)).padding(11.u)
                Ellipse().fill(Color.white.opacity(0.35)).frame(width: s * 0.38, height: s * 0.16).offset(y: -s * 0.22)
                Circle().strokeBorder(Theme.ink, lineWidth: 2).padding(11.u)
                Circle().strokeBorder(Theme.ink, lineWidth: 2.5)
                VStack(spacing: -1) {
                    Image(systemName: "bolt.fill").font(.system(size: 20.u, weight: .black))
                    Text("MEGA").font(.system(size: 12.u, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .embossed(width: 1, drop: 2)
                .opacity(ready ? 1 : 0.55)
            }
            .frame(width: s, height: s)
            .shadow(color: ready ? (armed ? Theme.red : Theme.gold).opacity(0.9) : .clear, radius: 12)
        }
        .buttonStyle(PressStyle())
        .disabled(!ready)
        .phaseAnimator([false, true]) { view, up in
            view.scaleEffect(ready && !armed && up && !still ? 1.08 : 1)
        } animation: { _ in .easeInOut(duration: 0.55) }
        .animation(.easeOut(duration: 0.5), value: game.hud.megaCharge)
        .onChange(of: armed) { _, _ in Haptics.tap(.medium) }
        .accessibilityLabel(ready ? Tx.megaReady : Tx.megaCharging)
    }

    private var core: [Color] {
        if game.megaArmed { return [Theme.red.lighter(0.5), Theme.red, Theme.redDark] }
        if game.hud.megaReady { return [Theme.goldLight, Theme.gold, Theme.goldDark] }
        return [Theme.stone, Theme.stoneDark, Color(hex: 0x2f2b26)]
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

/// The three special shots, as slots in a wooden tray. Each can be used once a match.
struct AmmoBar: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        HStack(spacing: 6.u) {
            ForEach(Ammo.specials) { a in slot(a) }
        }
        .padding(7.u)
        .background(WoodPanel(radius: 15.u, dark: true))
    }

    private func slot(_ a: Ammo) -> some View {
        let left = game.hud.stock[a.rawValue], on = game.ammo == a
        let shape = RoundedRectangle(cornerRadius: 10.u, style: .continuous)
        return Button { game.select(a) } label: {
            VStack(spacing: 2.u) {
                Image(systemName: Icons.ammo(a)).font(Theme.icon(18, .heavy))
                Text(Tx.ammo(a)).font(Theme.body(10, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(on ? .white : Theme.cream)
            .embossed(width: 0.8, drop: 1.5)
            .padding(.horizontal, 3.u)
            .frame(width: 62.u, height: 50.u)
            .background {
                if on {
                    Bevel(face: Theme.gold, edge: Theme.goldDark, radius: 10.u, depth: 3)
                } else {
                    shape.fill(Color.black.opacity(0.4))
                        .overlay(shape.stroke(Color.black.opacity(0.5), lineWidth: 3).blur(radius: 1).offset(y: 1.5).clipShape(shape))
                        .overlay(shape.strokeBorder(Theme.woodLight.opacity(0.35), lineWidth: 1))
                }
            }
            .overlay(alignment: .topTrailing) {
                Text("\(left)").font(.system(size: 10.u, weight: .black, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    .frame(width: 17.u, height: 17.u)
                    .background(Circle().fill(left > 0 ? Theme.red : Theme.stoneDark).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5)))
                    .offset(x: 5.u, y: -5.u)
            }
            .opacity(left > 0 ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
        .disabled(left == 0)
        .accessibilityLabel(Tx.ammoHint(a))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A little compass needle showing which way the wind pushes.
struct WindDial: View {
    let angle: Double
    let power: Int
    var body: some View {
        ZStack {
            Circle().fill(Theme.parchment).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
            Image(systemName: "arrow.up").font(.system(size: 11.u, weight: .black))
                .foregroundStyle(power == 0 ? Theme.muted : Theme.blue)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: 22.u, height: 22.u)
        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: angle)
    }
}

struct HUDView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let h = game.hud
        VStack(spacing: 8.u) {
            if h.names.count > 2 { partyTop(h) } else { duelTop(h) }
            HStack(spacing: 10.u) {
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
        .padding(.top, Theme.roomy ? 18 : 10).padding(.bottom, Theme.roomy ? 16 : 6).padding(.horizontal, Theme.roomy ? 20 : 8)
    }

    /// Four castles: two small plates on each side of the turn plate.
    private func partyTop(_ h: HUD) -> some View {
        HStack(alignment: .top) {
            VStack(spacing: 7.u) { ForEach([0, 1], id: \.self) { seatPlate(h, $0) } }
            Spacer(minLength: 8)
            turnPlate(h)
            Spacer(minLength: 8)
            VStack(spacing: 7.u) { ForEach([2, 3], id: \.self) { seatPlate(h, $0) } }
        }
    }

    @ViewBuilder private func seatPlate(_ h: HUD, _ i: Int) -> some View {
        if i < h.names.count {
            SeatPlate(name: h.names[i], heart: h.heart[i], pct: h.pct[i], color: Theme.team(i), out: h.out.indices.contains(i) && h.out[i],
                      active: h.turnSide == i && !h.finished, mine: h.me == i, shielded: h.shield.indices.contains(i) && h.shield[i])
                .allowsHitTesting(false)
        }
    }

    private func duelTop(_ h: HUD) -> some View {
        HStack(alignment: .top) {
            if let score = h.score {
                ScorePlate(score: score, taken: h.shotsTaken, charge: h.charge[0], streak: h.streak[0]).allowsHitTesting(false)
            } else {
                HealthPlate(name: h.names[0], pct: h.pct[0], heart: h.heart[0], color: Theme.red, charge: h.charge[0], streak: h.streak[0], shielded: h.shield[0]).allowsHitTesting(false)
            }
            Spacer(minLength: 8)
            turnPlate(h)
            Spacer(minLength: 8)
            HealthPlate(name: h.names[1], pct: h.pct[1], heart: h.heart[1], color: Theme.blue, charge: h.charge[1], streak: h.streak[1], shielded: h.shield[1]).allowsHitTesting(false)
        }
    }

    private func turnPlate(_ h: HUD) -> some View {
        VStack(spacing: 5.u) {
            Text(h.turnText).font(Theme.display(15)).foregroundStyle(.white).embossed(width: 1, drop: 2)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 14.u).padding(.vertical, 4.u)
                .background(Bevel(face: h.finished ? Theme.stoneDark : Theme.team(h.turnSide), radius: 9.u, depth: 3))
                .padding(.bottom, 3)
                .animation(.easeOut(duration: 0.25), value: h.turnSide)
            HStack(spacing: 5.u) {
                WindDial(angle: h.windAngle, power: h.windPower)
                Text(Tx.wind(h.windPower)).font(Theme.body(13, .heavy)).monospacedDigit().onWood(0.8)
                if h.modifier != .none {
                    Label(Tx.modifier(h.modifier), systemImage: Icons.modifier(h.modifier)).font(Theme.body(12, .heavy))
                        .foregroundStyle(Theme.goldLight).embossed(width: 0.8, drop: 1.2)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if let t = game.timeLeft {
                HStack(spacing: 5.u) {
                    Image(systemName: "hourglass").font(Theme.icon(11, .heavy)).foregroundStyle(t <= 5 ? Theme.goldLight : Theme.cream)
                    Meter(value: Double(t) / K.turnSeconds, color: t <= 5 ? Theme.red : Theme.gold, height: 6)
                        .frame(width: 84.u)
                        .animation(.linear(duration: 1), value: t)
                    Text("\(t)").font(Theme.display(13)).monospacedDigit().foregroundStyle(t <= 5 ? Theme.goldLight : Theme.cream)
                        .embossed(width: 0.8, drop: 1.2)
                        .frame(width: 20.u, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12.u).padding(.top, 7.u).padding(.bottom, 8.u)
        .background(StonePanel(radius: 14.u))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func hint(_ h: HUD) -> some View {
        if h.canAim && game.pull == nil {
            VStack(spacing: 2) {
                Text(game.megaArmed ? Tx.megaArmedHint : Tx.pullHint).font(Theme.display(15)).foregroundStyle(Theme.cream)
                if game.ammo != .standard {
                    Text(Tx.ammoHint(game.ammo)).font(Theme.body(12, .bold)).foregroundStyle(Theme.goldLight)
                } else if let k = h.pickup, !game.megaArmed {
                    Text(Tx.balloonHint(k)).font(Theme.body(12, .bold)).foregroundStyle(Color(hex: World.tint(of: k)))
                } else if h.hasTarget && !game.megaArmed {
                    Text(Tx.goldHint).font(Theme.body(12, .bold)).foregroundStyle(Theme.goldLight)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18.u).padding(.vertical, 7.u)
            .background(hintBack)
            .padding(.horizontal, 230.u)
        } else if h.inspecting {
            Text(Tx.inspectHint).font(Theme.display(14)).foregroundStyle(Theme.cream)
                .padding(.horizontal, 18.u).padding(.vertical, 8.u)
                .background(hintBack)
        }
    }

    private var hintBack: some View {
        Capsule().fill(Color(hex: 0x24150a).opacity(0.78))
            .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.55), lineWidth: 1.5))
    }
}

/// Draws the slingshot pull: anchor, band, current grip and where the previous shot was released.
struct PullOverlay: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Canvas { ctx, _ in
            guard let p = game.pull else { return }
            let ink = Theme.ink
            if let g = game.ghost {
                let c = CGPoint(x: p.start.x + g.width, y: p.start.y + g.height)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30)), with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
            }
            var band = Path()
            band.move(to: p.start)
            band.addLine(to: p.current)
            ctx.stroke(band, with: .color(ink), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            ctx.stroke(band, with: .color(p.armed ? Theme.gold : Theme.woodLight), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.start.x - 10, y: p.start.y - 10, width: 20, height: 20)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: p.start.x - 6, y: p.start.y - 6, width: 12, height: 12)), with: .color(Theme.ironLight))
            let r: CGFloat = 21
            let grip = CGRect(x: p.current.x - r, y: p.current.y - r, width: r * 2, height: r * 2)
            let face = p.armed ? Theme.team(game.hud.turnSide) : Theme.stone
            ctx.fill(Path(ellipseIn: grip.offsetBy(dx: 0, dy: 3)), with: .color(ink))
            ctx.fill(Path(ellipseIn: grip), with: .linearGradient(Gradient(colors: [face.lighter(0.35), face, face.darker(0.2)]),
                                                                 startPoint: CGPoint(x: grip.midX, y: grip.minY), endPoint: CGPoint(x: grip.midX, y: grip.maxY)))
            ctx.stroke(Path(ellipseIn: grip), with: .color(ink), lineWidth: 3)
            let label = p.armed ? Tx.pullLabel(power: Int(p.power.rounded()), yaw: p.yaw) : Tx.pullMore
            let text = ctx.resolve(Text(label).font(Theme.display(15)).foregroundColor(Theme.cream))
            let size = text.measure(in: CGSize(width: 400, height: 50))
            let box = CGRect(x: p.start.x - size.width / 2 - 14, y: p.start.y - 50, width: size.width + 28, height: size.height + 12)
            ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Color(hex: 0x24150a).opacity(0.88)))
            ctx.stroke(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Theme.gold.opacity(0.6)), lineWidth: 1.5)
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
                    Text(Tx.finalShot).font(Theme.display(24)).tracking(6)
                        .foregroundStyle(LinearGradient(colors: [Theme.heart.lighter(0.4), Theme.heart], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Theme.heart.opacity(0.7), radius: 10)
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
                .font(Theme.display(32))
                .foregroundStyle(LinearGradient(colors: [.white, Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                .embossed(width: 2, drop: 4)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
                .padding(.horizontal, 60)
                .padding(.top, 104.u)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// Asked before walking out of a match in progress.
struct QuitView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 440) {
            VStack(alignment: .leading, spacing: 12.u) {
                HStack(spacing: 12.u) {
                    Medallion(symbol: "flag.fill", tone: .red, size: 46)
                    CardTitle(text: Tx.quitTitle, size: 24)
                }
                Text(game.quitWarning)
                    .font(Theme.body(15)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14.u) {
                    Button(Tx.stay) { game.confirmQuit = false }
                        .buttonStyle(ThemeButtonStyle(tone: .green, size: 17))
                    Button(Tx.leave) { game.showMenu() }
                        .buttonStyle(ThemeButtonStyle(tone: .red, size: 17))
                }
                .padding(.top, 4.u)
            }
        }
    }
}

// MARK: - Screenshot hooks

#if DEBUG
/// "-panel home|profile|settings|howTo|campaign|achievements|party" opens a menu card;
/// "-screen hud|mega|hud4|siege|quit|toast|lobby|builder|over-win|over-loss|over-siege|over-party|over-local"
/// jumps straight to a screen, with sample data where a real one would need a whole match.
enum DebugJump {
    static func run(_ game: GameController) {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        func later(_ t: Double = 1.2, _ work: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work) }
        if let p = value("-panel") {
            let panels: [String: Panel] = ["home": .home, "profile": .profile, "settings": .settings, "howTo": .howTo,
                                           "campaign": .campaign, "achievements": .achievements, "party": .party]
            if let panel = panels[p] { game.panel = panel }
        }
        guard let s = value("-screen") else { return }
        switch s {
        case "hud": game.playComputer()
        case "mega":
            game.playComputer()
            later {
                game.hud.megaReady = true; game.hud.megaCharge = 1; game.hud.streak = [3, 0]; game.hud.shield = [true, false]
                game.hud.heart = [0.8, 0.45]; game.hud.pct = [0.9, 0.62]; game.hud.charge = [1, 0.4]
            }
        case "hud4": game.playParty()
        case "siege": game.playSiege()
        case "quit": game.playComputer(); later { game.askToQuit() }
        case "toast": game.playComputer(); later(2.5) { game.toast = Tx.crit(18) }
        case "lobby":
            game.lobby = Lobby(kind: .partyHost, status: Tx.hostWaiting, busy: true, players: 2, canStart: true)
            game.screen = .lobby
        case "builder": game.openBuilder()
        case _ where s.hasPrefix("over-"):
            game.playComputer()
            later(1.5) { game.over = sampleOver(String(s.dropFirst(5))); game.screen = .over }
        default: break
        }
    }

    private static func sampleOver(_ kind: String) -> OverInfo {
        let mine = MatchStats(shots: 7, hits: 5, crits: 2, bestHit: 24), theirs = MatchStats(shots: 7, hits: 3, crits: 0, bestHit: 15)
        var r = Reward(xp: 140, trophies: 18, levelBefore: 4, levelAfter: 5, progressBefore: 0.72, progressAfter: 0.18)
        r.totalTrophies = 236
        var o: OverInfo
        switch kind {
        case "loss":
            o = OverInfo(title: Tx.lost, detail: Tx.heartFell(Tx.you) + " " + Tx.standing(Tx.you, 34, Tx.computer, 71))
            r = Reward(xp: 45, trophies: -12, levelBefore: 5, levelAfter: 5, progressBefore: 0.2, progressAfter: 0.32)
            r.totalTrophies = 224
        case "siege":
            o = OverInfo(title: Tx.siegeCleared, detail: Tx.siegeScore(2350) + "  ·  " + Tx.clearBonus(500))
            o.isSiege = true
            r.siegeBest = 2350; r.siegeRecord = 3120; r.siegeNewBest = true; r.siegeFirstToday = true
        case "party":
            o = OverInfo(title: Tx.won, detail: Tx.placements([Tx.you, Tx.seatName(2), Tx.seatName(1), Tx.seatName(3)]))
        case "local":
            o = OverInfo(title: Tx.sideWon(Tx.red), detail: Tx.heartFell(Tx.blue) + " " + Tx.standing(Tx.red, 54, Tx.blue, 22))
            o.stats = mine; o.rivalStats = theirs; o.names = [Tx.red, Tx.blue]
            return o
        default:
            o = OverInfo(title: Tx.stageWon(3), detail: Tx.heartFell(Tx.computer) + " " + Tx.standing(Tx.you, 82, Tx.computer, 31))
            o.hasNextStage = true
            r.stars = 3
            r.achievements = [.firstWin, .sniper]
            r.unlockedBall = 1
            r.promotedTo = League.of(236)
        }
        o.stats = mine; o.rivalStats = theirs; o.names = [Tx.you, Tx.computer]
        o.reward = r
        return o
    }
}
#endif

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
    static func team(_ side: Int) -> Color { side == 0 ? red : blue }
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
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, compact ? 14 : 18).padding(.vertical, compact ? 6 : 11)
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
                    HUDView()
                }
                if let t = game.toast { ToastView(text: t).transition(.opacity.combined(with: .scale(scale: 0.9))) }
                switch game.screen {
                case .menu: if game.showProfile { ProfileView() } else { MenuView() }
                case .lobby: LobbyView()
                case .over: if game.over != nil { OverView() }
                case .playing: EmptyView()
                }
            }
            .animation(.easeOut(duration: 0.2), value: game.toast)
            .onAppear { game.viewSize = geo.size }
            .onChange(of: geo.size) { _, new in game.viewSize = new }
        }
        .environmentObject(game)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - In-game HUD

struct HealthPlate: View {
    let name: String
    let pct: Double
    let color: Color
    let charge: Double
    let streak: Int
    var body: some View {
        let whole = Int((pct * 100 + 1e-9).rounded(.down))
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(Paint.heavy(16)).foregroundStyle(color).lineLimit(1)
                Spacer(minLength: 8)
                Text(Tx.pct(whole)).font(Paint.heavy(19)).monospacedDigit().foregroundStyle(Paint.ink)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Paint.track)
                    Capsule().fill(color).frame(width: max(0, g.size.width * pct))
                    Rectangle().fill(Paint.yellow).frame(width: 3).offset(x: g.size.width * 0.2)   // the 20 % line
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 2))
            }
            .frame(height: 12)
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
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(width: 216)
        .modifier(Plate())
        .animation(.easeOut(duration: 0.6), value: pct)
        .animation(.easeOut(duration: 0.6), value: charge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Tx.health(name, whole))
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

struct HUDView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let h = game.hud
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                if let score = h.score {
                    ScorePlate(score: score, taken: h.shotsTaken, charge: h.charge[0], streak: h.streak[0]).allowsHitTesting(false)
                } else {
                    HealthPlate(name: h.names[0], pct: h.pct[0], color: Paint.red, charge: h.charge[0], streak: h.streak[0]).allowsHitTesting(false)
                }
                Spacer(minLength: 8)
                VStack(spacing: 2) {
                    Text(h.turnText).font(Paint.heavy(16)).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up").font(.system(size: 12, weight: .black)).rotationEffect(.degrees(h.windAngle))
                        Text(Tx.wind(h.windPower)).font(Paint.text(13, .semibold)).monospacedDigit()
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
                Spacer(minLength: 8)
                HealthPlate(name: h.names[1], pct: h.pct[1], color: Paint.blue, charge: h.charge[1], streak: h.streak[1]).allowsHitTesting(false)
            }
            HStack(spacing: 10) {
                Spacer()
                if h.canInspect {
                    ToolButton(icon: h.inspecting ? "scope" : "binoculars.fill", label: h.inspecting ? Tx.backToAim : Tx.inspect) { game.toggleInspect() }
                }
                ToolButton(icon: game.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", label: game.soundOn ? Tx.mute : Tx.unmute) { game.soundOn.toggle() }
                ToolButton(icon: "house.fill", label: Tx.mainMenu) { game.showMenu() }
            }
            Spacer()
            ZStack(alignment: .bottom) {
                hint(h).allowsHitTesting(false)
                if h.megaVisible {
                    HStack { Spacer(); MegaButton() }
                }
            }
        }
        .padding(.top, 10).padding(.bottom, 6).padding(.horizontal, 8)
    }

    @ViewBuilder private func hint(_ h: HUD) -> some View {
        if h.canAim && game.pull == nil {
            VStack(spacing: 1) {
                Text(game.megaArmed ? Tx.megaArmedHint : Tx.pullHint).font(Paint.heavy(15)).foregroundStyle(.white)
                if h.hasTarget && !game.megaArmed {
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

struct ToastView: View {
    let text: String
    var body: some View {
        VStack {
            Text(text)
                .font(Paint.heavy(32))
                .foregroundStyle(.white)
                .shadow(color: Paint.ink, radius: 0, x: 0, y: 3)
                .shadow(color: Paint.ink, radius: 0, x: 2, y: 0)
                .shadow(color: Paint.ink, radius: 0, x: -2, y: 0)
                .shadow(color: Paint.ink, radius: 0, x: 0, y: -2)
                .multilineTextAlignment(.center)
                .padding(.top, 100)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Menu and profile

struct Card<Content: View>: View {
    var width: CGFloat = 660
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Paint.ink.opacity(0.3).ignoresSafeArea()
            content
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: width)
                .modifier(Plate(radius: 22))
                .padding(14)
        }
    }
}

struct LevelBadge: View {
    let level: Int
    var size: CGFloat = 34
    var body: some View {
        Text("\(level)").font(Paint.heavy(size * 0.5)).monospacedDigit().foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Paint.ink))
    }
}

/// Level, trophies and win streak at a glance; opens the full profile.
struct ProfileStrip: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Button { game.showProfile = true } label: {
            HStack(spacing: 9) {
                LevelBadge(level: p.level)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(Tx.level(p.level)).font(Paint.heavy(13)).foregroundStyle(Paint.ink)
                        Spacer(minLength: 0)
                        if p.streak >= 2 {
                            Label("\(p.streak)", systemImage: "flame.fill").labelStyle(.titleAndIcon)
                                .font(Paint.text(12, .heavy)).foregroundStyle(Paint.red)
                        }
                        Label("\(p.trophies)", systemImage: "trophy.fill").labelStyle(.titleAndIcon)
                            .font(Paint.text(12, .heavy)).foregroundStyle(Color(hex: p.league.tint))
                    }
                    Meter(value: p.levelProgress, color: Paint.blue)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .black)).foregroundStyle(Paint.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Paint.track.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Paint.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Tx.profile): \(Tx.level(p.level)), \(Tx.trophies(p.trophies)), \(Tx.league(p.league))")
    }
}

/// Today's three missions with progress.
struct MissionsBlock: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Tx.missions).font(Paint.heavy(13)).foregroundStyle(Paint.ink)
            ForEach(game.missions) { m in
                HStack(spacing: 6) {
                    Image(systemName: m.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(m.done ? Paint.blue : Paint.muted)
                    Text(m.title).font(Paint.text(12, .semibold)).foregroundStyle(m.done ? Paint.muted : Paint.ink)
                        .strikethrough(m.done).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Text("\(m.progress)/\(m.target)").font(Paint.text(11, .heavy)).monospacedDigit().foregroundStyle(Paint.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(Paint.text(13, .bold))
            .foregroundStyle(selected ? .white : Paint.ink)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(selected ? Paint.ink : .white))
            .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 2))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MenuView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: -13) {
                        Text(Tx.logoTop).foregroundStyle(Paint.red)
                        Text(Tx.logoBottom).foregroundStyle(Paint.blue).padding(.leading, 22)
                    }
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .shadow(color: Paint.ink, radius: 0, x: 0, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Tx.gameName)
                    .accessibilityAddTraits(.isHeader)
                    MissionsBlock()
                    ProfileStrip()
                    HStack(spacing: 6) {
                        Text(Tx.language).font(Paint.text(13)).foregroundStyle(Paint.muted)
                        ForEach(Language.allCases) { l in
                            Chip(title: l.label, selected: game.language == l) { game.language = l }
                        }
                    }
                }
                .frame(maxWidth: 260, alignment: .leading)
                VStack(alignment: .leading, spacing: 13) {
                    Button(Tx.vsComputer) { game.playComputer() }
                        .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark))
                    HStack(spacing: 6) {
                        Text(Tx.difficulty).font(Paint.text(13)).foregroundStyle(Paint.muted)
                        ForEach(Difficulty.allCases) { d in
                            Chip(title: Tx.name(d), selected: game.difficulty == d) { game.difficulty = d }
                        }
                    }
                    HStack(spacing: 10) {
                        Button { game.playOnline(.gameCenter) } label: { Label(Tx.gameCenterShort, systemImage: "globe") }
                            .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark, size: 16))
                            .accessibilityLabel(Tx.onlineGameCenter)
                        Button { game.playOnline(.nearby) } label: { Label(Tx.nearbyShort, systemImage: "wifi") }
                            .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark, size: 16))
                            .accessibilityLabel(Tx.onlineNearby)
                    }
                    Button(Tx.localTwo) { game.playLocal() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink))
                    Button { game.playSiege() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "scope")
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Tx.dailySiege)
                                Text(game.profile.siegeToday().map(Tx.siegeToday) ?? Tx.siegePitch).font(Paint.text(11, .semibold)).opacity(0.85)
                            }
                        }
                    }
                    .buttonStyle(ChunkyButton(color: Paint.ink, dark: .black, fg: Paint.yellow, size: 16, compact: true))
                }
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Paint.heavy(18)).monospacedDigit().foregroundStyle(Paint.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Paint.text(11, .semibold)).foregroundStyle(Paint.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Paint.track.opacity(0.6)))
    }
}

struct ProfileView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Tx.profile).font(Paint.heavy(24)).foregroundStyle(Paint.ink)
                    TextField(Tx.playerName, text: Binding(get: { game.profile.name }, set: { game.setName($0) }))
                        .font(Paint.text(15, .heavy)).foregroundStyle(Paint.ink)
                        .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(width: 190)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Paint.track.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Paint.ink, lineWidth: 2))
                        .accessibilityLabel(Tx.playerName)
                    Spacer()
                    Button { game.showProfile = false } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Paint.ink)
                            .frame(width: 36, height: 32).modifier(Plate(radius: 10))
                    }
                    .accessibilityLabel(Tx.close)
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            LevelBadge(level: p.level, size: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Tx.level(p.level)).font(Paint.heavy(17)).foregroundStyle(Paint.ink)
                                Meter(value: p.levelProgress, color: Paint.blue, height: 8)
                                Text("\(Int(p.levelProgress * Double(Profile.xpToNext(p.level)))) / \(Profile.xpToNext(p.level)) XP")
                                    .font(Paint.text(11, .semibold)).monospacedDigit().foregroundStyle(Paint.muted)
                            }
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: p.league.tint))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(Tx.trophies(p.trophies)) · \(Tx.league(p.league))").font(Paint.heavy(14)).foregroundStyle(Paint.ink)
                                if let next = p.league.next {
                                    Text(Tx.nextLeague(next.floor - p.trophies, Tx.league(next))).font(Paint.text(11, .semibold)).foregroundStyle(Paint.muted)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 250, alignment: .leading)
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            StatTile(label: Tx.wins, value: "\(p.wins)")
                            StatTile(label: Tx.losses, value: "\(p.losses)")
                            StatTile(label: Tx.accuracy, value: Tx.pct(p.accuracy))
                        }
                        GridRow {
                            StatTile(label: Tx.winStreak, value: "\(p.streak)")
                            StatTile(label: Tx.bestStreak, value: "\(p.bestStreak)")
                            StatTile(label: Tx.dayStreak, value: Tx.days(p.dayStreak))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(Tx.cannonballs).font(Paint.heavy(14)).foregroundStyle(Paint.ink)
                    HStack(spacing: 10) {
                        ForEach(BallStyle.all) { b in
                            let owned = p.owns(b), selected = p.ballStyle == b.id
                            Button { game.selectBall(b.id) } label: {
                                HStack(spacing: 7) {
                                    ZStack {
                                        Circle().fill(Color(hex: b.ball)).frame(width: 24, height: 24)
                                            .overlay(Circle().strokeBorder(Color(hex: b.trail), lineWidth: 3))
                                        if !owned { Image(systemName: "lock.fill").font(.system(size: 10, weight: .black)).foregroundStyle(.white) }
                                    }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(Tx.ball(b.id)).font(Paint.text(13, .heavy)).foregroundStyle(Paint.ink)
                                        if !owned { Text(Tx.level(b.level)).font(Paint.text(10, .semibold)).foregroundStyle(Paint.muted) }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Paint.yellow.opacity(0.45) : Paint.track.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Paint.ink : .clear, lineWidth: 2))
                                .opacity(owned ? 1 : 0.6)
                            }
                            .buttonStyle(.plain)
                            .disabled(!owned)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Lobby and result cards

struct LobbyView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 460) {
            VStack(alignment: .leading, spacing: 14) {
                Text(game.lobby.kind == .gameCenter ? Tx.gameCenterTitle : Tx.nearbyTitle)
                    .font(Paint.heavy(24)).foregroundStyle(Paint.ink)
                HStack(spacing: 10) {
                    if game.lobby.busy { ProgressView().tint(Paint.ink) }
                    Text(game.lobby.status.isEmpty ? Tx.preparing : game.lobby.status)
                        .font(Paint.text(15)).foregroundStyle(Paint.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    Button(Tx.retry) { game.playOnline(game.lobby.kind) }
                        .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark, size: 16))
                    Button(Tx.cancel) { game.showMenu() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink, size: 16))
                }
                .padding(.top, 4)
            }
        }
    }
}

/// What the match earned: XP with the level bar filling, trophies, and any bonus worth calling out.
struct RewardPanel: View {
    let reward: Reward
    var showTrophies = true
    @State private var progress = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(Tx.xpGain(reward.xp)).font(Paint.heavy(20)).monospacedDigit().foregroundStyle(Paint.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tx.level(reward.levelAfter)).font(Paint.text(12, .heavy)).foregroundStyle(Paint.ink)
                    Meter(value: progress, color: Paint.blue, height: 8)
                }
                if showTrophies {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill").font(.system(size: 15, weight: .bold))
                        Text("\(reward.trophies >= 0 ? "+" : "−")\(abs(reward.trophies))").font(Paint.heavy(18)).monospacedDigit()
                    }
                    .foregroundStyle(Color(hex: League.of(reward.totalTrophies).tint))
                }
            }
            ForEach(notes, id: \.self) { n in
                Label(n, systemImage: "star.fill").font(Paint.text(12, .bold)).foregroundStyle(Paint.yellowDark)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Paint.track.opacity(0.6)))
        .onAppear {
            progress = reward.levelAfter > reward.levelBefore ? 0 : reward.progressBefore
            withAnimation(.easeOut(duration: 1.1).delay(0.35)) { progress = reward.progressAfter }
        }
    }

    private var notes: [String] {
        var out: [String] = []
        if reward.levelAfter > reward.levelBefore {
            var line = Tx.levelUp(reward.levelAfter)
            if let b = reward.unlockedBall { line += " · " + Tx.unlocked(Tx.ball(b)) }
            out.append(line)
        }
        if let l = reward.promotedTo { out.append(Tx.promoted(Tx.league(l))) }
        if reward.firstWin { out.append(Tx.firstWin) }
        if reward.siegeFirstToday { out.append(Tx.siegeFirst) }
        for m in reward.missions { out.append(Tx.missionDone(Tx.mission(m))) }
        return Array(out.prefix(5))      // the card has room for five lines
    }
}

/// Both players' numbers side by side; the better one in each row is set in ink, the other muted.
struct CompareTable: View {
    let names: [String]
    let stats: [MatchStats]
    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text(names[0]).font(Paint.heavy(13)).foregroundStyle(Paint.red).lineLimit(1).minimumScaleFactor(0.7)
                Text("")
                Text(names[1]).font(Paint.heavy(13)).foregroundStyle(Paint.blue).lineLimit(1).minimumScaleFactor(0.7)
            }
            row(Tx.accuracy, stats[0].accuracy, stats[1].accuracy) { Tx.pct($0) }
            row(Tx.bestHit, stats[0].bestHit, stats[1].bestHit) { $0 > 0 ? "−" + Tx.pct($0) : "–" }
            row(Tx.criticals, stats[0].crits, stats[1].crits) { "\($0)" }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Paint.track.opacity(0.6)))
    }

    private func row(_ label: String, _ a: Int, _ b: Int, _ text: (Int) -> String) -> some View {
        GridRow {
            Text(text(a)).font(Paint.heavy(16)).monospacedDigit().foregroundStyle(a >= b ? Paint.ink : Paint.muted)
            Text(label).font(Paint.text(11, .semibold)).foregroundStyle(Paint.muted).lineLimit(1).minimumScaleFactor(0.7)
            Text(text(b)).font(Paint.heavy(16)).monospacedDigit().foregroundStyle(b >= a ? Paint.ink : Paint.muted)
        }
    }
}

struct OverView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let o = game.over
        Card(width: 640) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o?.title ?? "").font(.system(size: 32, weight: .black, design: .rounded)).foregroundStyle(Paint.ink)
                    Text(o?.detail ?? "").font(Paint.text(14)).foregroundStyle(Paint.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 10) {
                    if let o, o.isSiege, let r = o.reward {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                StatTile(label: Tx.todayBest, value: "\(r.siegeBest)")
                                StatTile(label: Tx.record, value: "\(r.siegeRecord)")
                            }
                            if r.siegeNewBest {
                                Label(Tx.newBest, systemImage: "star.fill").font(Paint.text(13, .heavy)).foregroundStyle(Paint.yellowDark)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else if let o, let mine = o.stats, let theirs = o.rivalStats, o.names.count == 2 {
                        CompareTable(names: o.names, stats: o.side == 0 ? [mine, theirs] : [theirs, mine])
                    }
                    if let r = o?.reward { RewardPanel(reward: r, showTrophies: o?.isSiege != true).frame(maxWidth: .infinity) }
                }
                HStack(spacing: 14) {
                    Button(o?.waiting == true ? Tx.waitingOpponent : o?.isSiege == true ? Tx.tryAgain : Tx.playAgain) { game.rematch() }
                        .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, size: 16))
                        .disabled(game.over?.waiting == true)
                        .opacity(game.over?.waiting == true ? 0.6 : 1)
                    Button(Tx.mainMenu) { game.showMenu() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink, size: 16))
                }
                .padding(.top, 5)
            }
        }
    }
}

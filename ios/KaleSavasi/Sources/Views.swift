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
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Paint.heavy(size))
            .foregroundStyle(fg)
            .padding(.horizontal, 18).padding(.vertical, 11)
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
                case .menu: MenuView()
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
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(Paint.heavy(16)).foregroundStyle(color).lineLimit(1)
                Spacer(minLength: 8)
                Text("%\(Int((pct * 100 + 1e-9).rounded(.down)))").font(Paint.heavy(19)).monospacedDigit().foregroundStyle(Paint.ink)
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
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(width: 216)
        .modifier(Plate())
        .animation(.easeOut(duration: 0.6), value: pct)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), kalan yapı yüzde \(Int(pct * 100))")
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

struct HUDView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let h = game.hud
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                HealthPlate(name: h.names[0], pct: h.pct[0], color: Paint.red).allowsHitTesting(false)
                Spacer(minLength: 8)
                VStack(spacing: 1) {
                    Text(h.turnText).font(Paint.heavy(16)).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up").font(.system(size: 12, weight: .black)).rotationEffect(.degrees(h.windAngle))
                        Text("Rüzgâr \(h.windPower)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .modifier(Plate(fill: h.finished ? Paint.ink : Paint.team(h.turnSide)))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                HealthPlate(name: h.names[1], pct: h.pct[1], color: Paint.blue).allowsHitTesting(false)
            }
            HStack(spacing: 10) {
                Spacer()
                if h.canInspect {
                    ToolButton(icon: h.inspecting ? "scope" : "binoculars.fill", label: h.inspecting ? "Nişana dön" : "Hedefe bak") { game.toggleInspect() }
                }
                ToolButton(icon: game.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", label: game.soundOn ? "Sesi kapat" : "Sesi aç") { game.soundOn.toggle() }
                ToolButton(icon: "house.fill", label: "Ana menü") { game.showMenu() }
            }
            Spacer()
            if h.canAim && game.pull == nil {
                Text("Geri çek ve bırak").font(Paint.heavy(15)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Paint.ink.opacity(0.78)))
                    .allowsHitTesting(false)
            } else if h.inspecting {
                Text("Sürükle: çevir · Kıstır: yakınlaş").font(Paint.heavy(14)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Paint.ink.opacity(0.78)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 10).padding(.bottom, 6).padding(.horizontal, 8)
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
            let label = p.armed ? "GÜÇ \(Int(p.power.rounded()))   YÖN \(p.yaw >= 0 ? "+" : "−")\(String(format: "%.1f", abs(p.yaw)))°" : "Atış için aşağı çek"
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
                .font(Paint.heavy(34))
                .foregroundStyle(.white)
                .shadow(color: Paint.ink, radius: 0, x: 0, y: 3)
                .shadow(color: Paint.ink, radius: 0, x: 2, y: 0)
                .shadow(color: Paint.ink, radius: 0, x: -2, y: 0)
                .shadow(color: Paint.ink, radius: 0, x: 0, y: -2)
                .multilineTextAlignment(.center)
                .padding(.top, 92)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Menu, lobby and result cards

struct Card<Content: View>: View {
    var width: CGFloat = 640
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Paint.ink.opacity(0.3).ignoresSafeArea()
            content
                .padding(.horizontal, 26).padding(.vertical, 20)
                .frame(maxWidth: width)
                .modifier(Plate(radius: 22))
                .padding(16)
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: -14) {
                        Text("KALE").foregroundStyle(Paint.red)
                        Text("SAVAŞI").foregroundStyle(Paint.blue).padding(.leading, 22)
                    }
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .shadow(color: Paint.ink, radius: 0, x: 0, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Kale Savaşı")
                    .accessibilityAddTraits(.isHeader)
                    Text("Sırayla top ateşle, rakip kaleyi taş taş yık. Kalesinin %20'den azı ayakta kalan kaybeder.")
                        .font(.system(size: 14, design: .rounded)).foregroundStyle(Paint.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 250, alignment: .leading)
                VStack(alignment: .leading, spacing: 13) {
                    Button("Yapay zekâya karşı") { game.playComputer() }
                        .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark))
                    HStack(spacing: 6) {
                        Text("Zorluk").font(.system(size: 13, design: .rounded)).foregroundStyle(Paint.muted)
                        ForEach(Difficulty.allCases) { d in
                            Button(d.title) { game.difficulty = d }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(game.difficulty == d ? .white : Paint.ink)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(game.difficulty == d ? Paint.ink : .white))
                                .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 2))
                                .accessibilityAddTraits(game.difficulty == d ? .isSelected : [])
                        }
                    }
                    Button("Online: Game Center") { game.playOnline(.gameCenter) }
                        .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark))
                    Button("Online: yakındaki oyuncu") { game.playOnline(.nearby) }
                        .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark))
                    Button("Aynı cihazda 2 kişi") { game.playLocal() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink))
                }
            }
        }
    }
}

struct LobbyView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 460) {
            VStack(alignment: .leading, spacing: 14) {
                Text(game.lobby.kind == .gameCenter ? "Game Center eşleşmesi" : "Yakındaki oyuncu")
                    .font(Paint.heavy(24)).foregroundStyle(Paint.ink)
                HStack(spacing: 10) {
                    if game.lobby.busy { ProgressView().tint(Paint.ink) }
                    Text(game.lobby.status.isEmpty ? "Hazırlanıyor…" : game.lobby.status)
                        .font(.system(size: 15, design: .rounded)).foregroundStyle(Paint.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    Button("Yeniden dene") { game.playOnline(game.lobby.kind) }
                        .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark, size: 16))
                    Button("Vazgeç") { game.showMenu() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink, size: 16))
                }
                .padding(.top, 4)
            }
        }
    }
}

struct OverView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 440) {
            VStack(alignment: .leading, spacing: 8) {
                Text(game.over?.title ?? "").font(.system(size: 38, weight: .black, design: .rounded)).foregroundStyle(Paint.ink)
                Text(game.over?.detail ?? "").font(.system(size: 15, design: .rounded)).foregroundStyle(Paint.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button(game.over?.waiting == true ? "Rakip bekleniyor" : "Tekrar oyna") { game.rematch() }
                        .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, size: 16))
                        .disabled(game.over?.waiting == true)
                        .opacity(game.over?.waiting == true ? 0.6 : 1)
                    Button("Ana menü") { game.showMenu() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink, size: 16))
                }
                .padding(.top, 14)
            }
        }
    }
}

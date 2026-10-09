import SwiftUI
import UIKit

// The castle builder's controls over the 3D canvas: a top bar with the budget, codes and Save,
// a tool rail on the left, Rotate, layers and Test gravity on the right, and a tray of bricks,
// stamps and ready-made castles along the bottom.

/// Every colour, font and size the builder uses, taken from the shared paint so a restyle carries over.
enum BuildStyle {
    static let ink = Paint.ink, muted = Paint.muted, track = Paint.track
    static let panel = Color.white
    static let picked = Paint.yellow
    static let good = Paint.green, goodDark = Color(hex: 0x1f6e3a)
    static let bad = Paint.red
    static let coin = Paint.gold
    static let heart = Paint.heart
    static let water = Color(hex: 0x3f8fc4)
    static let shade = Paint.ink.opacity(0.78)
    static func title(_ u: CGFloat) -> Font { Paint.heavy(15 * u) }
    static func label(_ u: CGFloat) -> Font { Paint.text(10 * u, .heavy) }
    static func number(_ u: CGFloat) -> Font { Paint.text(13 * u, .heavy) }
    static func icon(_ u: CGFloat) -> Font { .system(size: 17 * u, weight: .black) }
}

private enum TrayTab: CaseIterable { case bricks, stamps, castles }

struct BuilderView: View {
    @EnvironmentObject var game: GameController
    @State private var tab = TrayTab.bricks

    var body: some View {
        GeometryReader { geo in
            let u: CGFloat = geo.size.width > 1000 ? 1.3 : 1
            ZStack {
                BuildTouchPad(game: game).ignoresSafeArea()
                VStack(spacing: 6 * u) {
                    topBar(u)
                    note(u)
                    HStack(alignment: .center, spacing: 0) {
                        toolRail(u)
                        Spacer(minLength: 0)
                        actionRail(u)
                    }
                    .frame(maxHeight: .infinity)
                    tray(u)
                }
                .padding(.horizontal, 8 * u).padding(.top, 6 * u).padding(.bottom, 4 * u)
                .disabled(game.testingGravity)
                .opacity(game.testingGravity ? 0.45 : 1)
                if game.testingGravity {
                    Label(Tx.gravityRunning, systemImage: "arrow.down.to.line")
                        .font(BuildStyle.title(u)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(BuildStyle.shade))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 60 * u)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            if game.buildTool == .stamp { tab = .stamps }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoCastlesTab") { tab = .castles }
            #endif
        }
    }

    // MARK: Top bar

    private func topBar(_ u: CGFloat) -> some View {
        HStack(spacing: 7 * u) {
            square("xmark", Tx.close, u) { game.closeBuilder() }
            square("arrow.uturn.backward", Tx.undo, u, enabled: !game.undoStack.isEmpty) { game.undo() }
            square("arrow.uturn.forward", Tx.redo, u, enabled: !game.redoStack.isEmpty) { game.redo() }
            CoinMeter(cost: game.draft.cost, u: u)
            brickCount(u)
            Spacer(minLength: 0)
            heartMenu(u)
            if let code = game.draftCode {
                ShareLink(item: Tx.shareMessage(code)) {
                    Image(systemName: "square.and.arrow.up").font(BuildStyle.icon(u)).foregroundStyle(BuildStyle.ink)
                        .frame(width: 40 * u, height: 36 * u).modifier(Plate(radius: 10))
                }
                .accessibilityLabel(Tx.shareCastle)
            }
            PasteButton(payloadType: String.self) { strings in
                DispatchQueue.main.async { game.pasteCastle(strings.first ?? "") }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .tint(BuildStyle.ink)
            .accessibilityLabel(Tx.paste)
            Button { game.saveCastle() } label: { Label(Tx.save, systemImage: "checkmark") }
                .buttonStyle(ChunkyButton(color: BuildStyle.good, dark: BuildStyle.goodDark, size: 15 * u, fill: false, compact: true))
                .opacity(game.draft.problem == nil ? 1 : 0.5)
        }
    }

    private func brickCount(_ u: CGFloat) -> some View {
        let n = game.draft.bricks.count
        return HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 12 * u, weight: .bold))
            Text("\(n)/\(BK.maxBricks)").font(BuildStyle.number(u)).monospacedDigit()
        }
        .foregroundStyle(n > BK.maxBricks ? BuildStyle.bad : BuildStyle.ink)
        .padding(.horizontal, 9 * u).frame(height: 36 * u)
        .modifier(Plate(radius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Tx.bricks) \(n)/\(BK.maxBricks)")
    }

    private func heartMenu(_ u: CGFloat) -> some View {
        Menu {
            ForEach(HeartKind.allCases) { h in
                let owned = game.profile.owns(h)
                Button { game.pick(heart: h) } label: {
                    Label(owned ? "\(Tx.heart(h)) · \(h.cost)" : "\(Tx.heart(h)) · \(Tx.heartLocked(h.level))",
                          systemImage: !owned ? "lock.fill" : game.draft.heart == h ? "checkmark" : "heart.fill")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 15 * u, weight: .black))
                    .foregroundStyle(Color(hex: Look.heartColors(game.draft.heart).glow))
                Text(Tx.heart(game.draft.heart)).font(BuildStyle.label(u)).foregroundStyle(BuildStyle.ink)
                Image(systemName: "chevron.down").font(.system(size: 9 * u, weight: .black)).foregroundStyle(BuildStyle.muted)
            }
            .padding(.horizontal, 9 * u).frame(height: 36 * u)
            .modifier(Plate(radius: 10))
        }
        .accessibilityLabel("\(Tx.heartType): \(Tx.heart(game.draft.heart))")
    }

    // MARK: Note

    private func note(_ u: CGFloat) -> some View {
        let problem = game.draft.problem
        let text: String, fill: Color
        if let n = game.builderNote { text = n; fill = BuildStyle.shade }
        else if game.buildTool == .erase { text = Tx.eraseHint; fill = BuildStyle.shade }
        else if game.buildTool == .look { text = Tx.lookHint; fill = BuildStyle.shade }
        else if game.draft.bricks.isEmpty { text = Tx.builderHint3D; fill = BuildStyle.shade }
        else if let problem { text = Tx.brickProblem(problem); fill = BuildStyle.bad.opacity(0.9) }
        else { text = Tx.builderReady; fill = BuildStyle.good.opacity(0.92) }
        return Text(text).font(Paint.text(12 * u, .heavy)).foregroundStyle(.white)
            .lineLimit(2).multilineTextAlignment(.center)
            .padding(.horizontal, 12 * u).padding(.vertical, 5 * u)
            .background(Capsule().fill(fill))
            .frame(maxWidth: 460 * u)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: text)
    }

    // MARK: Rails

    private func toolRail(_ u: CGFloat) -> some View {
        VStack(spacing: 6 * u) {
            railButton("hammer.fill", Tx.build, u, on: game.buildTool.places) {
                if !game.buildTool.places { game.pick(tool: tab == .stamps ? .stamp : .brick) }
            }
            railButton("eraser.fill", Tx.eraser, u, on: game.buildTool == .erase) { game.pick(tool: .erase) }
            railButton("rotate.3d", Tx.look, u, on: game.buildTool == .look) { game.pick(tool: .look) }
        }
    }

    private func actionRail(_ u: CGFloat) -> some View {
        VStack(spacing: 6 * u) {
            Button { game.rotate() } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 20 * u, weight: .black))
                        .rotationEffect(.degrees(Double(game.buildRot) * 90))
                        .animation(.spring(duration: 0.25), value: game.buildRot)
                    Text(Tx.rotate).font(BuildStyle.label(u))
                }
                .foregroundStyle(BuildStyle.ink).frame(width: 58 * u, height: 52 * u)
                .modifier(Plate(radius: 12, fill: BuildStyle.picked))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tx.rotate)
            VStack(spacing: 0) {
                Button { game.setLayer(game.buildLayer + 1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 13 * u, weight: .black)).frame(width: 58 * u, height: 22 * u)
                }
                .disabled(game.buildLayer >= BK.height)
                Text("\(Tx.layer) \(game.buildLayer)").font(BuildStyle.label(u)).monospacedDigit()
                Button { game.setLayer(game.buildLayer - 1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 13 * u, weight: .black)).frame(width: 58 * u, height: 22 * u)
                }
                .disabled(game.buildLayer <= 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BuildStyle.ink)
            .modifier(Plate(radius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(Tx.layer) \(game.buildLayer)/\(BK.height)")
            Button { game.testGravity() } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 18 * u, weight: .black))
                    Text(Tx.testGravity).font(BuildStyle.label(u)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(.white).frame(width: 58 * u, height: 52 * u)
                .modifier(Plate(radius: 12, fill: Paint.blue))
            }
            .buttonStyle(.plain)
            .disabled(game.draft.bricks.isEmpty)
            .accessibilityLabel(Tx.testGravity)
        }
    }

    private func railButton(_ icon: String, _ label: String, _ u: CGFloat, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(BuildStyle.icon(u))
                Text(label).font(BuildStyle.label(u)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(BuildStyle.ink).frame(width: 52 * u, height: 48 * u)
            .modifier(Plate(radius: 12, fill: on ? BuildStyle.picked : BuildStyle.panel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func square(_ icon: String, _ label: String, _ u: CGFloat, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15 * u, weight: .black)).foregroundStyle(BuildStyle.ink)
                .frame(width: 40 * u, height: 36 * u).modifier(Plate(radius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }

    // MARK: Tray

    private func tray(_ u: CGFloat) -> some View {
        HStack(spacing: 8 * u) {
            VStack(spacing: 3 * u) {
                ForEach(TrayTab.allCases, id: \.self) { t in
                    Button { tab = t; if t == .stamps { game.pick(tool: .stamp) } else if t == .bricks && game.buildTool == .stamp { game.pick(tool: .brick) } } label: {
                        Text(title(t)).font(BuildStyle.label(u)).foregroundStyle(BuildStyle.ink)
                            .frame(width: 62 * u, height: 21 * u)
                            .background(RoundedRectangle(cornerRadius: 7).fill(tab == t ? BuildStyle.picked : BuildStyle.track.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
            if tab != .castles {
                materials(u)
                Rectangle().fill(BuildStyle.track).frame(width: 2, height: 56 * u)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5 * u) {
                    switch tab {
                    case .bricks: brickTiles(u)
                    case .stamps: stampTiles(u)
                    case .castles: castleTiles(u)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 72 * u)
        }
        .padding(6 * u)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(Plate(radius: 16))
    }

    private func title(_ t: TrayTab) -> String {
        switch t {
        case .bricks: return Tx.bricks
        case .stamps: return Tx.stamps
        case .castles: return Tx.castles
        }
    }

    private func materials(_ u: CGFloat) -> some View {
        LazyHGrid(rows: [GridItem(.fixed(32 * u), spacing: 3 * u), GridItem(.fixed(32 * u), spacing: 3 * u)], spacing: 3 * u) {
            ForEach(BrickMaterial.buildable) { m in
                let on = game.buildMaterial == m
                Button { game.pick(material: m) } label: {
                    HStack(spacing: 2) {
                        Image(uiImage: BrickIcons.brick(.cube, m)).resizable().frame(width: 26 * u, height: 26 * u)
                        Text(Tx.material(m)).font(Paint.text(9 * u, .heavy)).foregroundStyle(BuildStyle.ink).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(width: 64 * u, height: 32 * u, alignment: .leading)
                    .padding(.leading, 2)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? BuildStyle.picked : BuildStyle.track.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BuildStyle.ink, lineWidth: on ? 2.5 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Tx.material(m)), \(Tx.materialInfo(m))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(width: 134 * u, height: 68 * u)
    }

    @ViewBuilder private func brickTiles(_ u: CGFloat) -> some View {
        tile(BrickIcons.brick(.cube, .heart), Tx.heartTool, "\(game.draft.heart.cost)", u, on: game.buildTool == .heart, tint: BuildStyle.heart) { game.pick(tool: .heart) }
        tile(BrickIcons.brick(.cube, .decoy), Tx.decoy, "\(PlacedBrick(shape: .cube, material: .decoy, x: 0, y: 0, z: 0).cost)", u, on: game.buildTool == .decoy, tint: BuildStyle.heart) { game.pick(tool: .decoy) }
        tile(BrickIcons.brick(.moat, .stone), Tx.shape(.moat), "\(PlacedBrick(shape: .moat, material: .stone, x: 0, y: 0, z: 0).cost)", u, on: game.buildTool == .moat, tint: BuildStyle.water) { game.pick(tool: .moat) }
        ForEach(BrickShape.allCases.filter { !$0.isDecal }) { s in
            let m = s.materials.contains(game.buildMaterial) ? game.buildMaterial : .stone
            tile(BrickIcons.brick(s, m), Tx.shape(s), "\(PlacedBrick(shape: s, material: m, x: 0, y: 0, z: 0).cost)", u,
                 on: game.buildTool == .brick && game.buildShape == s) { game.pick(shape: s) }
        }
    }

    @ViewBuilder private func stampTiles(_ u: CGFloat) -> some View {
        ForEach(Stamp.allCases) { s in
            let cost = s.bricks(x: 0, z: 0, rot: 0, material: game.buildMaterial).reduce(0) { $0 + $1.cost }
            tile(BrickIcons.stamp(s, game.buildMaterial), Tx.stamp(s), "\(cost)", u, on: game.buildTool == .stamp && game.buildStamp == s) { game.pick(stamp: s) }
        }
    }

    @ViewBuilder private func castleTiles(_ u: CGFloat) -> some View {
        tile(nil, Tx.clearAll, nil, u, on: false, icon: "trash") { game.clearDraft() }
        ForEach(Array(BuilderCatalog.castles.enumerated()), id: \.offset) { i, d in
            tile(BrickIcons.castle("preset\(i)", d), i == 0 ? Tx.classicLayout : Tx.castleNumber(i + 1), "\(d.cost)", u, on: false, wide: true) { game.loadDraft(d) }
        }
    }

    private func tile(_ image: UIImage?, _ name: String, _ cost: String?, _ u: CGFloat, on: Bool, tint: Color? = nil,
                      icon: String? = nil, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    if let image { Image(uiImage: image).resizable().scaledToFit() }
                    if let icon { Image(systemName: icon).font(.system(size: 20 * u, weight: .black)).foregroundStyle(BuildStyle.ink) }
                }
                .frame(width: (wide ? 66 : 44) * u, height: 40 * u)
                Text(name).font(Paint.text(9 * u, .heavy)).foregroundStyle(BuildStyle.ink).lineLimit(1).minimumScaleFactor(0.6)
                if let cost {
                    HStack(spacing: 2) {
                        Circle().fill(BuildStyle.coin).frame(width: 7 * u, height: 7 * u)
                        Text(cost).font(Paint.text(9 * u, .heavy)).monospacedDigit().foregroundStyle(BuildStyle.muted)
                    }
                }
            }
            .frame(width: (wide ? 74 : 58) * u, height: 68 * u)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? BuildStyle.picked : (tint ?? BuildStyle.track).opacity(on ? 1 : 0.22)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BuildStyle.ink, lineWidth: on ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cost.map { "\(name), \($0) \(Tx.coins)" } ?? name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Coins spent against the budget, with a notch at the minimum a castle must spend.
private struct CoinMeter: View {
    let cost: Int
    let u: CGFloat
    var body: some View {
        let over = cost > BK.budget, under = cost < BK.minimum
        HStack(spacing: 6 * u) {
            ZStack {
                Circle().fill(BuildStyle.coin)
                Circle().strokeBorder(Paint.yellowDark, lineWidth: 2)
                Text("$").font(.system(size: 11 * u, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 20 * u, height: 20 * u)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(cost) / \(BK.budget)").font(BuildStyle.number(u)).monospacedDigit()
                    .foregroundStyle(over ? BuildStyle.bad : BuildStyle.ink)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Meter(value: Double(cost) / Double(BK.budget), color: over ? BuildStyle.bad : under ? BuildStyle.coin : BuildStyle.good, height: 6 * u)
                        Rectangle().fill(BuildStyle.ink).frame(width: 2, height: 10 * u)
                            .offset(x: g.size.width * CGFloat(BK.minimum) / CGFloat(BK.budget) - 1)
                    }
                }
                .frame(height: 10 * u)
            }
        }
        .padding(.horizontal, 9 * u).frame(width: 160 * u, height: 36 * u)
        .modifier(Plate(radius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tx.coins) \(cost)/\(BK.budget)")
    }
}

// MARK: - Touches

/// Catches touches on the builder canvas: one finger places, erases or orbits; two fingers pan,
/// pinch to zoom and twist to turn.
struct BuildTouchPad: UIViewRepresentable {
    let game: GameController
    func makeUIView(context: Context) -> BuildPadView { let v = BuildPadView(); v.game = game; return v }
    func updateUIView(_ v: BuildPadView, context: Context) { v.game = game }
}

final class BuildPadView: UIView, UIGestureRecognizerDelegate {
    weak var game: GameController?
    private var finger: UITouch?
    /// A second finger came down: ignore the first until every finger lifts.
    private var multi = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(twisted(_:)))
        for g in [pinch, pan, twist] as [UIGestureRecognizer] {
            g.delegate = self
            g.cancelsTouchesInView = false
            addGestureRecognizer(g)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let all = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count
        if all > 1 || finger != nil {
            if finger != nil { game?.buildCancel() }
            finger = nil
            multi = true
            return
        }
        guard !multi, let t = touches.first else { return }
        finger = t
        game?.buildDown(t.location(in: nil))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let f = finger, touches.contains(f) else { return }
        game?.buildMove(f.location(in: nil))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let f = finger, touches.contains(f) { game?.buildUp(f.location(in: nil)); finger = nil }
        resetIfLifted(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let f = finger, touches.contains(f) { game?.buildCancel(); finger = nil }
        resetIfLifted(event)
    }

    private func resetIfLifted(_ event: UIEvent?) {
        let live = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        if live == 0 { multi = false }
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) { game?.buildZoom(g.scale); g.scale = 1 }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        game?.buildPan(CGSize(width: t.x, height: t.y))
        g.setTranslation(.zero, in: self)
    }

    @objc private func twisted(_ g: UIRotationGestureRecognizer) { game?.buildTwist(g.rotation); g.rotation = 0 }
}

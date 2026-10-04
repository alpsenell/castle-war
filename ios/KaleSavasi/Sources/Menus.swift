import SwiftUI

// Everything outside a match: the menu and its panels, the castle builder, the online lobby
// and the result card.

struct Card<Content: View>: View {
    var width: CGFloat = 680
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Paint.ink.opacity(0.3).ignoresSafeArea()
            content
                .padding(.horizontal, 22).padding(.vertical, 16)
                .frame(maxWidth: width)
                .modifier(Plate(radius: 22))
                .padding(12)
        }
    }
}

/// Title row with a close button, shared by the menu's side panels.
struct PanelHeader: View {
    @EnvironmentObject var game: GameController
    let title: String
    var close: (() -> Void)?
    var body: some View {
        HStack {
            Text(title).font(Paint.heavy(24)).foregroundStyle(Paint.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { if let close { close() } else { game.panel = .home } } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Paint.ink)
                    .frame(width: 36, height: 32).modifier(Plate(radius: 10))
            }
            .accessibilityLabel(Tx.close)
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
        Button { game.panel = .profile } label: {
            HStack(spacing: 9) {
                LevelBadge(level: p.level)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(p.name.isEmpty ? Tx.level(p.level) : p.name).font(Paint.heavy(13)).foregroundStyle(Paint.ink).lineLimit(1)
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
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12).fill(Paint.track.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Paint.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Tx.profile): \(Tx.level(p.level)), \(Tx.trophies(p.trophies)), \(Tx.league(p.league))")
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
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(selected ? Paint.ink : .white))
            .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 2))
            .accessibilityAddTraits(selected ? .isSelected : [])
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

/// A menu button with a second line under the title.
struct ModeLabel: View {
    let icon: String
    let title: String
    var detail: String?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                if let detail { Text(detail).font(Paint.text(11, .semibold)).opacity(0.85) }
            }
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Card {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: -12) {
                        Text(Tx.logoTop).foregroundStyle(Paint.red)
                        Text(Tx.logoBottom).foregroundStyle(Paint.blue).padding(.leading, 20)
                    }
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .shadow(color: Paint.ink, radius: 0, x: 0, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Tx.gameName)
                    .accessibilityAddTraits(.isHeader)
                    MissionsBlock()
                    ProfileStrip()
                    HStack(spacing: 8) {
                        Button { game.openBuilder() } label: { Label(Tx.buildCastle, systemImage: "hammer.fill") }
                            .buttonStyle(ChunkyButton(color: Paint.ink, dark: .black, fg: .white, size: 14, compact: true))
                        Button { game.panel = .settings } label: {
                            Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Paint.ink)
                                .frame(width: 38, height: 30).modifier(Plate(radius: 10))
                        }
                        .accessibilityLabel(Tx.settings)
                        Button { game.panel = .howTo } label: {
                            Image(systemName: "questionmark").font(.system(size: 15, weight: .black)).foregroundStyle(Paint.ink)
                                .frame(width: 38, height: 30).modifier(Plate(radius: 10))
                        }
                        .accessibilityLabel(Tx.howToPlay)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: 262, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Button { game.panel = .campaign } label: {
                        ModeLabel(icon: "flag.checkered", title: Tx.campaign, detail: Tx.campaignProgress(p.nextStage.id, p.totalStars, Stage.all.count * 3))
                    }
                    .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, compact: true))
                    HStack(spacing: 8) {
                        Button { game.playComputer() } label: { Label(Tx.quickMatch, systemImage: "cpu") }
                            .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, size: 16))
                        VStack(spacing: 4) {
                            ForEach(Difficulty.allCases) { d in
                                Button(Tx.name(d)) { game.difficulty = d }
                                    .font(Paint.text(11, .heavy))
                                    .foregroundStyle(game.difficulty == d ? .white : Paint.ink)
                                    .frame(width: 62, height: 15)
                                    .background(Capsule().fill(game.difficulty == d ? Paint.ink : .white))
                                    .overlay(Capsule().strokeBorder(Paint.ink, lineWidth: 1.5))
                                    .accessibilityAddTraits(game.difficulty == d ? .isSelected : [])
                            }
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
                    HStack(spacing: 10) {
                        Button { game.playLocal() } label: { Label(Tx.localShort, systemImage: "person.2.fill") }
                            .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink, size: 16))
                            .accessibilityLabel(Tx.localTwo)
                        Button { game.playSiege() } label: {
                            ModeLabel(icon: "scope", title: Tx.dailySiege, detail: p.siegeToday().map(Tx.siegeToday))
                        }
                        .buttonStyle(ChunkyButton(color: Paint.ink, dark: .black, fg: Paint.yellow, size: 15, compact: p.siegeToday() != nil))
                    }
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
                    Button { game.panel = .home } label: {
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

struct SettingsView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 460) {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(title: Tx.settings)
                row(Tx.language) {
                    ForEach(Language.allCases) { l in Chip(title: l.label, selected: game.language == l) { game.language = l } }
                }
                row(Tx.sound) {
                    Chip(title: Tx.on, selected: game.soundOn) { game.soundOn = true }
                    Chip(title: Tx.off, selected: !game.soundOn) { game.soundOn = false }
                }
                row(Tx.haptics) {
                    Chip(title: Tx.on, selected: game.profile.haptics) { game.setHaptics(true) }
                    Chip(title: Tx.off, selected: !game.profile.haptics) { game.setHaptics(false) }
                }
                Button { game.panel = .howTo } label: { Label(Tx.howToPlay, systemImage: "questionmark.circle.fill") }
                    .buttonStyle(ChunkyButton(color: Paint.blue, dark: Paint.blueDark, size: 16))
            }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Paint.text(15, .semibold)).foregroundStyle(Paint.ink).frame(width: 110, alignment: .leading)
            content()
            Spacer()
        }
    }
}

struct HowToView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(title: Tx.howToPlay) { game.closeHowTo() }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], alignment: .leading, spacing: 9) {
                    ForEach(Array(Tx.tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: tip.0).font(.system(size: 15, weight: .bold)).foregroundStyle(Paint.blue).frame(width: 22)
                            Text(tip.1).font(Paint.text(12.5, .medium)).foregroundStyle(Paint.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button(Tx.gotIt) { game.closeHowTo() }
                    .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, size: 16, fill: false))
            }
        }
    }
}

struct StarRow: View {
    let earned: Int
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < earned ? "star.fill" : "star").font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < earned ? Paint.yellowDark : Paint.muted.opacity(0.5))
            }
        }
        .accessibilityLabel("\(earned)/3")
    }
}

/// The ladder of computer opponents.
struct CampaignView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Card {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(title: Tx.campaign)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Stage.all) { s in
                        let open = p.isOpen(s), stars = p.stars(for: s)
                        Button { game.playStage(s) } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("\(s.id)").font(Paint.heavy(20)).monospacedDigit()
                                    if !open { Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold)) }
                                    else if s.modifier != .none { Image(systemName: Icons.modifier(s.modifier)).font(.system(size: 11, weight: .bold)) }
                                }
                                .foregroundStyle(Paint.ink)
                                Text(Tx.name(s.difficulty)).font(Paint.text(10, .heavy)).foregroundStyle(Paint.muted)
                                StarRow(earned: stars)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 11).fill(stars > 0 ? Paint.yellow.opacity(0.35) : Paint.track.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(s.id == p.nextStage.id && open ? Paint.red : Paint.ink.opacity(open ? 1 : 0.25), lineWidth: s.id == p.nextStage.id ? 3 : 2))
                            .opacity(open ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .disabled(!open)
                        .accessibilityLabel("\(Tx.stage(s.id)), \(Tx.name(s.difficulty))\(open ? "" : ", " + Tx.locked)")
                    }
                }
                HStack(spacing: 14) {
                    Label("\(p.totalStars)/\(Stage.all.count * 3)", systemImage: "star.fill").font(Paint.text(13, .heavy)).foregroundStyle(Paint.yellowDark)
                    ForEach([PieceKind.tallTower, .bastion]) { k in
                        Label("\(Tx.piece(k)): \(Profile.starsNeeded(k))", systemImage: p.owns(k) ? "checkmark.circle.fill" : "lock.fill")
                            .font(Paint.text(12, .semibold)).foregroundStyle(p.owns(k) ? Paint.green : Paint.muted)
                    }
                }
            }
        }
    }
}

// MARK: - Castle builder

enum PieceLook {
    static func color(_ k: PieceKind) -> Color {
        switch k {
        case .wallLow: return Color(hex: 0xb7bcc0)
        case .wallHigh: return Color(hex: 0x858b91)
        case .tower: return Color(hex: 0x5b8fd6)
        case .tallTower: return Color(hex: 0x2459b8)
        case .bastion: return Color(hex: 0x9a7b52)
        case .keep: return Color(hex: 0xc62d1f)
        case .heart: return Paint.heart
        case .wallStrong: return Color(hex: 0x4e555c)
        case .shelter: return Color(hex: 0x8f7e66)
        case .moat: return Color(hex: 0x3f8fc4)
        case .decoy: return Color(hex: 0xe58bb0)
        }
    }
    static func icon(_ k: PieceKind) -> String {
        switch k {
        case .wallLow: return "rectangle.fill"
        case .wallHigh: return "rectangle.portrait.fill"
        case .tower: return "building.fill"
        case .tallTower: return "building.2.fill"
        case .bastion: return "square.fill"
        case .keep: return "crown.fill"
        case .heart: return "heart.fill"
        case .wallStrong: return "shield.fill"
        case .shelter: return "house.fill"
        case .moat: return "water.waves"
        case .decoy: return "heart"
        }
    }
}

/// The tile grid of a castle, seen from above with the enemy at the top.
struct DesignGrid: View {
    let design: CastleDesign
    let cell: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let rows = CastleDesign.rows, cols = CastleDesign.cols
            for r in 0...rows {
                var p = Path(); p.move(to: CGPoint(x: 0, y: CGFloat(r) * cell)); p.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cell))
                ctx.stroke(p, with: .color(Paint.ink.opacity(0.14)), lineWidth: 1)
            }
            for c in 0...cols {
                var p = Path(); p.move(to: CGPoint(x: CGFloat(c) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(c) * cell, y: size.height))
                ctx.stroke(p, with: .color(Paint.ink.opacity(0.14)), lineWidth: 1)
            }
            // Shelters first: whatever sits in the middle of one is drawn on top.
            for piece in design.pieces.sorted(by: { ($0.kind == .shelter ? 0 : 1) < ($1.kind == .shelter ? 0 : 1) }) {
                let n = piece.kind.span
                // Row 0 is the back of the castle, drawn at the bottom.
                let rect = CGRect(x: CGFloat(piece.tz) * cell, y: CGFloat(rows - piece.tx - n) * cell, width: CGFloat(n) * cell, height: CGFloat(n) * cell).insetBy(dx: 1, dy: 1)
                ctx.fill(Path(roundedRect: rect, cornerRadius: n == 1 ? 3 : 5), with: .color(PieceLook.color(piece.kind)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: n == 1 ? 3 : 5), with: .color(Paint.ink), lineWidth: 1.5)
                if piece.kind == .shelter {
                    let hole = CGRect(x: rect.minX + cell - 1, y: rect.minY + cell - 1, width: cell, height: cell).insetBy(dx: 2, dy: 2)
                    ctx.fill(Path(roundedRect: hole, cornerRadius: 3), with: .color(Color(hex: 0xe9efe2)))
                    ctx.stroke(Path(roundedRect: hole, cornerRadius: 3), with: .color(Paint.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    let mark = ctx.resolve(Image(systemName: PieceLook.icon(piece.kind)))
                    ctx.draw(mark, in: CGRect(x: rect.minX + 3, y: rect.minY + 3, width: cell * 0.7, height: cell * 0.7))
                } else if piece.kind == .heart || piece.kind == .decoy || piece.kind == .wallStrong || piece.kind == .moat {
                    var mark = ctx.resolve(Image(systemName: PieceLook.icon(piece.kind)))
                    mark.shading = .color(.white)
                    ctx.draw(mark, in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18))
                } else if n > 1 {
                    let mark = ctx.resolve(Image(systemName: PieceLook.icon(piece.kind)))
                    ctx.draw(mark, in: rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28))
                }
            }
        }
        .frame(width: cell * CGFloat(CastleDesign.cols), height: cell * CGFloat(CastleDesign.rows))
    }
}

struct BuilderView: View {
    @EnvironmentObject var game: GameController
    private let cell: CGFloat = 20

    var body: some View {
        let cost = game.draft.cost
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Tx.buildCastle).font(Paint.heavy(18)).foregroundStyle(Paint.ink)
                    Spacer()
                    Text(Tx.stone(cost, CastleDesign.budget)).font(Paint.text(13, .heavy)).monospacedDigit()
                        .foregroundStyle(cost > CastleDesign.budget ? Paint.red : Paint.ink)
                }
                Meter(value: Double(cost) / Double(CastleDesign.budget), color: cost < CastleDesign.minimum ? Paint.muted : Paint.green, height: 7)
                Text(Tx.builderFront).font(Paint.text(9, .heavy)).foregroundStyle(Paint.red).frame(maxWidth: .infinity)
                DesignGrid(design: game.draft, cell: cell)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xe9efe2)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Paint.ink, lineWidth: 2))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let col = Int(v.location.x / cell), row = CastleDesign.rows - 1 - Int(v.location.y / cell)
                            game.paint(row: row, col: col, fresh: v.translation == .zero)
                        }
                        .onEnded { _ in game.strokeEnded() })
                    .accessibilityLabel(Tx.buildCastle)
                Text(Tx.builderBack).font(Paint.text(9, .heavy)).foregroundStyle(Paint.muted).frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: cell * CGFloat(CastleDesign.cols) + 24)
            .modifier(Plate(radius: 16))
            VStack(spacing: 4) {
                LazyVGrid(columns: [GridItem(.fixed(38), spacing: 4), GridItem(.fixed(38), spacing: 4)], spacing: 4) {
                    ForEach(PieceKind.allCases) { k in toolButton(k) }
                    Button { game.pick(tool: nil) } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "eraser.fill").font(.system(size: 13, weight: .bold))
                            Text(Tx.eraser).font(Paint.text(8, .heavy))
                        }
                        .foregroundStyle(Paint.ink).frame(width: 38, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(game.erasing ? Paint.yellow : Paint.track.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paint.ink, lineWidth: game.erasing ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tx.eraser)
                }
            }
            .padding(8)
            .modifier(Plate(radius: 16))
            .padding(.leading, 6)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Button { game.closeBuilder() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Paint.ink)
                        .frame(width: 38, height: 34).modifier(Plate(radius: 10))
                }
                .accessibilityLabel(Tx.close)
                Spacer()
                Text(game.builderNote ?? toolLine).font(Paint.text(13, .heavy)).foregroundStyle(.white).multilineTextAlignment(.trailing)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill((game.builderNote == nil ? Paint.ink : Paint.red).opacity(0.85)))
                    .frame(maxWidth: 300, alignment: .trailing)
                HStack(spacing: 10) {
                    Button(Tx.classicLayout) { game.loadDraft(.classic) }
                        .buttonStyle(ChunkyButton(color: .white, dark: Paint.ink, fg: Paint.ink, size: 14, fill: false, compact: true))
                    Button(Tx.clearAll) { game.loadDraft(CastleDesign()) }
                        .buttonStyle(ChunkyButton(color: .white, dark: Paint.ink, fg: Paint.ink, size: 14, fill: false, compact: true))
                    Button { game.saveCastle() } label: { Label(Tx.save, systemImage: "checkmark") }
                        .buttonStyle(ChunkyButton(color: Paint.green, dark: Color(hex: 0x1f6e3a), size: 16, fill: false))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
    }

    private var toolLine: String {
        if game.erasing { return Tx.builderHint }
        guard let k = game.tool else { return Tx.builderHint }
        let line = "\(Tx.piece(k)) · \(CastleDesign.cost(of: k))"
        return Tx.pieceInfo(k).map { line + "\n" + $0 } ?? line
    }

    private func toolButton(_ k: PieceKind) -> some View {
        let owned = game.profile.owns(k), on = !game.erasing && game.tool == k
        return Button { game.pick(tool: k) } label: {
            VStack(spacing: 1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(PieceLook.color(k)).frame(width: 18, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Paint.ink, lineWidth: 1))
                    if k == .heart { Image(systemName: "heart.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white) }
                    if !owned { Image(systemName: "lock.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white) }
                }
                Text("\(CastleDesign.cost(of: k))").font(Paint.text(9, .heavy)).monospacedDigit()
            }
            .foregroundStyle(Paint.ink).frame(width: 38, height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Paint.yellow : Paint.track.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paint.ink, lineWidth: on ? 2.5 : 1))
            .opacity(owned ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Tx.piece(k)), \(CastleDesign.cost(of: k))\(owned ? "" : ", " + Tx.locked)")
        .accessibilityAddTraits(on ? .isSelected : [])
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
                    .lineLimit(1).minimumScaleFactor(0.75)
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
        if let k = reward.unlockedPiece { out.append(Tx.pieceUnlocked(Tx.piece(k))) }
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
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o?.title ?? "").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Paint.ink)
                        Text(o?.detail ?? "").font(Paint.text(14)).foregroundStyle(Paint.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if let stars = o?.reward?.stars { StarRow(earned: stars, size: 26) }
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
                    Button(again(o)) { game.rematch() }
                        .buttonStyle(ChunkyButton(color: Paint.red, dark: Paint.redDark, size: 16))
                        .disabled(o?.waiting == true)
                        .opacity(o?.waiting == true ? 0.6 : 1)
                    Button(Tx.mainMenu) { game.showMenu() }
                        .buttonStyle(ChunkyButton(color: Paint.yellow, dark: Paint.yellowDark, fg: Paint.ink, size: 16))
                }
                .padding(.top, 5)
            }
        }
    }

    private func again(_ o: OverInfo?) -> String {
        if o?.waiting == true { return Tx.waitingOpponent }
        if o?.hasNextStage == true { return Tx.nextStage }
        return o?.isSiege == true ? Tx.tryAgain : Tx.playAgain
    }
}

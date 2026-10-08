import SwiftUI

// Everything outside a match: the menu and its panels, the online lobby and the result card.
// The shared controls (Card, PanelHeader, Chip, StatTile, …) live in Theme.swift; the castle
// builder lives in BuilderView.swift.

/// Level, trophies and win streak at a glance; opens the full profile.
struct ProfileStrip: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Button { game.panel = .profile } label: {
            HStack(spacing: 8.u) {
                LevelBadge(level: p.level, size: 38)
                VStack(alignment: .leading, spacing: 3.u) {
                    Text(p.name.isEmpty ? Tx.level(p.level) : p.name).font(Theme.display(14)).foregroundStyle(Theme.cream)
                        .embossed(width: 1, drop: 1.5).lineLimit(1).minimumScaleFactor(0.7)
                    Meter(value: p.levelProgress, color: Theme.blue, height: 7).frame(width: 104.u)
                }
                Pill(text: "\(p.trophies)", icon: "trophy.fill", tint: Color(hex: p.league.tint).lighter(0.25))
                if p.streak >= 2 { Pill(text: "\(p.streak)", icon: "flame.fill", tint: Theme.orange.lighter(0.2)) }
            }
            .padding(.leading, 8.u).padding(.trailing, 10.u).padding(.vertical, 5.u)
            .background(WoodPanel(radius: 16.u, drop: 3))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(Tx.profile): \(Tx.level(p.level)), \(Tx.trophies(p.trophies)), \(Tx.league(p.league))")
    }
}

/// Today's three missions with progress, on a scrap of parchment.
struct MissionsBlock: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        VStack(alignment: .leading, spacing: 4.u) {
            Label(Tx.missions, systemImage: "scroll.fill").font(Theme.display(13)).foregroundStyle(Theme.woodDark).engraved()
            ForEach(game.missions) { m in
                HStack(spacing: 6.u) {
                    Image(systemName: m.done ? "checkmark.seal.fill" : "circle.dotted")
                        .font(Theme.icon(12, .bold)).foregroundStyle(m.done ? Theme.green : Theme.muted)
                    Text(m.title).font(Theme.body(12, .bold)).foregroundStyle(m.done ? Theme.muted : Theme.text)
                        .strikethrough(m.done).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("\(m.progress)/\(m.target)").font(Theme.body(11, .heavy)).monospacedDigit().foregroundStyle(m.done ? Theme.green : Theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 11.u).padding(.vertical, 8.u)
        .background(ParchmentPanel(radius: 12.u, drop: 3))
    }
}

/// The title: KEEP in red over FALL in gold, outlined and tipped back a little.
struct Logo: View {
    var size: CGFloat = 50
    var body: some View {
        VStack(alignment: .leading, spacing: -size.u * 0.36) {
            Text(Tx.logoTop)
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xff7a5a), Theme.red, Theme.redDark], startPoint: .top, endPoint: .bottom))
            Text(Tx.logoBottom).padding(.leading, size.u * 0.45)
                .foregroundStyle(LinearGradient(colors: [Theme.goldLight, Theme.gold, Theme.goldDark], startPoint: .top, endPoint: .bottom))
        }
        .font(.system(size: size.u, weight: .black, design: .rounded))
        .embossed(width: 2.5, drop: 5)
        .overlay(alignment: .topLeading) {
            Image(systemName: "crown.fill").font(.system(size: size.u * 0.38, weight: .black))
                .foregroundStyle(LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                .embossed(width: 1.2, drop: 2)
                .rotationEffect(.degrees(-18))
                .offset(x: -size.u * 0.14, y: -size.u * 0.2)
        }
        .rotationEffect(.degrees(-3))
        .lineLimit(1).minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Tx.gameName)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The big quick-match button with the difficulty it plays at.
struct PlayBlock: View {
    @EnvironmentObject var game: GameController
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        VStack(spacing: 6.u) {
            Button { game.playComputer() } label: {
                HStack(spacing: 10.u) {
                    Image(systemName: "play.fill").font(Theme.icon(26, .black))
                    VStack(alignment: .leading, spacing: -2.u) {
                        Text(Tx.play).font(Theme.display(31))
                        Text("\(Tx.quickMatch) · \(Tx.name(game.difficulty))").font(Theme.body(11, .heavy))
                    }
                }
            }
            .buttonStyle(ThemeButtonStyle(tone: .green, size: 30, radius: 18))
            .phaseAnimator([false, true]) { v, up in v.scaleEffect(up && !still ? 1.025 : 1) } animation: { _ in .easeInOut(duration: 1.1) }
            .accessibilityLabel("\(Tx.quickMatch), \(Tx.name(game.difficulty))")
            HStack(spacing: 5.u) {
                ForEach(Difficulty.allCases) { d in Chip(title: Tx.name(d), selected: game.difficulty == d) { game.difficulty = d } }
            }
            .padding(.horizontal, 6.u).padding(.vertical, 4.u)
            .background(WoodPanel(radius: 100, dark: true, drop: 2))
        }
    }
}

/// An illustrated mode tile: a big symbol on rays of light, the mode's name and one line about it.
struct TileFace: View {
    let icon: String
    let title: String
    var detail: String?
    var body: some View {
        VStack(spacing: 3.u) {
            Image(systemName: icon).font(.system(size: 30.u, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, Theme.cream], startPoint: .top, endPoint: .bottom))
                .embossed(width: 1.2, drop: 2.5)
                .frame(maxHeight: .infinity)
            Text(title).font(Theme.display(14)).foregroundStyle(.white).embossed(width: 1, drop: 2)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(Theme.body(10, .heavy)).foregroundStyle(Theme.cream.opacity(0.95))
                    .shadow(color: Theme.ink.opacity(0.7), radius: 0, x: 0, y: 1)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6.u).padding(.top, 6.u).padding(.bottom, 8.u)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Sunburst().fill(Color.white.opacity(0.13)).frame(width: 260.u, height: 260.u).offset(y: -16.u)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16.u, style: .continuous))
    }
}

struct TileStyle: ButtonStyle {
    var tone: Tone
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed, depth = 5.u
        configuration.label
            .background(Bevel(face: tone.face, edge: tone.edge, radius: 16.u, depth: depth, pressed: down))
            .offset(y: down ? depth - 1 : 0)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: down)
            .onChange(of: down) { _, now in if now { Haptics.tap() } }
    }
}

struct ModeTile: View {
    let icon: String
    let title: String
    var detail: String?
    let tone: Tone
    let action: () -> Void
    var body: some View {
        Button(action: action) { TileFace(icon: icon, title: title, detail: detail) }
            .buttonStyle(TileStyle(tone: tone))
    }
}

/// Friend's castle: a tile with the system paste button, since a pasted code starts the match.
struct FriendTile: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        VStack(spacing: 3.u) {
            Image(systemName: "envelope.open.fill").font(.system(size: 26.u, weight: .heavy)).foregroundStyle(.white)
                .embossed(width: 1.2, drop: 2.5)
                .frame(maxHeight: .infinity)
            Text(Tx.friendCastle).font(Theme.display(13)).foregroundStyle(.white).embossed(width: 1, drop: 2)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            PasteButton(payloadType: String.self) { strings in
                DispatchQueue.main.async { game.playFriend(code: strings.first ?? "") }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .tint(Theme.woodDark)
            .controlSize(.small)
            .accessibilityHint(Tx.friendHint)
        }
        .padding(.horizontal, 6.u).padding(.top, 6.u).padding(.bottom, 7.u)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Bevel(face: Theme.stone, edge: Theme.stoneDark, radius: 16.u, depth: 5.u))
        .padding(.bottom, 5.u)
    }
}

struct MenuView: View {
    @EnvironmentObject var game: GameController
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        GeometryReader { g in
            let leftW = min(290.u, g.size.width * 0.37)
            VStack(spacing: 8.u) {
                topBar
                HStack(alignment: .center, spacing: 16.u) {
                    VStack(spacing: 9.u) {
                        Logo(size: Theme.roomy ? 58 : 46)
                        PlayBlock()
                        MissionsBlock()
                    }
                    .frame(width: leftW)
                    .offset(x: shown || still ? 0 : -40)
                    modeGrid(width: g.size.width - leftW - (Theme.roomy ? 40 : 28).u, height: g.size.height - 66.u)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, Theme.roomy ? 12.u : 6.u).padding(.vertical, Theme.roomy ? 10.u : 6.u)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(still ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.75)) { shown = true } }
    }

    private var topBar: some View {
        HStack(spacing: 10.u) {
            ProfileStrip()
            Spacer(minLength: 8)
            Button { game.openBuilder() } label: { Label(Tx.buildCastle, systemImage: "hammer.fill") }
                .buttonStyle(ThemeButtonStyle(tone: .wood, size: 15, fill: false, compact: true))
            Button { game.panel = .settings } label: { Image(systemName: "gearshape.fill").font(Theme.icon(17, .heavy)) }
                .buttonStyle(RoundButtonStyle(tone: .stone, size: 40))
                .accessibilityLabel(Tx.settings)
            Button { game.panel = .howTo } label: { Image(systemName: "questionmark").font(Theme.icon(17, .black)) }
                .buttonStyle(RoundButtonStyle(tone: .stone, size: 40))
                .accessibilityLabel(Tx.howToPlay)
        }
    }

    private func modeGrid(width: CGFloat, height: CGFloat) -> some View {
        let p = game.profile, gap = 9.u
        let tileW = (width - gap * 3) / 4
        let tileH = min((height - gap) / 2 - 5.u, tileW * 1.2)
        let cols = Array(repeating: GridItem(.fixed(tileW), spacing: gap), count: 4)
        let tiles: [AnyView] = [
            AnyView(ModeTile(icon: "map.fill", title: Tx.campaign, detail: Tx.campaignProgress(p.nextStage.id, p.totalStars, Stage.all.count * 3), tone: .red) { game.panel = .campaign }),
            AnyView(ModeTile(icon: "scope", title: Tx.dailySiege, detail: p.siegeToday().map(Tx.siegeToday) ?? Tx.siegePitch, tone: .purple) { game.playSiege() }),
            AnyView(ModeTile(icon: "flame.fill", title: Tx.gauntlet, detail: p.gauntletBest > 0 ? Tx.gauntletBest(p.gauntletBest) : Tx.gauntletPitch, tone: .orange) { game.playGauntlet() }),
            AnyView(ModeTile(icon: "person.3.fill", title: Tx.partyTitle, detail: Tx.partyShort, tone: .green) { game.panel = .party }),
            AnyView(ModeTile(icon: "globe.europe.africa.fill", title: Tx.gameCenterShort, detail: Tx.gameCenterPitch, tone: .blue) { game.playOnline(.gameCenter) }
                .accessibilityLabel(Tx.onlineGameCenter)),
            AnyView(ModeTile(icon: "wifi", title: Tx.nearbyShort, detail: Tx.nearbyPitch, tone: .teal) { game.playOnline(.nearby) }
                .accessibilityLabel(Tx.onlineNearby)),
            AnyView(ModeTile(icon: "person.2.fill", title: Tx.localShort, detail: Tx.localPitch, tone: .gold) { game.playLocal() }
                .accessibilityLabel(Tx.localTwo)),
            AnyView(FriendTile()),
        ]
        return LazyVGrid(columns: cols, spacing: gap) {
            ForEach(tiles.indices, id: \.self) { i in
                tiles[i]
                    .frame(height: tileH + 5.u)
                    .scaleEffect(shown || still ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)
                    .animation(still ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.62).delay(0.05 + Double(i) * 0.04), value: shown)
            }
        }
        .frame(width: width)
    }
}

struct ProfileView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Card(width: 700) {
            VStack(alignment: .leading, spacing: 11.u) {
                HStack(spacing: 10.u) {
                    CardTitle(text: Tx.profile).fixedSize()
                    TextField(Tx.playerName, text: Binding(get: { game.profile.name }, set: { game.setName($0) }))
                        .font(Theme.body(15, .heavy)).foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                        .padding(.horizontal, 11.u).padding(.vertical, 6.u)
                        .frame(width: 200.u)
                        .background(InsetWell(radius: 9.u))
                        .overlay(alignment: .trailing) { Image(systemName: "pencil").font(Theme.icon(12, .heavy)).foregroundStyle(Theme.muted).padding(.trailing, 9.u) }
                        .accessibilityLabel(Tx.playerName)
                    Spacer()
                    CloseButton { game.panel = .home }
                }
                HStack(alignment: .top, spacing: 18.u) {
                    VStack(alignment: .leading, spacing: 9.u) {
                        HStack(spacing: 10.u) {
                            LevelBadge(level: p.level, size: 54)
                            VStack(alignment: .leading, spacing: 4.u) {
                                Text(Tx.level(p.level)).font(Theme.display(18)).foregroundStyle(Theme.text).engraved()
                                Meter(value: p.levelProgress, color: Theme.blue, height: 10)
                                Text("\(Int(p.levelProgress * Double(Profile.xpToNext(p.level)))) / \(Profile.xpToNext(p.level)) XP")
                                    .font(Theme.body(11, .bold)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                        }
                        HStack(spacing: 9.u) {
                            Medallion(symbol: "trophy.fill", tone: Tone(face: Color(hex: p.league.tint), edge: Color(hex: p.league.tint).darker(0.4)), size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(Tx.trophies(p.trophies)) · \(Tx.league(p.league))").font(Theme.display(14)).foregroundStyle(Theme.text)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                if let next = p.league.next {
                                    Text(Tx.nextLeague(next.floor - p.trophies, Tx.league(next))).font(Theme.body(11, .bold)).foregroundStyle(Theme.muted)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 250.u, alignment: .leading)
                    Grid(horizontalSpacing: 8.u, verticalSpacing: 8.u) {
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
                VStack(alignment: .leading, spacing: 6.u) {
                    Text(Tx.cannonballs).font(Theme.display(14)).foregroundStyle(Theme.woodDark).engraved()
                    HStack(spacing: 8.u) {
                        ForEach(BallStyle.all) { b in ballSlot(b, p) }
                    }
                }
                Button { game.panel = .achievements } label: {
                    Label(Tx.achievementCount(Achievement.allCases.filter { p.has($0) }.count, Achievement.allCases.count), systemImage: "rosette")
                }
                .buttonStyle(ThemeButtonStyle(tone: .gold, size: 15, fill: false, compact: true))
            }
        }
    }

    private func ballSlot(_ b: BallStyle, _ p: Profile) -> some View {
        let owned = p.owns(b), selected = p.ballStyle == b.id
        let shape = RoundedRectangle(cornerRadius: 10.u, style: .continuous)
        return Button { game.selectBall(b.id) } label: {
            HStack(spacing: 7.u) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(hex: b.ball).lighter(0.5), Color(hex: b.ball), Color(hex: b.ball).darker(0.4)],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 15.u))
                        .frame(width: 26.u, height: 26.u)
                        .overlay(Circle().strokeBorder(Color(hex: b.trail), lineWidth: 3))
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
                    if !owned { Image(systemName: "lock.fill").font(Theme.icon(10, .black)).foregroundStyle(.white).embossed(width: 0.8, drop: 1) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Tx.ball(b.id)).font(Theme.body(13, .heavy)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                    if !owned { Text(Tx.level(b.level)).font(Theme.body(10, .bold)).foregroundStyle(Theme.muted) }
                }
            }
            .padding(.horizontal, 9.u).padding(.vertical, 6.u)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected { shape.fill(Theme.goldLight.opacity(0.55)) } else { InsetWell(radius: 10.u) }
            }
            .overlay(shape.strokeBorder(selected ? Theme.goldDark : .clear, lineWidth: 2.5))
            .opacity(owned ? 1 : 0.6)
        }
        .buttonStyle(PressStyle())
        .disabled(!owned)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 500) {
            VStack(alignment: .leading, spacing: 10.u) {
                PanelHeader(title: Tx.settings)
                VStack(spacing: 8.u) {
                    row("globe", Tx.language) {
                        ForEach(Language.allCases) { l in Chip(title: l.label, selected: game.language == l) { game.language = l } }
                    }
                    row(game.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", Tx.sound) {
                        Chip(title: Tx.on, selected: game.soundOn) { game.soundOn = true }
                        Chip(title: Tx.off, selected: !game.soundOn) { game.soundOn = false }
                    }
                    row("iphone.radiowaves.left.and.right", Tx.haptics) {
                        Chip(title: Tx.on, selected: game.profile.haptics) { game.setHaptics(true) }
                        Chip(title: Tx.off, selected: !game.profile.haptics) { game.setHaptics(false) }
                    }
                }
                Button { game.panel = .howTo } label: { Label(Tx.howToPlay, systemImage: "book.fill") }
                    .buttonStyle(ThemeButtonStyle(tone: .blue, size: 16))
                    .padding(.top, 4.u)
            }
        }
    }

    private func row<C: View>(_ icon: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8.u) {
            Image(systemName: icon).font(Theme.icon(15, .bold)).foregroundStyle(Theme.woodDark).frame(width: 26.u)
            Text(title).font(Theme.body(15, .heavy)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 112.u, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10.u).padding(.vertical, 7.u)
        .background(InsetWell(radius: 11.u))
    }
}

struct HowToView: View {
    @EnvironmentObject var game: GameController
    private let tones: [Tone] = [.blue, .teal, .gold, .orange, .purple, .red, .green]
    var body: some View {
        Card(width: 720) {
            VStack(alignment: .leading, spacing: 10.u) {
                PanelHeader(title: Tx.howToPlay) { game.closeHowTo() }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12.u), count: Theme.roomy ? 3 : 2), alignment: .leading, spacing: 9.u) {
                        ForEach(Array(Tx.tips.enumerated()), id: \.offset) { i, tip in
                            HStack(alignment: .center, spacing: 10.u) {
                                Medallion(symbol: tip.0, tone: tones[i % tones.count], size: 38)
                                Text(tip.1).font(Theme.body(12.5, .semibold)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(8.u)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .background(InsetWell(radius: 12.u))
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: (Theme.roomy ? 380 : 226).u)
                Button { game.closeHowTo() } label: { Label(Tx.gotIt, systemImage: "checkmark") }
                    .buttonStyle(ThemeButtonStyle(tone: .green, size: 16, fill: false))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Four castles: against computers, or online with up to three other players.
struct PartyView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 560) {
            VStack(alignment: .leading, spacing: 11.u) {
                PanelHeader(title: Tx.partyTitle)
                HStack(spacing: 12.u) {
                    HStack(spacing: -6.u) {
                        ForEach(0..<4, id: \.self) { i in
                            Crest(color: Theme.team(i), size: 40.u) {
                                Image(systemName: "building.columns.fill").font(.system(size: 13.u, weight: .black)).foregroundStyle(.white)
                            }
                        }
                    }
                    Text(Tx.partyPitch).font(Theme.body(13, .semibold)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10.u) {
                    Button { game.playParty() } label: { Label(Tx.partyComputers, systemImage: "cpu") }
                        .buttonStyle(ThemeButtonStyle(tone: .red, size: 15))
                    ForEach(Difficulty.allCases) { d in Chip(title: Tx.name(d), selected: game.difficulty == d) { game.difficulty = d } }
                }
                Button { game.playOnline(.partyGameCenter) } label: { Label(Tx.partyGameCenter, systemImage: "globe.europe.africa.fill") }
                    .buttonStyle(ThemeButtonStyle(tone: .blue, size: 15))
                HStack(spacing: 10.u) {
                    Button { game.playOnline(.partyHost) } label: { Label(Tx.partyHost, systemImage: "antenna.radiowaves.left.and.right") }
                        .buttonStyle(ThemeButtonStyle(tone: .green, size: 15))
                    Button { game.playOnline(.partyJoin) } label: { Label(Tx.partyJoin, systemImage: "wifi") }
                        .buttonStyle(ThemeButtonStyle(tone: .teal, size: 15))
                }
            }
        }
    }
}

struct AchievementsView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Card(width: 760) {
            VStack(alignment: .leading, spacing: 10.u) {
                PanelHeader(title: "\(Tx.achievementsTitle)  \(Achievement.allCases.filter { p.has($0) }.count)/\(Achievement.allCases.count)") { game.panel = .profile }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8.u), count: Theme.roomy ? 4 : 3), spacing: 8.u) {
                        ForEach(Achievement.allCases) { a in cell(a, p) }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: (Theme.roomy ? 330 : 270).u)
            }
        }
    }

    private func cell(_ a: Achievement, _ p: Profile) -> some View {
        let done = p.has(a), v = min(a.value(p), a.target)
        let shape = RoundedRectangle(cornerRadius: 12.u, style: .continuous)
        return HStack(spacing: 8.u) {
            Medallion(symbol: a.icon, tone: .gold, size: 40, lit: done)
            VStack(alignment: .leading, spacing: 2.u) {
                Text(Tx.achievement(a)).font(Theme.body(12, .heavy)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(Tx.achievementGoal(a)).font(Theme.body(10, .semibold)).foregroundStyle(Theme.muted).lineLimit(2).minimumScaleFactor(0.8)
                if !done && a.target > 1 { Meter(value: Double(v) / Double(a.target), color: Theme.blue, height: 5) }
            }
            Spacer(minLength: 0)
        }
        .padding(7.u)
        .frame(maxHeight: .infinity)
        .background {
            if done {
                shape.fill(LinearGradient(colors: [Theme.goldLight.opacity(0.7), Theme.gold.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Theme.goldDark, lineWidth: 1.5))
            } else { InsetWell(radius: 12.u) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? Tx.achievementDone(a) : "\(v)/\(a.target)")
    }
}

/// The ladder of computer opponents, drawn as a winding road across a map.
struct CampaignView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let p = game.profile
        Card(width: 740) {
            VStack(alignment: .leading, spacing: 8.u) {
                PanelHeader(title: Tx.campaign)
                CampaignMap(profile: p) { game.playStage($0) }
                    .frame(height: 212.u)
                HStack(spacing: 14.u) {
                    Pill(text: "\(p.totalStars)/\(Stage.all.count * 3)", icon: "star.fill", tint: Theme.goldLight)
                    ForEach([PieceKind.tallTower, .bastion]) { k in
                        Label("\(Tx.piece(k)): \(Profile.starsNeeded(k))", systemImage: p.owns(k) ? "checkmark.seal.fill" : "lock.fill")
                            .font(Theme.body(12, .bold)).foregroundStyle(p.owns(k) ? Theme.greenDark : Theme.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }
}

struct CampaignMap: View {
    let profile: Profile
    let play: (Stage) -> Void
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        GeometryReader { g in
            let pts = points(in: g.size)
            ZStack {
                InsetWell(radius: 14.u)
                scenery(g.size)
                road(pts).stroke(Theme.woodDark.opacity(0.35), style: StrokeStyle(lineWidth: 9.u, lineCap: .round, lineJoin: .round))
                road(pts).stroke(Theme.parchment, style: StrokeStyle(lineWidth: 3.u, lineCap: .round, dash: [7.u, 6.u]))
                ForEach(Array(Stage.all.enumerated()), id: \.element.id) { i, s in
                    node(s).position(pts[i])
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let n = Stage.all.count, perRow = max(1, (n + 1) / 2)
        return (0..<n).map { i in
            let row = i / perRow, k = i % perRow
            let col = row % 2 == 0 ? k : perRow - 1 - k
            let x = size.width * (0.09 + 0.82 * CGFloat(col) / CGFloat(max(1, perRow - 1)))
            let y = size.height * (row == 0 ? 0.3 : 0.75) + (k % 2 == 0 ? -1 : 1) * size.height * 0.05
            return CGPoint(x: x, y: y)
        }
    }

    private func road(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for i in 1..<max(1, pts.count) {
            let a = pts[i - 1], b = pts[i]
            if abs(a.y - b.y) > 40.u && abs(a.x - b.x) < 30.u {
                let out = (a.x > 200 ? 1 : -1) * 46.u
                p.addCurve(to: b, control1: CGPoint(x: a.x + out, y: a.y), control2: CGPoint(x: b.x + out, y: b.y))
            } else {
                let mid = (a.x + b.x) / 2
                p.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
            }
        }
        return p
    }

    private func scenery(_ size: CGSize) -> some View {
        let marks: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("tree.fill", 0.03, 0.08, 16), ("mountain.2.fill", 0.24, 0.07, 22), ("tree.fill", 0.52, 0.1, 14), ("mountain.2.fill", 0.8, 0.06, 20),
            ("tree.fill", 0.96, 0.5, 15), ("water.waves", 0.38, 0.52, 18), ("tree.fill", 0.62, 0.52, 13), ("mountain.2.fill", 0.12, 0.93, 18),
            ("tree.fill", 0.45, 0.94, 15), ("tree.fill", 0.88, 0.95, 14), ("flag.2.crossed.fill", 0.03, 0.53, 14),
        ]
        return ZStack {
            ForEach(marks.indices, id: \.self) { i in
                let m = marks[i]
                Image(systemName: m.0).font(.system(size: m.3.u, weight: .bold)).foregroundStyle(Theme.woodDark.opacity(0.22))
                    .position(x: size.width * m.1, y: size.height * m.2)
            }
        }
        .allowsHitTesting(false)
    }

    private func node(_ s: Stage) -> some View {
        let open = profile.isOpen(s), stars = profile.stars(for: s), next = s.id == profile.nextStage.id && open
        let face: Color = !open ? Theme.stone : s.difficulty == .kolay ? Theme.green : s.difficulty == .orta ? Theme.gold : Theme.red
        return Button { play(s) } label: {
            VStack(spacing: 3.u) {
                ZStack {
                    Bevel(face: face, edge: face.darker(0.45), radius: 100, depth: 3.u)
                    if open {
                        Text("\(s.id)").font(Theme.display(19)).monospacedDigit().foregroundStyle(.white).embossed(width: 1, drop: 2)
                    } else {
                        Image(systemName: "lock.fill").font(Theme.icon(15, .black)).foregroundStyle(Theme.stoneLight.lighter(0.4)).embossed(width: 0.8, drop: 1.5)
                    }
                }
                .frame(width: 44.u, height: 44.u)
                .overlay(alignment: .topTrailing) {
                    if open && s.modifier != .none {
                        Image(systemName: Icons.modifier(s.modifier)).font(.system(size: 9.u, weight: .black)).foregroundStyle(.white)
                            .frame(width: 18.u, height: 18.u)
                            .background(Circle().fill(Theme.blue).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.2)))
                            .offset(x: 6.u, y: -4.u)
                    }
                }
                .padding(.bottom, 3.u)
                StarRow(earned: stars, size: 9)
            }
            .overlay(alignment: .top) { if next { NextPin().offset(y: -28.u) } }
        }
        .buttonStyle(PressStyle())
        .disabled(!open)
        .accessibilityLabel("\(Tx.stage(s.id)), \(Tx.name(s.difficulty))\(open ? "" : ", " + Tx.locked)")
    }
}

/// The flag over the stage to play next; it bobs unless motion is reduced.
private struct NextPin: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        Image(systemName: "flag.fill").font(.system(size: 17.u, weight: .black)).foregroundStyle(Theme.red)
            .embossed(width: 1, drop: 2)
            .phaseAnimator([false, true]) { v, up in v.offset(y: up && !still ? -4 : 0) } animation: { _ in .easeInOut(duration: 0.6) }
    }
}

// MARK: - Lobby and result cards

struct LobbyView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        Card(width: 500) {
            VStack(alignment: .leading, spacing: 13.u) {
                HStack(spacing: 12.u) {
                    Medallion(symbol: game.lobby.kind == .gameCenter || game.lobby.kind == .partyGameCenter ? "globe.europe.africa.fill" : "wifi",
                              tone: .blue, size: 44)
                    CardTitle(text: game.lobby.isParty ? Tx.partyTitle : game.lobby.kind == .gameCenter ? Tx.gameCenterTitle : Tx.nearbyTitle, size: 24)
                }
                HStack(spacing: 10.u) {
                    if game.lobby.busy { ProgressView().tint(Theme.woodDark).controlSize(.regular) }
                    Text(game.lobby.status.isEmpty ? Tx.preparing : game.lobby.status)
                        .font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12.u).padding(.vertical, 10.u)
                .background(InsetWell(radius: 12.u))
                if game.lobby.isParty && game.lobby.kind != .partyJoin {
                    HStack(spacing: 10.u) {
                        ForEach(0..<4, id: \.self) { i in
                            let here = i < game.lobby.players
                            Crest(color: Theme.team(i), size: 44.u) {
                                Image(systemName: here ? "person.fill" : "cpu").font(.system(size: 15.u, weight: .black)).foregroundStyle(.white)
                                    .embossed(width: 0.8, drop: 1.5)
                            }
                            .saturation(here ? 1 : 0.25).opacity(here ? 1 : 0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Tx.players): \(game.lobby.players)/4")
                }
                HStack(spacing: 14.u) {
                    if game.lobby.canStart {
                        Button { game.startPartyNow() } label: { Label(Tx.startNow, systemImage: "play.fill") }
                            .buttonStyle(ThemeButtonStyle(tone: .green, size: 17))
                    } else {
                        Button { game.playOnline(game.lobby.kind) } label: { Label(Tx.retry, systemImage: "arrow.clockwise") }
                            .buttonStyle(ThemeButtonStyle(tone: .blue, size: 17))
                    }
                    Button(Tx.cancel) { game.showMenu() }
                        .buttonStyle(ThemeButtonStyle(tone: .stone, size: 17))
                }
                .padding(.top, 2.u)
            }
        }
    }
}

/// What the match earned: XP with the level bar filling, trophies counting up, and any bonus worth calling out.
struct RewardPanel: View {
    let reward: Reward
    var showTrophies = true
    @State private var progress = 0.0
    @State private var xp = 0
    @State private var trophies = 0
    @State private var notesShown = 0
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        VStack(alignment: .leading, spacing: 6.u) {
            HStack(spacing: 10.u) {
                Text(Tx.xpGain(xp)).font(Theme.display(20)).monospacedDigit().foregroundStyle(Theme.blue).engraved()
                    .contentTransition(.numericText(value: Double(xp)))
                    .fixedSize()
                LevelBadge(level: reward.levelAfter, size: 30)
                VStack(alignment: .leading, spacing: 3.u) {
                    Text(Tx.level(reward.levelAfter)).font(Theme.body(12, .heavy)).foregroundStyle(Theme.text).lineLimit(1)
                    Meter(value: progress, color: Theme.blue, height: 9)
                }
                if showTrophies {
                    HStack(spacing: 4.u) {
                        Image(systemName: "trophy.fill").font(Theme.icon(16, .bold))
                        Text("\(reward.trophies >= 0 ? "+" : "−")\(abs(trophies))").font(Theme.display(20)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(trophies)))
                    }
                    .foregroundStyle(Color(hex: League.of(reward.totalTrophies).tint).darker(0.15))
                    .engraved()
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Tx.trophies(reward.trophies))
                }
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { i, n in
                if i < notesShown {
                    Label(n, systemImage: "star.fill").font(Theme.body(12, .heavy)).foregroundStyle(Theme.goldDark)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12.u).padding(.vertical, 9.u)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsetWell(radius: 12.u))
        .task { await reveal() }
    }

    /// Fills the level bar and counts the numbers up, then brings in the notes one by one.
    private func reveal() async {
        progress = reward.levelAfter > reward.levelBefore ? 0 : reward.progressBefore
        if still {
            progress = reward.progressAfter; xp = reward.xp; trophies = abs(reward.trophies); notesShown = notes.count
            return
        }
        withAnimation(.easeOut(duration: 1.1).delay(0.45)) { progress = reward.progressAfter }
        try? await Task.sleep(nanoseconds: 450_000_000)
        let steps = 14
        for s in 1...steps {
            try? await Task.sleep(nanoseconds: 55_000_000)
            withAnimation(.snappy(duration: 0.12)) {
                xp = reward.xp * s / steps
                trophies = abs(reward.trophies) * s / steps
            }
        }
        for i in 0..<notes.count {
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { notesShown = i + 1 }
        }
    }

    private var notes: [String] {
        var out: [String] = reward.achievements.map(Tx.achievementDone)
        if reward.gauntletNewBest { out.append(Tx.gauntletNewBest) }
        if let k = reward.unlockedPiece { out.append(Tx.pieceUnlocked(Tx.piece(k))) }
        if reward.levelAfter > reward.levelBefore {
            var line = Tx.levelUp(reward.levelAfter)
            if let b = reward.unlockedBall { line += " · " + Tx.unlocked(Tx.ball(b)) }
            if let h = HeartKind.allCases.last(where: { $0.level > reward.levelBefore && $0.level <= reward.levelAfter }) { line += " · " + Tx.heartUnlocked(Tx.heart(h)) }
            out.append(line)
        }
        if let l = reward.promotedTo { out.append(Tx.promoted(Tx.league(l))) }
        if reward.firstWin { out.append(Tx.firstWin) }
        if reward.siegeFirstToday { out.append(Tx.siegeFirst) }
        for m in reward.missions { out.append(Tx.missionDone(Tx.mission(m))) }
        return Array(out.prefix(Theme.roomy ? 5 : 3))      // what the card has room for
    }
}

/// Both players' numbers side by side; the better one in each row is set in ink, the other muted.
struct CompareTable: View {
    let names: [String]
    let stats: [MatchStats]
    var body: some View {
        Grid(horizontalSpacing: 10.u, verticalSpacing: 5.u) {
            GridRow {
                name(names[0], Theme.red)
                Text("")
                name(names[1], Theme.blue)
            }
            Divider().overlay(Theme.parchmentEdge).gridCellUnsizedAxes(.horizontal)
            row(Tx.accuracy, stats[0].accuracy, stats[1].accuracy) { Tx.pct($0) }
            row(Tx.bestHit, stats[0].bestHit, stats[1].bestHit) { $0 > 0 ? "−" + Tx.pct($0) : "–" }
            row(Tx.criticals, stats[0].crits, stats[1].crits) { "\($0)" }
        }
        .padding(.horizontal, 12.u).padding(.vertical, 9.u)
        .frame(maxWidth: .infinity)
        .background(InsetWell(radius: 12.u))
    }

    private func name(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4.u) {
            Crest(color: color, size: 15.u) { EmptyView() }
            Text(text).font(Theme.display(13)).foregroundStyle(color.darker(0.1)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func row(_ label: String, _ a: Int, _ b: Int, _ text: (Int) -> String) -> some View {
        GridRow {
            Text(text(a)).font(Theme.display(17)).monospacedDigit().foregroundStyle(a >= b ? Theme.text : Theme.muted.opacity(0.8))
            Text(label).font(Theme.body(11, .bold)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.6)
            Text(text(b)).font(Theme.display(17)).monospacedDigit().foregroundStyle(b >= a ? Theme.text : Theme.muted.opacity(0.8))
        }
    }
}

private enum Outcome { case win, loss, neutral }

private extension OverInfo {
    /// Read from what the card says, since a draw-free match only ever ends one of these ways.
    var outcome: Outcome {
        if title == Tx.won || title == Tx.siegeCleared || (reward?.stars ?? 0) > 0 || hasNextStage || gauntletNext { return .win }
        if title == Tx.lost || title == Tx.gauntletOver || title == Tx.gameOver { return .loss }
        if reward != nil && !isSiege { return .loss }
        return .neutral
    }
}

/// Three stars popping in one after another, the middle one raised.
private struct StarPop: View {
    let earned: Int
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        HStack(alignment: .bottom, spacing: 4.u) {
            ForEach(0..<3, id: \.self) { i in
                let lit = i < earned
                GemStar(lit: lit && i < shown, size: (i == 1 ? 40 : 31).u)
                    .scaleEffect(lit && i < shown && !still ? 1 : lit && !still ? 0.4 : 1)
                    .rotationEffect(.degrees(i == 0 ? -12 : i == 2 ? 12 : 0))
                    .offset(y: i == 1 ? -6.u : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned)/3")
        .task {
            if still { shown = 3; return }
            for i in 0..<3 {
                try? await Task.sleep(nanoseconds: (i == 0 ? 450 : 280) * 1_000_000)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) { shown = i + 1 }
                if i < earned { Haptics.tap(.rigid) }
            }
        }
    }
}

struct OverView: View {
    @EnvironmentObject var game: GameController
    var body: some View {
        let o = game.over
        let outcome = o?.outcome ?? .neutral
        Card(width: 660, inset: Theme.roomy ? 19 : 14) {
            VStack(spacing: 6.u) {
                Ribbon(tone: outcome == .win ? .gold : outcome == .loss ? .stone : .blue) {
                    Text(outcome == .win ? Tx.victory : outcome == .loss ? Tx.defeat : (o?.title ?? ""))
                        .font(Theme.display(26)).foregroundStyle(.white).embossed(width: 1.5, drop: 3)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: 420.u)
                .padding(.top, -40.u)
                .padding(.bottom, 6.u)
                if let stars = o?.reward?.stars { StarPop(earned: stars) }
                VStack(spacing: 2.u) {
                    if outcome != .neutral, let t = o?.title, t != Tx.won, t != Tx.lost {
                        Text(t).font(Theme.display(18)).foregroundStyle(Theme.woodDark).engraved().lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(o?.detail ?? "").font(Theme.body(13, .semibold)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 10.u) {
                    if let o, o.isSiege, let r = o.reward {
                        VStack(spacing: 8.u) {
                            HStack(spacing: 8.u) {
                                StatTile(label: Tx.todayBest, value: "\(r.siegeBest)")
                                StatTile(label: Tx.record, value: "\(r.siegeRecord)")
                            }
                            if r.siegeNewBest {
                                Label(Tx.newBest, systemImage: "star.fill").font(Theme.body(13, .heavy)).foregroundStyle(Theme.goldDark)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else if let o, let mine = o.stats, let theirs = o.rivalStats, o.names.count == 2 {
                        CompareTable(names: o.names, stats: o.side == 0 ? [mine, theirs] : [theirs, mine])
                    }
                    if let r = o?.reward { RewardPanel(reward: r, showTrophies: o?.isSiege != true).frame(maxWidth: .infinity) }
                }
                HStack(spacing: 14.u) {
                    Button { game.rematch() } label: { Label(again(o), systemImage: o?.hasNextStage == true || o?.gauntletNext == true ? "arrow.right" : "arrow.clockwise") }
                        .buttonStyle(ThemeButtonStyle(tone: .green, size: 17))
                        .disabled(o?.waiting == true)
                    Button { game.showMenu() } label: { Label(Tx.mainMenu, systemImage: "house.fill") }
                        .buttonStyle(ThemeButtonStyle(tone: .stone, size: 17))
                }
                .padding(.top, 3.u)
            }
        }
        .onAppear { Haptics.tap(outcome == .win ? .heavy : .medium) }
    }

    private func again(_ o: OverInfo?) -> String {
        if o?.waiting == true { return Tx.waitingOpponent }
        if o?.hasNextStage == true { return Tx.nextStage }
        if o?.isGauntlet == true { return o?.gauntletNext == true ? Tx.nextCastle : Tx.newRun }
        return o?.isSiege == true ? Tx.tryAgain : Tx.playAgain
    }
}

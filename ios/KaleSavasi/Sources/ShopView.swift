import StoreKit
import SwiftUI

// The shop: one-time cosmetic purchases, and the "My Look" tab that equips what the player owns.

enum ShopTab: String, CaseIterable, Identifiable {
    case featured, skins, trails, hearts, look
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .featured: return "crown.fill"
        case .skins: return "building.columns.fill"
        case .trails: return "sparkles"
        case .hearts: return "suit.diamond.fill"
        case .look: return "paintpalette.fill"
        }
    }
    static func of(_ item: ShopItem) -> ShopTab {
        switch item {
        case .supporter: return .featured
        case .gold, .obsidian, .marble, .candy: return .skins
        case .rainbow, .lightning, .starfall, .fireworks: return .trails
        case .hearts, .banners: return .hearts
        }
    }
}

struct ShopView: View {
    @EnvironmentObject var game: GameController
    @EnvironmentObject var store: Store

    var body: some View {
        GeometryReader { g in
            let contentH = min((Theme.roomy ? 470 : 330).u, max(170, g.size.height - 176.u))
            Card(width: 900, inset: Theme.roomy ? 19 : 11) {
                VStack(alignment: .leading, spacing: 7.u) {
                    header
                    tabs
                    Group {
                        switch game.shopTab {
                        case .featured: FeaturedTab(height: contentH)
                        case .skins: ItemRow(items: [.gold, .obsidian, .marble, .candy], height: contentH)
                        case .trails: ItemRow(items: [.rainbow, .lightning, .starfall, .fireworks], height: contentH)
                        case .hearts: ItemRow(items: [.hearts, .banners], height: contentH)
                        case .look: LookTab(height: contentH)
                        }
                    }
                    .frame(height: contentH)
                    .clipped()
                    .id(game.shopTab)
                    .transition(.opacity)
                    footer
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .animation(.easeOut(duration: 0.18), value: game.shopTab)
        .onChange(of: store.notice) { _, n in if let n { handle(n) } }
        .task { if store.products.isEmpty { await store.loadProducts() } }
    }

    private var header: some View {
        HStack(spacing: 10.u) {
            Medallion(symbol: "bag.fill", tone: .gold, size: 38)
            CardTitle(text: Tx.shop).fixedSize()
            if game.myLook.supporter { CrownBadge(size: 18) }
            Spacer(minLength: 8)
            Button { Task { await store.restore() } } label: {
                HStack(spacing: 6.u) {
                    if store.restoring { ProgressView().tint(.white).controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    Text(Theme.roomy ? Tx.restorePurchases : Tx.restoreShort)
                }
            }
            .buttonStyle(ThemeButtonStyle(tone: .stone, size: 13, fill: false, compact: true))
            .disabled(store.restoring)
            .accessibilityLabel(Tx.restorePurchases)
            CloseButton { game.panel = .home }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5.u) {
                ForEach(ShopTab.allCases) { t in
                    Button { game.shopTab = t; game.sfx.play(.tick) } label: {
                        Label(Tx.shopTab(t), systemImage: t.icon)
                    }
                    .buttonStyle(PillStyle(selected: game.shopTab == t, size: 12.5))
                    .accessibilityAddTraits(game.shopTab == t ? .isSelected : [])
                }
            }
            .padding(.horizontal, 6.u).padding(.vertical, 4.u)
        }
        .background(WoodPanel(radius: 100, dark: true, drop: 2))
    }

    private var footer: some View {
        HStack(spacing: 8.u) {
            Image(systemName: "info.circle.fill").font(Theme.icon(11, .bold)).foregroundStyle(Theme.muted)
            Text(Tx.shopLegal).font(Theme.body(10.5, .semibold)).foregroundStyle(Theme.muted).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if store.loadFailed && !store.loading {
                Button { Task { await store.loadProducts() } } label: { Label(Tx.retry, systemImage: "wifi.exclamationmark") }
                    .buttonStyle(ThemeButtonStyle(tone: .blue, size: 11, fill: false, compact: true))
                    .accessibilityHint(Tx.shopOffline)
            }
        }
    }

    private func handle(_ n: Store.Notice) {
        switch n {
        case .purchased(let id):
            let name = ShopItem.with(productID: id).map(Tx.shopItem) ?? ""
            game.show(toast: Tx.shopThanks(name))
            game.sfx.play(.win)
            game.thump(.heavy)
        case .pending: game.show(toast: Tx.shopPending)
        case .failed(let why): game.show(toast: Tx.shopFailed(why)); game.sfx.play(.thud)
        case .unavailable: game.show(toast: Tx.shopUnavailable); game.sfx.play(.thud)
        case .restored(let k): game.show(toast: Tx.restored(k)); game.sfx.play(.charged)
        case .nothingToRestore: game.show(toast: Tx.nothingToRestore)
        case .restoreFailed(let why): game.show(toast: Tx.restoreFailed(why)); game.sfx.play(.thud)
        }
        store.notice = nil
    }
}

// MARK: - Buying

/// Buys an item and equips it straight away.
@MainActor
func shopBuy(_ item: ShopItem, store: Store, game: GameController) {
    Task { @MainActor in
        let result = await store.buy(item.productID)
        #if DEBUG
        print("STORE buy \(item.productID) -> \(result)")
        #endif
        guard result == .purchased else { return }
        shopAutoEquip(item, game: game)
    }
}

func shopAutoEquip(_ item: ShopItem, game: GameController) {
    let look = game.myLook
    switch item {
    case .supporter: game.equip(skin: .royal, trail: .royal, banner: look.banner == .none ? .lion : nil)
    case .gold, .obsidian, .marble, .candy: game.equip(skin: item.skin)
    case .rainbow, .lightning, .starfall: game.equip(trail: item.trail)
    case .fireworks: game.equip(impact: .fireworks)
    case .hearts: if look.gem == .none { game.equip(gem: .emerald) }
    case .banners: if look.banner == .none { game.equip(banner: .lion) }
    }
}

/// The price button, or what the player can do with an item they own.
struct BuyButton: View {
    @EnvironmentObject var game: GameController
    @EnvironmentObject var store: Store
    let item: ShopItem
    /// Owned items that can be worn: whether it is on now, and how to put it on.
    var equipped: Bool? = nil
    var equip: (() -> Void)? = nil
    var big = false

    var body: some View {
        let owned = store.owns(item.productID)
        if owned {
            if let equip, let on = equipped {
                Button(action: equip) {
                    Label(on ? Tx.equipped : Tx.equip, systemImage: on ? "checkmark.circle.fill" : "paintbrush.fill")
                }
                .buttonStyle(ThemeButtonStyle(tone: on ? .parchment : .green, size: big ? 17 : 14, compact: !big))
                .disabled(on)
            } else {
                Label(Tx.owned, systemImage: "checkmark.seal.fill")
                    .font(Theme.display(big ? 16 : 13)).foregroundStyle(Theme.greenDark)
                    .frame(maxWidth: .infinity).padding(.vertical, 8.u)
                    .background(Capsule().fill(Theme.green.opacity(0.18)).overlay(Capsule().strokeBorder(Theme.greenDark.opacity(0.6), lineWidth: 1.5)))
            }
        } else {
            let price = displayPrice
            Button { shopBuy(item, store: store, game: game) } label: {
                HStack(spacing: 6.u) {
                    if store.buying == item.productID {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "cart.fill")
                        Text(price ?? "—").monospacedDigit()
                    }
                }
            }
            .buttonStyle(ThemeButtonStyle(tone: .gold, size: big ? 18 : 15, compact: !big))
            .disabled(store.buying != nil || price == nil)
            .accessibilityLabel("\(Tx.shopItem(item)), \(price ?? "")")
        }
    }

    /// The App Store's localized price. Debug builds without StoreKit fall back to the list price.
    private var displayPrice: String? {
        if let p = store.product(item.productID) { return p.displayPrice }
        #if DEBUG
        return item.referencePrice
        #else
        return nil
        #endif
    }
}

// MARK: - Featured

private struct FeaturedTab: View {
    @EnvironmentObject var game: GameController
    @EnvironmentObject var store: Store
    let height: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16.u, style: .continuous)
        GeometryReader { g in
        let pw = min(height * 1.35, g.size.width * 0.56), ph = height - 24.u
        HStack(spacing: 14.u) {
            ZStack(alignment: .topLeading) {
                CastlePreview(skin: .royal, gem: .amethyst, banner: .lion, renderSize: CGSize(width: 720, height: 480))
                    .frame(width: pw, height: ph)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.goldDark, lineWidth: 3))
                    .overlay(shape.inset(by: 3).strokeBorder(Theme.goldLight.opacity(0.7), lineWidth: 1.5))
                TrailPreview(trail: .royal)
                    .frame(width: pw * 0.46, height: ph * 0.38)
                    .clipShape(RoundedRectangle(cornerRadius: 10.u, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10.u, style: .continuous).strokeBorder(Theme.goldDark, lineWidth: 2))
                    .padding(8.u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                Text(Tx.bestValue.uppercased()).font(Theme.body(11, .black)).foregroundStyle(.white)
                    .padding(.horizontal, 9.u).padding(.vertical, 4.u)
                    .background(Capsule().fill(Theme.red).overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5)))
                    .rotationEffect(.degrees(-6))
                    .padding(10.u)
            }
            .frame(width: pw, height: ph)
            VStack(alignment: .leading, spacing: 7.u) {
                HStack(spacing: 8.u) {
                    CrownBadge(size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Tx.supporterTagline.uppercased()).font(Theme.body(11, .black)).foregroundStyle(Theme.purple)
                        Text(Tx.shopItem(.supporter)).font(Theme.display(24)).foregroundStyle(Theme.woodDark).engraved()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Text(Tx.shopDetail(.supporter)).font(Theme.body(12, .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(Theme.roomy ? 3 : 2).minimumScaleFactor(0.75)
                Grid(alignment: .leading, horizontalSpacing: 10.u, verticalSpacing: 5.u) {
                    GridRow {
                        perk("building.columns.fill", Tx.perkRoyalSkin, .purple)
                        perk("sparkles", Tx.perkRoyalTrail, .purple)
                    }
                    GridRow {
                        perk("crown.fill", Tx.perkCrown, .gold)
                        perk("flag.fill", Tx.perkBanners, .red)
                    }
                }
                Spacer(minLength: 0)
                BuyButton(item: .supporter, equipped: game.myLook.skin == .royal && game.myLook.trail == .royal,
                          equip: { game.equip(skin: .royal, trail: .royal) }, big: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10.u)
        .background {
            shape.fill(LinearGradient(colors: [Theme.purple.opacity(0.22), Theme.goldLight.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.strokeBorder(Theme.purpleDark.opacity(0.5), lineWidth: 1.5))
        }
        }
    }

    private func perk(_ icon: String, _ text: String, _ tone: Tone) -> some View {
        HStack(spacing: 7.u) {
            Medallion(symbol: icon, tone: tone, size: 22)
            Text(text).font(Theme.body(12.5, .heavy)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Item cards

private struct ItemRow: View {
    let items: [ShopItem]
    let height: CGFloat
    var body: some View {
        GeometryReader { g in
            let gap = 10.u
            let fitW = (g.size.width - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
            let w = max(items.count <= 2 ? 300.u : 150.u, fitW)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: gap) {
                    ForEach(items) { item in ItemCard(item: item, height: height).frame(width: w) }
                }
                .frame(minWidth: g.size.width, alignment: .center)
            }
        }
    }
}

private struct ItemCard: View {
    @EnvironmentObject var game: GameController
    @EnvironmentObject var store: Store
    let item: ShopItem
    let height: CGFloat

    var body: some View {
        let owned = store.owns(item.productID)
        let shape = RoundedRectangle(cornerRadius: 14.u, style: .continuous)
        VStack(alignment: .leading, spacing: 5.u) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: height * (item == .hearts || item == .banners ? 0.33 : 0.47))
                .clipShape(RoundedRectangle(cornerRadius: 10.u, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10.u, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
            HStack(spacing: 5.u) {
                Text(Tx.shopItem(item)).font(Theme.display(15)).foregroundStyle(Theme.woodDark).engraved().lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if owned { Image(systemName: "checkmark.seal.fill").font(Theme.icon(13, .bold)).foregroundStyle(Theme.green) }
            }
            Text(Tx.shopDetail(item)).font(Theme.body(10.5, .semibold)).foregroundStyle(Theme.muted)
                .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            if item == .hearts { gemPicker(owned) }
            if item == .banners { bannerPicker(owned) }
            Spacer(minLength: 0)
            action
        }
        .padding(8.u)
        .frame(height: height)
        .background {
            if owned {
                shape.fill(LinearGradient(colors: [Theme.goldLight.opacity(0.45), Theme.parchmentDark.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Theme.goldDark.opacity(0.8), lineWidth: 1.5))
            } else { InsetWell(radius: 14.u) }
        }
    }

    @ViewBuilder private var preview: some View {
        switch item {
        case .gold, .obsidian, .marble, .candy: CastlePreview(skin: item.skin ?? .classic)
        case .rainbow, .lightning, .starfall: TrailPreview(trail: item.trail ?? .none)
        case .fireworks: FireworksPreview()
        case .hearts:
            HStack(spacing: 12.u) { ForEach(HeartGem.allCases.dropFirst()) { HeartGemIcon(gem: $0, size: height * 0.24) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [Color(hex: 0x2a1a2e), Color(hex: 0x4a2f4f)], startPoint: .top, endPoint: .bottom))
        case .banners:
            HStack(spacing: 6.u) { ForEach(Banner.allCases.dropFirst()) { BannerFlag(banner: $0, color: Look.accent[$0 == .eagle ? 1 : $0 == .wolf ? 2 : 0], height: height * 0.16) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [Color(hex: 0x6fb6ef), Color(hex: 0xcfe6f7)], startPoint: .top, endPoint: .bottom))
        case .supporter: CastlePreview(skin: .royal, gem: .amethyst, banner: .lion)
        }
    }

    @ViewBuilder private var action: some View {
        let look = game.myLook
        switch item {
        case .gold, .obsidian, .marble, .candy:
            BuyButton(item: item, equipped: look.skin == item.skin, equip: { game.equip(skin: item.skin) })
        case .rainbow, .lightning, .starfall:
            BuyButton(item: item, equipped: look.trail == item.trail, equip: { game.equip(trail: item.trail) })
        case .fireworks:
            BuyButton(item: item, equipped: look.impact == .fireworks, equip: { game.equip(impact: .fireworks) })
        case .hearts, .banners, .supporter:
            BuyButton(item: item)
        }
    }

    /// Owned packs: pick a colour or crest right on the card.
    private func gemPicker(_ owned: Bool) -> some View {
        HStack(spacing: 6.u) {
            ForEach(HeartGem.allCases) { g in
                pick(selected: owned && game.myLook.gem == g, enabled: owned, label: Tx.gem(g)) { game.equip(gem: g) } face: {
                    if g == .none { Image(systemName: "circle.slash").font(Theme.icon(12, .bold)).foregroundStyle(Theme.muted) } else { HeartGemIcon(gem: g, size: 18.u) }
                }
            }
        }
    }

    private func bannerPicker(_ owned: Bool) -> some View {
        HStack(spacing: 6.u) {
            ForEach(Banner.allCases) { b in
                pick(selected: owned && game.myLook.banner == b, enabled: owned, label: Tx.banner(b)) { game.equip(banner: b) } face: {
                    if b == .none { Image(systemName: "flag.slash").font(Theme.icon(12, .bold)).foregroundStyle(Theme.muted) }
                    else { Image(uiImage: Emblem.crest(b, size: 64)).resizable().scaledToFit().frame(width: 20.u, height: 20.u) }
                }
            }
        }
    }

    private func pick<F: View>(selected: Bool, enabled: Bool, label: String, action: @escaping () -> Void, @ViewBuilder face: () -> F) -> some View {
        let s = RoundedRectangle(cornerRadius: 8.u, style: .continuous)
        return Button(action: action) {
            face().frame(width: 28.u, height: 28.u)
                .background(s.fill(selected ? Theme.goldLight.opacity(0.8) : Theme.parchment.opacity(0.85)))
                .overlay(s.strokeBorder(selected ? Theme.goldDark : Theme.woodDark.opacity(0.4), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.7)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - My Look

/// Everything the player can wear, by kind. Locked options are shown too; tapping one opens it in the shop.
struct LookTab: View {
    @EnvironmentObject var game: GameController
    @EnvironmentObject var store: Store
    let height: CGFloat

    var body: some View {
        let look = game.myLook, owned = store.owned
        ScrollView {
            VStack(alignment: .leading, spacing: 7.u) {
                Text(Tx.myLookHint).font(Theme.body(11, .semibold)).foregroundStyle(Theme.muted)
                row("building.columns.fill", Tx.castleSkin) {
                    ForEach(Skin.allCases) { s in
                        option(Tx.skin(s), selected: look.skin == s, locked: !s.unlocked(by: owned), tab: s == .royal ? .featured : .skins,
                               action: { game.equip(skin: s) }) { SkinSwatch(skin: s, size: 10.u) }
                    }
                }
                row("sparkles", Tx.trailTitle) {
                    ForEach(Trail.allCases) { t in
                        option(Tx.trail(t), selected: look.trail == t, locked: !t.unlocked(by: owned), tab: t == .royal ? .featured : .trails,
                               action: { game.equip(trail: t) }) {
                            Capsule().fill(LinearGradient(colors: t.colors.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing))
                                .frame(width: 34.u, height: 9.u).overlay(Capsule().strokeBorder(Theme.ink.opacity(0.7), lineWidth: 1))
                        }
                    }
                }
                row("burst.fill", Tx.impactTitle) {
                    ForEach(ImpactEffect.allCases) { i in
                        option(Tx.impact(i), selected: look.impact == i, locked: !i.unlocked(by: owned), tab: .trails, action: { game.equip(impact: i) }) {
                            Image(systemName: i == .none ? "smoke.fill" : "sparkles").font(Theme.icon(13, .bold))
                                .foregroundStyle(i == .none ? AnyShapeStyle(Theme.stone) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xff3b5c), Color(hex: 0xffd34d), Color(hex: 0x3fa8ff)], startPoint: .leading, endPoint: .trailing)))
                        }
                    }
                }
                row("suit.diamond.fill", Tx.heartGem) {
                    ForEach(HeartGem.allCases) { g in
                        option(Tx.gem(g), selected: look.gem == g, locked: !g.unlocked(by: owned), tab: .hearts, action: { game.equip(gem: g) }) {
                            HeartGemIcon(gem: g, size: 17.u)
                        }
                    }
                }
                row("flag.fill", Tx.bannerTitle) {
                    ForEach(Banner.allCases) { b in
                        option(Tx.banner(b), selected: look.banner == b, locked: !b.unlocked(by: owned), tab: .hearts, action: { game.equip(banner: b) }) {
                            if b == .none { Image(systemName: "flag.fill").font(Theme.icon(12, .bold)).foregroundStyle(Theme.red) }
                            else { Image(uiImage: Emblem.crest(b, size: 64)).resizable().scaledToFit().frame(width: 18.u, height: 18.u) }
                        }
                    }
                }
            }
            .padding(.bottom, 4.u)
        }
    }

    private func row<C: View>(_ icon: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8.u) {
            Label(title, systemImage: icon).font(Theme.body(12.5, .heavy)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 118.u, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6.u) { content() }.padding(.vertical, 2) }
        }
        .padding(.horizontal, 9.u).padding(.vertical, 5.u)
        .background(InsetWell(radius: 11.u))
    }

    private func option<F: View>(_ name: String, selected: Bool, locked: Bool, tab: ShopTab, action: @escaping () -> Void, @ViewBuilder face: () -> F) -> some View {
        let s = RoundedRectangle(cornerRadius: 9.u, style: .continuous)
        return Button {
            if locked { game.shopTab = tab; game.sfx.play(.tick) } else { action() }
        } label: {
            HStack(spacing: 5.u) {
                face()
                Text(name).font(Theme.body(11.5, .heavy)).foregroundStyle(locked ? Theme.muted : Theme.text).lineLimit(1)
                if locked { Image(systemName: "lock.fill").font(Theme.icon(9, .black)).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 8.u).padding(.vertical, 5.u)
            .background(s.fill(selected ? Theme.goldLight.opacity(0.75) : Theme.parchment.opacity(locked ? 0.5 : 0.9)))
            .overlay(s.strokeBorder(selected ? Theme.goldDark : Theme.woodDark.opacity(0.35), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(locked ? "\(name), \(Tx.shop)" : name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

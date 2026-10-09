import StoreKit
import StoreKitTest
import XCTest
@testable import KaleSavasi

/// The shop against the local StoreKit configuration (`StoreKit/Products.storekit`): products load,
/// a purchase grants its entitlement, a refund takes it away, and cosmetics follow ownership.
final class StoreTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defaults = UserDefaults(suiteName: "store-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        session.clearTransactions()
    }

    private func makeStore() -> Store { Store(defaults: defaults, ownAll: false) }

    func testAllProductsLoadWithPrices() async {
        let store = makeStore()
        await store.loadProducts()
        XCTAssertEqual(Set(store.products.keys), Set(Catalog.all))
        let prices = Dictionary(uniqueKeysWithValues: store.products.map { ($0.key, $0.value.price) })
        XCTAssertEqual(prices[Catalog.gold], Decimal(string: "2.99"))
        XCTAssertEqual(prices[Catalog.obsidian], Decimal(string: "2.99"))
        XCTAssertEqual(prices[Catalog.marble], Decimal(string: "1.99"))
        XCTAssertEqual(prices[Catalog.candy], Decimal(string: "1.99"))
        XCTAssertEqual(prices[Catalog.hearts], Decimal(string: "1.99"))
        XCTAssertEqual(prices[Catalog.supporter], Decimal(string: "4.99"))
        for id in [Catalog.rainbow, Catalog.lightning, Catalog.starfall, Catalog.fireworks, Catalog.banners] {
            XCTAssertEqual(prices[id], Decimal(string: "0.99"), id)
        }
        for p in store.products.values { XCTAssertEqual(p.type, .nonConsumable, p.id) }
        // Every product has a shop item, and every shop item a product.
        XCTAssertEqual(Set(ShopItem.allCases.map(\.productID)), Set(Catalog.all))
    }

    func testPurchaseGrantsEntitlementAndCachesIt() async {
        let store = makeStore()
        await store.loadProducts()
        XCTAssertFalse(store.owns(Catalog.gold))
        let outcome = await store.buy(Catalog.gold)
        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(store.owns(Catalog.gold))
        // A fresh store (an offline relaunch) starts from the cache, then entitlements.
        let relaunch = makeStore()
        XCTAssertTrue(relaunch.owns(Catalog.gold))
        await relaunch.refreshEntitlements()
        XCTAssertTrue(relaunch.owns(Catalog.gold))
    }

    func testRefundRevokesEntitlement() async throws {
        let store = makeStore()
        await store.loadProducts()
        XCTAssertEqual(await store.buy(Catalog.rainbow), .purchased)
        XCTAssertTrue(store.owns(Catalog.rainbow))
        let t = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == Catalog.rainbow })
        try session.refundTransaction(identifier: t.identifier)
        await store.refreshEntitlements()
        XCTAssertFalse(store.owns(Catalog.rainbow))
        // The cache follows the entitlements, so a relaunch does not bring it back.
        XCTAssertFalse(makeStore().owns(Catalog.rainbow))
    }

    func testRestoreKeepsWhatIsOwned() async {
        let store = makeStore()
        await store.loadProducts()
        XCTAssertEqual(await store.buy(Catalog.supporter), .purchased)
        await store.restore()
        XCTAssertTrue(store.owns(Catalog.supporter))
        XCTAssertNotNil(store.notice)
    }

    func testCosmeticsFollowOwnership() {
        var p = Profile()
        p.equipSkin = "gold"; p.equipTrail = "royal"; p.equipImpact = "fireworks"; p.equipGem = "sapphire"; p.equipBanner = "wolf"
        // Nothing owned: everything falls back to the default look.
        XCTAssertEqual(p.cosmetics(owned: []), .plain)
        // The Supporter Pack unlocks the Royal trail and every banner, and the crown.
        let supporter = p.cosmetics(owned: [Catalog.supporter])
        XCTAssertEqual(supporter.skin, .classic)
        XCTAssertEqual(supporter.trail, .royal)
        XCTAssertEqual(supporter.banner, .wolf)
        XCTAssertTrue(supporter.supporter)
        let all = p.cosmetics(owned: Set(Catalog.all))
        XCTAssertEqual(all, Cosmetics(skin: .gold, trail: .royal, impact: .fireworks, gem: .sapphire, banner: .wolf, supporter: true))
        XCTAssertTrue(Banner.lion.unlocked(by: [Catalog.banners]))
        XCTAssertFalse(Skin.royal.unlocked(by: [Catalog.banners]))
    }

    func testHelloCosmeticsAreOptionalAndValidated() throws {
        // An older build's hello has no cosmetics at all.
        let old = try JSONDecoder().decode(NetMessage.self, from: Data(#"{"t":"hello","nonce":7,"name":"Ada","rules":6}"#.utf8))
        XCTAssertEqual(old.cosmetics, .plain)
        // Unknown values (a newer build's skin) fall back to the default; known ones are kept.
        let new = try JSONDecoder().decode(NetMessage.self, from: Data(#"{"t":"hello","skin":"plasma","trail":"lightning","gem":"emerald","banner":"eagle","supporter":true}"#.utf8))
        XCTAssertEqual(new.cosmetics, Cosmetics(skin: .classic, trail: .lightning, gem: .emerald, banner: .eagle, supporter: true))
        // Round trip.
        var m = NetMessage(t: "hello")
        m.attach(Cosmetics(skin: .obsidian, trail: .starfall, impact: .fireworks, gem: .sunfire, banner: .dragon, supporter: false))
        let back = try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.cosmetics, m.cosmetics)
        // Four-castle seats: missing or malformed looks never fail the message.
        let seats = try JSONDecoder().decode([SeatInfo].self, from: Data(#"[{"nonce":1,"name":"A","level":2,"design":[]},{"nonce":2,"name":"B","level":3,"design":[],"look":{"skin":7,"trail":"rainbow"}}]"#.utf8))
        XCTAssertNil(seats[0].look)
        XCTAssertEqual(seats[1].look, Cosmetics(trail: .rainbow))
    }

    func testRulesVersionUnchanged() {
        // Cosmetics are drawn only; online matches must keep playing by the same rules.
        XCTAssertEqual(K.rulesVersion, 6)
    }
}

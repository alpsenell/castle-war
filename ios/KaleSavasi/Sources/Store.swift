import Foundation
import StoreKit

// In-app purchases with StoreKit 2. Every product is a one-time, non-consumable cosmetic.
// What the player owns comes only from StoreKit: `Transaction.currentEntitlements` (minus
// revoked transactions) is the source of truth. The owned IDs are cached so cosmetics show at
// once on an offline launch, but the cache is always replaced by a fresh read of the entitlements.

final class Store: ObservableObject {
    static let shared = Store()

    enum Notice: Equatable {
        case purchased(String)
        case pending
        case failed(String)
        case unavailable
        case restored(Int)
        case nothingToRestore
        case restoreFailed(String)
    }

    /// What a purchase came to; returned for tests and logs.
    enum Outcome: Equatable { case purchased, cancelled, pending, unverified, unavailable, failed(String) }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var owned: Set<String>
    /// The product being bought right now.
    @Published private(set) var buying: String?
    @Published private(set) var restoring = false
    @Published private(set) var loading = false
    /// Products could not be fetched (offline, or not set up yet).
    @Published private(set) var loadFailed = false
    @Published var notice: Notice?

    private static let cacheKey = "store.owned.v1"
    private var updates: Task<Void, Never>?
    private let defaults: UserDefaults
    /// Debug builds: "-ownAll" pretends every product is owned.
    private let ownAll: Bool

    init(defaults: UserDefaults = .standard, ownAll: Bool? = nil) {
        self.defaults = defaults
        #if DEBUG
        self.ownAll = ownAll ?? ProcessInfo.processInfo.arguments.contains("-ownAll")
        #else
        self.ownAll = false
        #endif
        let cached = Set(defaults.stringArray(forKey: Store.cacheKey) ?? []).intersection(Catalog.all)
        owned = self.ownAll ? Set(Catalog.all) : cached
    }

    deinit { updates?.cancel() }

    /// Starts listening for transactions made elsewhere (Ask to Buy, another device, refunds) and
    /// loads products and entitlements. Called once at launch.
    func start() {
        guard updates == nil else { return }
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { @MainActor in
            await self.refreshEntitlements()
            await self.loadProducts()
        }
    }

    func owns(_ productID: String) -> Bool { owned.contains(productID) }

    func product(_ id: String) -> Product? { products[id] }

    // MARK: Products

    @MainActor
    func loadProducts() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let list = try await Product.products(for: Catalog.all)
            var map: [String: Product] = [:]
            for p in list { map[p.id] = p }
            products = map
            loadFailed = map.isEmpty
        } catch {
            loadFailed = products.isEmpty
            #if DEBUG
            print("STORE products failed: \(error)")
            #endif
        }
        #if DEBUG
        print("STORE products loaded: \(products.keys.sorted())")
        #endif
    }

    // MARK: Entitlements

    /// Product IDs with a verified, unrevoked current entitlement.
    static func currentEntitlements() async -> Set<String> {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { ids.insert(t.productID) }
        }
        return ids
    }

    func refreshEntitlements() async {
        let ids = await Store.currentEntitlements()
        await MainActor.run { self.apply(ids) }
    }

    @MainActor
    private func apply(_ ids: Set<String>) {
        let mine = ids.intersection(Catalog.all)
        defaults.set(Array(mine).sorted(), forKey: Store.cacheKey)
        let shown = ownAll ? Set(Catalog.all) : mine
        if shown != owned { owned = shown }
        #if DEBUG
        print("STORE owned: \(mine.sorted())")
        #endif
    }

    // MARK: Buying

    @MainActor
    @discardableResult
    func buy(_ id: String) async -> Outcome {
        guard buying == nil else { return .cancelled }
        buying = id
        defer { buying = nil }
        do {
            var product = products[id]
            if product == nil { product = try await Product.products(for: [id]).first }
            guard let product else { notice = .unavailable; return .unavailable }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    await t.finish()
                    await refreshEntitlements()
                    notice = .purchased(id)
                    return .purchased
                case .unverified(_, let error):
                    notice = .failed(error.localizedDescription)
                    return .unverified
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                notice = .pending
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            notice = .failed(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    /// Restore Purchases: asks the App Store to sync, then reads the entitlements again. A failed
    /// sync (offline, sign-in cancelled, the StoreKit test environment) never hides what is owned.
    @MainActor
    func restore() async {
        guard !restoring else { return }
        restoring = true
        defer { restoring = false }
        var syncError: Error?
        do { try await AppStore.sync() } catch { syncError = error }
        await refreshEntitlements()
        let real = await Store.currentEntitlements().intersection(Catalog.all)
        if let syncError, real.isEmpty {
            notice = .restoreFailed(syncError.localizedDescription)
        } else {
            notice = real.isEmpty ? .nothingToRestore : .restored(real.count)
        }
    }
}

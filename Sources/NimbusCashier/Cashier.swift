import Foundation
import StoreKit

/// Nimbus Cashier for Apple platforms: in-app purchases through StoreKit 2,
/// verified and tracked by your Cashier app, gated on entitlements.
///
/// ```swift
/// Cashier.configure(apiKey: "cshr_pub_…", appUserID: user?.id)
///
/// let offerings = try await Cashier.shared.offerings()
/// if let annual = offerings.current?.annual {
///     let result = try await Cashier.shared.purchase(annual)
///     if result.customerInfo.isEntitled(to: "premium") { unlock() }
/// }
/// ```
///
/// A purchase is finished (removed from StoreKit's queue) only after Cashier
/// accepted its receipt. If the app is killed or offline in between, StoreKit
/// hands the transaction back on the next launch and the SDK posts it again.
public final class Cashier: @unchecked Sendable {
    public static let version = "1.0.0"

    private static let lock = NSLock()
    // Only read and written under `lock`.
    nonisolated(unsafe) private static var instance: Cashier?

    /// The configured instance. Call `configure` first.
    public static var shared: Cashier {
        lock.lock()
        defer { lock.unlock() }
        guard let instance else {
            preconditionFailure("NimbusCashier: call Cashier.configure(apiKey:) before Cashier.shared")
        }
        return instance
    }

    public static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return instance != nil
    }

    /// Configures the shared instance once, early in app launch.
    ///
    /// - Parameters:
    ///   - apiKey: your app's **public** key (`cshr_pub_…`). Never ship the secret key.
    ///   - appUserID: your own user id when known; nil uses the last identified
    ///     user, else a persisted anonymous id.
    ///   - baseURL: Cashier's host (override for a self-hosted Nimbus Cloud).
    @discardableResult
    public static func configure(
        apiKey: String,
        appUserID: String? = nil,
        baseURL: URL = URL(string: "https://nimbusgo.space/")!,
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        observeTransactions: Bool = true
    ) -> Cashier {
        let c = Cashier(apiKey: apiKey, appUserID: appUserID, baseURL: baseURL, session: session,
                        userDefaults: userDefaults, observeTransactions: observeTransactions)
        lock.lock()
        instance?.stop()
        instance = c
        lock.unlock()
        return c
    }

    // MARK: - State

    private let backend: Backend
    private let defaults: UserDefaults
    private let state = NSLock()
    private var _appUserID: String
    private var cached: (info: CustomerInfo, at: Date)?
    private var listeners: [UUID: AsyncStream<CustomerInfo>.Continuation] = [:]
    private var updatesTask: Task<Void, Never>?

    private static let identifiedKey = "com.nimbus.cashier.appUserID"
    /// How long a cached CustomerInfo is served without refetching.
    public var cacheLifetime: TimeInterval = 300

    init(apiKey: String, appUserID: String?, baseURL: URL, session: URLSession,
         userDefaults: UserDefaults, observeTransactions: Bool) {
        precondition(!apiKey.hasPrefix("cshr_live_"),
                     "NimbusCashier: that is your SECRET key. Use the public key (cshr_pub_…) in an app.")
        backend = Backend(apiKey: apiKey, baseURL: baseURL, session: session)
        defaults = userDefaults
        if let id = appUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            _appUserID = id
            userDefaults.set(id, forKey: Self.identifiedKey)
        } else if let saved = userDefaults.string(forKey: Self.identifiedKey), !saved.isEmpty {
            _appUserID = saved
        } else {
            _appUserID = Identity.anonymousID(userDefaults)
        }
        if observeTransactions { startObservingTransactions() }
    }

    deinit { stop() }

    /// Runs body under the state lock. Synchronous on purpose: no await can
    /// happen while the lock is held.
    private func locked<T>(_ body: () -> T) -> T {
        state.lock()
        defer { state.unlock() }
        return body()
    }

    private func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    /// The app user id purchases and reads are attributed to.
    public var appUserID: String { locked { _appUserID } }

    /// Whether the current user is an anonymous one the SDK generated.
    public var isAnonymous: Bool { Identity.isAnonymous(appUserID) }

    // MARK: - Customer info

    public enum FetchPolicy: Sendable {
        /// The cached value while it is fresh, else a fetch.
        case cachedOrFetched
        /// Always ask Cashier.
        case fetchCurrent
    }

    /// What the current user holds.
    public func customerInfo(fetchPolicy: FetchPolicy = .cachedOrFetched) async throws -> CustomerInfo {
        let user = appUserID
        if fetchPolicy == .cachedOrFetched, let c = cachedInfo(for: user) { return c }
        let info = try await backend.customerInfo(user)
        publish(info, for: user)
        return info
    }

    /// The last CustomerInfo fetched for the current user, without a request.
    public var cachedCustomerInfo: CustomerInfo? {
        locked {
            guard let c = cached, c.info.appUserID == _appUserID else { return nil }
            return c.info
        }
    }

    /// Every CustomerInfo the SDK learns about, as it happens (purchases,
    /// renewals StoreKit reports while the app runs, logins, refreshes).
    public var customerInfoStream: AsyncStream<CustomerInfo> {
        AsyncStream { continuation in
            let id = UUID()
            let current: CustomerInfo? = locked {
                listeners[id] = continuation
                return cached?.info
            }
            if let current { continuation.yield(current) }
            continuation.onTermination = { [weak self] _ in
                self?.locked { self?.listeners[id] = nil }
            }
        }
    }

    private func cachedInfo(for user: String) -> CustomerInfo? {
        locked {
            guard let c = cached, c.info.appUserID == user, Date().timeIntervalSince(c.at) < cacheLifetime else { return nil }
            return c.info
        }
    }

    private func publish(_ info: CustomerInfo, for user: String) {
        let sinks: [AsyncStream<CustomerInfo>.Continuation] = locked {
            // A response for a user who has since logged out must not land.
            guard info.appUserID == _appUserID || user == _appUserID else { return [] }
            cached = (info, Date())
            return Array(listeners.values)
        }
        sinks.forEach { $0.yield(info) }
    }

    /// Drops the cached CustomerInfo.
    public func invalidateCustomerInfoCache() { locked { cached = nil } }

    // MARK: - Offerings

    /// The console's offerings, with each package's StoreKit product loaded.
    /// Packages whose product has no App Store id, or that the App Store does
    /// not return (not yet approved, wrong bundle), are left out.
    public func offerings() async throws -> Offerings {
        try await buildOfferings(try await backend.offerings(appUserID: appUserID))
    }

    /// The offering of a paywall *draft*, from the editor's "Preview in app"
    /// token — for checking unpublished changes on a device. Use it in debug
    /// builds only; customers always get the published paywall.
    ///
    /// ```swift
    /// PaywallView(offering: try await Cashier.shared.previewOffering(token: "pvw_…"))
    /// ```
    public func previewOffering(token: String) async throws -> Offering {
        let offerings = try await buildOfferings(try await backend.paywallPreview(token: token), preview: true)
        guard let offering = offerings.current else {
            throw CashierError.server(status: 404, code: "not_found", message: "No paywall preview for that token.")
        }
        return offering
    }

    private func buildOfferings(_ wire: OfferingsResponse, preview: Bool = false) async throws -> Offerings {
        let ids = Set(wire.offerings.flatMap { $0.packages.compactMap { $0.product.appleProductID } })
        let products: [String: Product]
        do {
            products = Dictionary(uniqueKeysWithValues: try await Product.products(for: ids).map { ($0.id, $0) })
        } catch {
            throw CashierError.purchase("The App Store could not load products: \(error.localizedDescription)")
        }
        var all: [String: Offering] = [:]
        for o in wire.offerings {
            let pkgs = o.packages.compactMap { p -> Package? in
                guard let sku = p.product.appleProductID, let sp = products[sku] else { return nil }
                return Package(identifier: p.id, offeringIdentifier: o.id, cashierProduct: p.product, storeProduct: sp)
            }
            var offering = Offering(identifier: o.id, serverDescription: o.description ?? "", availablePackages: pkgs,
                                    paywall: o.paywall, appName: wire.appName ?? "")
            // A draft's views and answers are never recorded.
            offering.paywallID = o.paywall == nil || preview ? nil : o.paywallID
            if o.id == wire.currentOffering { offering.experiment = wire.experiment }
            all[o.id] = offering
        }
        var offerings = Offerings(current: wire.currentOffering.flatMap { all[$0] }, all: all)
        offerings.experiment = wire.experiment
        return offerings
    }

    // MARK: - Paywall analytics

    /// Records a paywall "view" or "close" in the background; errors are
    /// ignored. Nothing is sent for an offering without a paywall id (a
    /// preview-token draft).
    func trackPaywall(_ type: String, offering: Offering) {
        Task.detached(priority: .utility) { [self] in await self.postPaywallEvent(type, offering: offering) }
    }

    func postPaywallEvent(_ type: String, offering: Offering) async {
        guard let id = offering.paywallID else { return }
        let body = PaywallEventBody(appUserID: appUserID, paywallID: id, type: type,
                                    experimentID: offering.experiment?.id, variant: offering.experiment?.variant)
        try? await backend.paywallEvent(body)
    }

    /// Records an answer tapped on a paywall screen in the background;
    /// errors are ignored, preview drafts send nothing.
    func recordAnswer(_ answer: PaywallAnswer, offering: Offering) {
        Task.detached(priority: .utility) { [self] in await self.postAnswer(answer, offering: offering) }
    }

    func postAnswer(_ answer: PaywallAnswer, offering: Offering) async {
        guard let id = offering.paywallID else { return }
        let body = PaywallResponseBody(appUserID: appUserID, paywallID: id, screenID: answer.screenID,
                                       question: answer.question, answer: answer.answer)
        try? await backend.paywallResponse(body)
    }

    // MARK: - Purchasing

    /// The outcome of a purchase attempt.
    public struct PurchaseResult: Sendable {
        public let customerInfo: CustomerInfo?
        public let transaction: Transaction?
        /// The buyer dismissed the sheet.
        public let userCancelled: Bool
        /// Waiting on approval (Ask to Buy, SCA); StoreKit reports the outcome
        /// later and `customerInfoStream` delivers it.
        public let isPending: Bool
    }

    /// Buys a package.
    public func purchase(_ package: Package, options: Set<Product.PurchaseOption> = []) async throws -> PurchaseResult {
        try await purchase(package.storeProduct, options: options)
    }

    /// Buys a StoreKit product directly.
    public func purchase(_ product: Product, options: Set<Product.PurchaseOption> = []) async throws -> PurchaseResult {
        var opts = options
        opts.insert(.appAccountToken(Identity.appAccountToken(for: appUserID)))
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase(options: opts)
        } catch {
            throw CashierError.purchase("The App Store could not complete the purchase: \(error.localizedDescription)")
        }
        switch result {
        case let .success(verification):
            let info = try await deliver(verification)
            return PurchaseResult(customerInfo: info, transaction: verification.unsafePayloadValue, userCancelled: false, isPending: false)
        case .userCancelled:
            return PurchaseResult(customerInfo: cachedCustomerInfo, transaction: nil, userCancelled: true, isPending: false)
        case .pending:
            return PurchaseResult(customerInfo: cachedCustomerInfo, transaction: nil, userCancelled: false, isPending: true)
        @unknown default:
            throw CashierError.purchase("The App Store returned an unknown purchase result")
        }
    }

    /// Posts one transaction to Cashier and finishes it once accepted.
    @discardableResult
    private func deliver(_ verification: VerificationResult<Transaction>) async throws -> CustomerInfo {
        let tx = verification.unsafePayloadValue
        let user = appUserID
        let receipt = ReceiptPayload(token: verification.jwsRepresentation,
                                     renewalInfo: await renewalJWS(for: tx), productID: tx.productID)
        do {
            let info = try await backend.postReceipt(appUserID: user, receipt: receipt)
            await tx.finish()
            publish(info, for: user)
            return info
        } catch let error as CashierError {
            // A receipt Apple's signature does not back will never be accepted;
            // finishing it stops StoreKit from redelivering it forever.
            if case let .server(_, code, _) = error, code == "invalid_receipt" { await tx.finish() }
            throw error
        }
    }

    /// The signed renewal info for a subscription transaction, if any.
    private func renewalJWS(for tx: Transaction) async -> String? {
        guard tx.productType == .autoRenewable,
              let product = try? await Product.products(for: [tx.productID]).first,
              let statuses = try? await product.subscription?.status else { return nil }
        for status in statuses {
            if case let .verified(t) = status.transaction, t.originalID == tx.originalID {
                return status.renewalInfo.jwsRepresentation
            }
        }
        return nil
    }

    // MARK: - Restore & sync

    /// Restores purchases: asks the App Store to sync (this may prompt the
    /// user to sign in — call it from a "Restore purchases" button only), then
    /// sends every current entitlement to Cashier.
    public func restorePurchases() async throws -> CustomerInfo {
        do {
            try await AppStore.sync()
        } catch {
            throw CashierError.purchase("The App Store could not sync: \(error.localizedDescription)")
        }
        return try await syncPurchases()
    }

    /// Sends the purchases StoreKit already knows about to Cashier without any
    /// prompt — for migrating existing subscribers, or on launch.
    @discardableResult
    public func syncPurchases() async throws -> CustomerInfo {
        var receipts: [ReceiptPayload] = []
        var transactions: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            let tx = result.unsafePayloadValue
            transactions.append(tx)
            receipts.append(ReceiptPayload(token: result.jwsRepresentation, renewalInfo: await renewalJWS(for: tx), productID: tx.productID))
        }
        let user = appUserID
        guard !receipts.isEmpty else { return try await customerInfo(fetchPolicy: .fetchCurrent) }
        let info = try await backend.restore(appUserID: user, receipts: receipts)
        for tx in transactions { await tx.finish() }
        publish(info, for: user)
        return info
    }

    private func startObservingTransactions() {
        updatesTask = Task.detached(priority: .background) { [weak self] in
            // Purchases made on another device, renewals while the app runs,
            // Ask to Buy approvals, and anything left unfinished last launch.
            for await verification in Transaction.unfinished {
                guard let self else { return }
                _ = try? await self.deliver(verification)
            }
            for await verification in Transaction.updates {
                guard let self else { return }
                _ = try? await self.deliver(verification)
            }
        }
    }

    // MARK: - Identity

    /// Identifies the current user as `newAppUserID`. Anything bought while
    /// anonymous moves to that account. Switching between two signed-in users
    /// merges nothing.
    @discardableResult
    public func logIn(_ newAppUserID: String) async throws -> CustomerInfo {
        let target = newAppUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !Identity.isAnonymous(target) else {
            throw CashierError.configuration("Cashier: logIn needs your own, non-empty user id")
        }
        let current = appUserID
        if current == target { return try await customerInfo() }
        let info = try await backend.logIn(from: current, to: target)
        locked {
            _appUserID = target
            cached = nil
        }
        defaults.set(target, forKey: Self.identifiedKey)
        if Identity.isAnonymous(current) { Identity.forgetAnonymousID(defaults) }
        publish(info, for: target)
        return info
    }

    /// Signs out: the device becomes a fresh anonymous subscriber. Purchases
    /// stay with the account that made them.
    @discardableResult
    public func logOut() async throws -> CustomerInfo {
        guard !isAnonymous else {
            throw CashierError.configuration("Cashier: logOut called while already anonymous")
        }
        defaults.removeObject(forKey: Self.identifiedKey)
        Identity.forgetAnonymousID(defaults)
        let anon = Identity.anonymousID(defaults)
        locked {
            _appUserID = anon
            cached = nil
        }
        return try await customerInfo(fetchPolicy: .fetchCurrent)
    }
}

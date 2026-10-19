import Foundation
import Observation
import OSLog
import StoreKit

/// Mergeform's in-app purchases: whether the user has Pro, buying the lifetime unlock,
/// restoring purchases, and the subscription's renewal state for Settings.
///
/// The store listens to `Transaction.updates` from launch until the app quits, so a
/// purchase unlocks Pro as soon as it arrives, whether it was made in StoreKit's
/// subscription view, approved later through Ask to Buy, or restored. Every transaction
/// it receives is finished.
@Observable
final class PurchaseStore {
    /// What the user's purchases unlock. `.unknown` until they've been checked.
    private(set) var access: ProAccess = .unknown
    /// The lifetime unlock, once it has loaded from the App Store.
    private(set) var lifetimeProduct: Product?
    /// The subscription's renewal state, when the user has or recently had one.
    private(set) var renewal: SubscriptionRenewal?

    @ObservationIgnored private var recordsByProduct: [String: EntitlementRecord] = [:]
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var initialCheck: Task<Void, Never>?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.transfinite.MailMerge", category: "Purchases")

    deinit {
        updatesTask?.cancel()
        initialCheck?.cancel()
        expirationTask?.cancel()
    }

    var hasProAccess: Bool {
        if case .pro = access { return true }
        return false
    }

    /// Whether the user owns the lifetime unlock.
    var ownsLifetime: Bool {
        access == .pro(.lifetime)
    }

    /// Whether to show things only free users see, such as adverts. While purchases are
    /// still being checked this is false, so Pro users never see them flash at launch.
    var showsFreePlanContent: Bool {
        access == .free
    }

    /// Starts listening for transactions and checks the user's purchases. Calling it again
    /// does nothing.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        initialCheck = Task { [weak self] in
            await self?.refresh()
        }
    }

    /// Waits until the user's purchases have been checked at least once.
    func waitUntilChecked() async {
        start()
        await initialCheck?.value
    }

    /// Checks the user's current purchases again.
    func refresh() async {
        let startingRevision = revision
        var records: [EntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            // Unverified transactions don't grant anything.
            guard case .verified(let transaction) = result else { continue }
            records.append(EntitlementRecord(transaction))
        }
        // An update can arrive while the sequence suspends. Never overwrite it with
        // the older entitlement snapshot (including StoreKit's propagation delay).
        guard revision == startingRevision else { return }
        recordsByProduct = Dictionary(records.map { ($0.productID, $0) }, uniquingKeysWith: { _, new in new })
        updateAccess()
        renewal = await Self.currentRenewal()
    }

    /// Loads the lifetime product if it hasn't loaded yet, so a failed load at launch
    /// (such as while offline) doesn't leave the Buy button broken.
    func loadLifetimeProduct() async throws -> Product {
        if let lifetimeProduct { return lifetimeProduct }
        guard let product = try await Product.products(for: [MailMergeProductIDs.lifetimePurchase]).first else {
            throw PurchaseError.productUnavailable
        }
        lifetimeProduct = product
        return product
    }

    /// Buys the lifetime unlock. Returns false when the user cancels or the purchase
    /// waits for approval; Ask to Buy approvals arrive later through `Transaction.updates`.
    func purchaseLifetime() async throws -> Bool {
        let product = try await loadLifetimeProduct()
        return try await completePurchase(try await product.purchase())
    }

    /// Handles both StoreKit's subscription view and the lifetime purchase path. Grant
    /// access before finishing; entitlement queries may lag behind the purchase result.
    @discardableResult
    func completePurchase(_ result: Product.PurchaseResult) async throws -> Bool {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseError.unverified
            }
            await handle(.verified(transaction))
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Syncs purchases with the App Store, which may ask the user to sign in.
    func restorePurchases() async throws {
        try await AppStore.sync()
        await refresh()
    }

    // MARK: - Free Job Allowance

    /// Whether the user can create another job: Pro has no limit, and the free plan has
    /// `JobAllowance.freeJobLimit` in total. Waits for purchases to be checked, so a Pro
    /// user isn't held to the free limit just after launch.
    func canCreateJob(defaults: UserDefaults = .standard) async -> Bool {
        await waitUntilChecked()
        return JobAllowance.canCreateJob(access: access, createdJobCount: JobAllowance.createdJobCount(in: defaults))
    }

    /// Counts a new job against the free plan. Jobs created with Pro don't count.
    func recordJobCreation(defaults: UserDefaults = .standard) {
        guard access == .free else { return }
        JobAllowance.recordJobCreation(in: defaults)
    }

    // MARK: - Private

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else {
            logger.error("Ignored an unverified transaction for \(update.unsafePayloadValue.productID)")
            return
        }
        revision += 1
        recordsByProduct[transaction.productID] = EntitlementRecord(transaction)
        updateAccess()
        await transaction.finish()
        renewal = await Self.currentRenewal()
    }

    private func updateAccess() {
        let records = Array(recordsByProduct.values)
        access = ProAccess.granted(by: records)
        scheduleRefresh(atExpirationOf: records)
    }

    /// Ends the listeners when their owner goes away (and isolates StoreKit tests).
    func stop() {
        updatesTask?.cancel()
        initialCheck?.cancel()
        expirationTask?.cancel()
        updatesTask = nil
        initialCheck = nil
        expirationTask = nil
    }

    /// `Transaction.updates` doesn't report a subscription simply running out, so check
    /// again when the soonest one expires.
    private func scheduleRefresh(atExpirationOf records: [EntitlementRecord]) {
        expirationTask?.cancel()
        guard let expiration = records.compactMap(\.expirationDate).filter({ $0 > .now }).min() else { return }
        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiration.timeIntervalSinceNow + 1))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private static func currentRenewal() async -> SubscriptionRenewal? {
        guard let statuses = try? await Product.SubscriptionInfo.status(for: MailMergeProductIDs.subscriptionGroupID) else {
            return nil
        }
        return statuses.compactMap(SubscriptionRenewal.init).first
    }
}

// MARK: - Supporting Types

/// What the user's purchases unlock.
nonisolated enum ProAccess: Equatable, Sendable {
    /// Purchases haven't been checked yet.
    case unknown
    case free
    case pro(Source)

    enum Source: Equatable, Sendable {
        case subscription
        case lifetime
    }

    /// The access a set of current entitlements grants. `Transaction.currentEntitlements`
    /// already leaves out expired subscriptions and those in billing retry, which matches
    /// Mergeform not offering a billing grace period; revoked (refunded) purchases and
    /// anything past its expiration date are excluded here too.
    static func granted(by entitlements: [EntitlementRecord], now: Date = .now) -> ProAccess {
        let active = entitlements.filter { entitlement in
            !entitlement.isRevoked && (entitlement.expirationDate.map { $0 > now } ?? true)
        }
        if active.contains(where: { $0.productID == MailMergeProductIDs.lifetimePurchase }) {
            return .pro(.lifetime)
        }
        if active.contains(where: { MailMergeProductIDs.subscriptions.contains($0.productID) }) {
            return .pro(.subscription)
        }
        return .free
    }
}

/// The parts of a transaction that decide access, so the rules can be tested without
/// StoreKit.
nonisolated struct EntitlementRecord: Equatable, Sendable {
    var productID: String
    var isRevoked: Bool
    var expirationDate: Date?

    init(productID: String, isRevoked: Bool = false, expirationDate: Date? = nil) {
        self.productID = productID
        self.isRevoked = isRevoked
        self.expirationDate = expirationDate
    }

    init(_ transaction: Transaction) {
        self.init(
            productID: transaction.productID,
            isRevoked: transaction.revocationDate != nil || transaction.isUpgraded,
            expirationDate: transaction.expirationDate
        )
    }
}

/// The subscription's renewal state, as Settings describes it.
nonisolated struct SubscriptionRenewal: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case renews(Date)
        case expires(Date)
        /// The App Store couldn't charge the user and is retrying; Pro is paused.
        case billingIssue
    }

    var state: State

    init(state: State) {
        self.state = state
    }

    init?(_ status: Product.SubscriptionInfo.Status) {
        guard case .verified(let transaction) = status.transaction else { return nil }
        let willRenew: Bool
        if case .verified(let renewalInfo) = status.renewalInfo {
            willRenew = renewalInfo.willAutoRenew
        } else {
            willRenew = false
        }
        switch status.state {
        case .subscribed:
            guard let expiration = transaction.expirationDate else { return nil }
            state = willRenew ? .renews(expiration) : .expires(expiration)
        case .inBillingRetryPeriod, .inGracePeriod:
            state = .billingIssue
        default:
            return nil
        }
    }

    var description: String {
        switch state {
        case .renews(let date): "Renews \(date.formatted(date: .abbreviated, time: .omitted))"
        case .expires(let date): "Ends \(date.formatted(date: .abbreviated, time: .omitted))"
        case .billingIssue: "Payment issue: update your payment method in the App Store"
        }
    }
}

nonisolated enum PurchaseError: LocalizedError {
    case productUnavailable
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "Lifetime Access isn’t available right now. Check your internet connection and try again."
        case .unverified: "The App Store couldn’t verify this purchase. Try again, or restore purchases."
        }
    }
}

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Mergeform

/// Purchases against the app's local StoreKit configuration. They share StoreKit's test
/// environment, so they run one at a time.
@MainActor
@Suite("Purchase store", .serialized)
struct PurchaseStoreTests {
    private func makeSession() throws -> SKTestSession {
        let url = try #require(Bundle.main.url(forResource: "Mergeform", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    @Test("A subscription from StoreKit's paywall completion unlocks Pro immediately")
    func subscriptionCompletionUnlocksPro() async throws {
        let session = try makeSession()
        let store = PurchaseStore()
        defer { store.stop(); session.clearTransactions() }
        await store.waitUntilChecked()
        #expect(store.access == .free)
        #expect(store.showsFreePlanContent)

        // SKTestSession returns the transaction to its caller, like a StoreKit view's
        // completion. It doesn't simulate that view's automatic updates broadcast.
        let transaction = try await session.buyProduct(identifier: MailMergeProductIDs.monthlySubscription)
        #expect(try await store.completePurchase(.success(.verified(transaction))))
        #expect(store.access == .pro(.subscription))
        #expect(store.showsFreePlanContent == false)
    }

    @Test("Buying the lifetime unlock unlocks Pro")
    func lifetimePurchaseUnlocksPro() async throws {
        let session = try makeSession()
        let store = PurchaseStore()
        defer { store.stop(); session.clearTransactions() }
        await store.waitUntilChecked()

        let purchased = try await store.purchaseLifetime()

        #expect(purchased)
        #expect(store.access == .pro(.lifetime))
        #expect(store.ownsLifetime)
        session.clearTransactions()
    }

    @Test("Jobs created with Pro don't count against the free plan")
    func proJobsDontCount() async throws {
        let session = try makeSession()
        let suiteName = "MergeformTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(JobAllowance.freeJobLimit, forKey: JobAllowance.createdJobCountKey)
        let store = PurchaseStore()
        defer { store.stop(); session.clearTransactions() }

        #expect(await store.canCreateJob(defaults: defaults) == false)

        let transaction = try await session.buyProduct(identifier: MailMergeProductIDs.lifetimePurchase)
        _ = try await store.completePurchase(.success(.verified(transaction)))
        #expect(store.hasProAccess)
        #expect(await store.canCreateJob(defaults: defaults))
        store.recordJobCreation(defaults: defaults)
        #expect(JobAllowance.createdJobCount(in: defaults) == JobAllowance.freeJobLimit)
        session.clearTransactions()
    }

    @Test("Cancelled and pending purchases keep the upgrade screen available")
    func cancelledAndPending() async throws {
        let session = try makeSession()
        let store = PurchaseStore()
        defer { store.stop(); session.clearTransactions() }
        await store.waitUntilChecked()
        #expect(try await store.completePurchase(.userCancelled) == false)
        #expect(try await store.completePurchase(.pending) == false)
        #expect(store.access == .free)
    }
}

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

    /// Polls `condition` until it's true, for state that updates asynchronously.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("A subscription bought outside purchase(), such as in StoreKit's paywall, unlocks Pro")
    func subscriptionFromUpdatesUnlocksPro() async throws {
        let session = try makeSession()
        let store = PurchaseStore()
        await store.waitUntilChecked()
        #expect(store.access == .free)
        #expect(store.showsFreePlanContent)

        // buyProduct simulates a purchase that reaches the app through Transaction.updates,
        // the path StoreKit's subscription view uses by default.
        try await session.buyProduct(identifier: MailMergeProductIDs.monthlySubscription)

        #expect(try await eventually { store.access == .pro(.subscription) })
        #expect(store.showsFreePlanContent == false)
        let unfinished = await Self.unfinishedTransactionCount()
        #expect(unfinished == 0)
        session.clearTransactions()
    }

    @Test("Buying the lifetime unlock unlocks Pro")
    func lifetimePurchaseUnlocksPro() async throws {
        let session = try makeSession()
        let store = PurchaseStore()
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

        #expect(await store.canCreateJob(defaults: defaults) == false)

        try await session.buyProduct(identifier: MailMergeProductIDs.lifetimePurchase)
        #expect(try await eventually { store.hasProAccess })
        #expect(await store.canCreateJob(defaults: defaults))
        store.recordJobCreation(defaults: defaults)
        #expect(JobAllowance.createdJobCount(in: defaults) == JobAllowance.freeJobLimit)
        session.clearTransactions()
    }

    private static func unfinishedTransactionCount() async -> Int {
        var count = 0
        for await _ in Transaction.unfinished {
            count += 1
        }
        return count
    }
}

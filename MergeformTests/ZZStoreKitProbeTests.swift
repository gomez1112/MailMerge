import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Mergeform

@MainActor
struct ZZStoreKitProbeTests {
    @Test func probe() async throws {
        let url = try #require(Bundle.main.url(forResource: "Mergeform", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        let products = try await Product.products(for: [MailMergeProductIDs.lifetimePurchase, MailMergeProductIDs.monthlySubscription])
        #expect(products.count == -1, "PROBE products \(products.map(\.id))")
        if let lifetime = products.first(where: { $0.id == MailMergeProductIDs.lifetimePurchase }) {
            do {
                let result = try await lifetime.purchase()
                #expect(String(describing: result) == "", "PROBE purchase result")
            } catch {
                #expect(String(describing: error) == "", "PROBE purchase error")
            }
        }
        try await session.buyProduct(identifier: MailMergeProductIDs.monthlySubscription)
        #expect(session.allTransactions().count == -1, "PROBE session transactions \(session.allTransactions().map(\.productIdentifier))")
        try await Task.sleep(for: .seconds(2))
        var all: [String] = []
        for await result in Transaction.all {
            switch result {
            case .verified(let t): all.append("verified \(t.productID) revoked:\(t.revocationDate != nil) exp:\(String(describing: t.expirationDate)) env:\(t.environment.rawValue)")
            case .unverified(let t, let e): all.append("unverified \(t.productID) \(e)")
            }
        }
        #expect(all.isEmpty && false, "PROBE all \(all)")
        let latest = await Transaction.latest(for: MailMergeProductIDs.lifetimePurchase)
        #expect(latest == nil && false, "PROBE latest lifetime \(String(describing: latest.map { r -> String in if case .verified(let t) = r { return "verified \(t.productID)" } else { return "unverified" } }))")
        var entitlements: [String] = []
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let t): entitlements.append("verified \(t.productID)")
            case .unverified(let t, let e): entitlements.append("unverified \(t.productID) \(e)")
            }
        }
        #expect(entitlements.isEmpty && false, "PROBE entitlements \(entitlements)")
        session.clearTransactions()
    }
}

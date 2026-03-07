import Testing
@testable import Mergeform

@MainActor
@Suite("Mail merge tier")
struct MailMergeTierTests {
    @Test("Default tier is free")
    func defaultTierIsFree() {
        #expect(MailMergeTier.defaultTier == .free)
    }

    @Test("Level of service maps to tier", arguments: zip(
        [0, 1],
        [MailMergeTier.free, .pro]
    ))
    func mapsLevelOfService(_ level: Int, expected: MailMergeTier) {
        #expect(MailMergeTier(levelOfService: level) == expected)
    }

    @Test("Higher levels of service still map to pro")
    func higherLevelOfServiceMapsToPro() {
        #expect(MailMergeTier(levelOfService: 2) == .pro)
    }

    @Test("Negative level of service returns nil")
    func negativeLevelOfServiceIsNil() {
        #expect(MailMergeTier(levelOfService: -1) == nil)
    }

    @Test("Product ID mapping returns pro")
    func productIDMapping() {
        #expect(MailMergeTier(productID: MailMergeProductIDs.monthlySubscription) == .pro)
        #expect(MailMergeTier(productID: MailMergeProductIDs.annualSubscription) == .pro)
        #expect(MailMergeTier(productID: MailMergeProductIDs.lifetimePurchase) == .pro)
    }

    @Test("Unknown product ID returns nil")
    func unknownProductIDIsNil() {
        #expect(MailMergeTier(productID: "com.mergeform.unknown") == nil)
    }

    @Test("Display names are stable", arguments: zip(
        [MailMergeTier.free, .pro],
        ["Free", "Pro"]
    ))
    func displayName(_ tier: MailMergeTier, expected: String) {
        #expect(tier.displayName == expected)
    }

    @Test("Comparable orders tiers")
    func comparableOrders() {
        #expect(MailMergeTier.free < .pro)
        #expect((MailMergeTier.pro < .free) == false)
    }
}

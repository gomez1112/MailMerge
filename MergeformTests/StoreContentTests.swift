import Testing
import FlexStore
@testable import Mergeform

@Suite("Store content")
struct StoreContentTests {
    @Test("Mail merge pro features are stable")
    func mailMergeProFeatures() {
        let features = FlexPaywallFeature.mailMergeProFeatures

        #expect(features.count == 5)
        #expect(features.map(\.title) == [
            "Unlimited Records",
            "Batch PDF Output",
            "Smart Field Matching",
            "Field Transformations",
            "Custom Output Patterns"
        ])
        #expect(features.map(\.systemImage) == [
            "infinity",
            "doc.on.doc.fill",
            "wand.and.stars",
            "arrow.left.arrow.right",
            "folder.badge.gearshape"
        ])
    }

    @Test("Mail merge pro dark configuration is complete")
    func mailMergeProDarkConfiguration() throws {
        let config = SubscriptionShopConfiguration.mailMergeProDark

        #expect(config.title == "Mergeform Pro")
        #expect(config.subtitle == "Automate documents without limits")
        #expect(config.heroSystemImage == "doc.on.doc.fill")
        let features = try #require(config.features)
        #expect(features.count == 5)
        #expect(config.tiers.count == 2)
    }

    @Test("Mail merge pro light configuration is complete")
    func mailMergeProLightConfiguration() throws {
        let config = SubscriptionShopConfiguration.mailMergeProLight

        #expect(config.title == "Mergeform")
        #expect(config.subtitle == "Automate documents without limits")
        #expect(config.heroSystemImage == "doc.on.doc.fill")
        let features = try #require(config.features)
        #expect(features.count == 5)
        #expect(config.tiers.count == 2)
    }

    @Test("Mail merge pro resolves to dark configuration")
    func mailMergeProResolvesToDark() {
        let config = SubscriptionShopConfiguration.mailMergePro
        let dark = SubscriptionShopConfiguration.mailMergeProDark

        #expect(config.title == dark.title)
        #expect(config.subtitle == dark.subtitle)
        #expect(config.heroSystemImage == dark.heroSystemImage)
    }
}

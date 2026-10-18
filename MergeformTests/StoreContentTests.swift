import Testing
@testable import Mergeform

@MainActor
@Suite("Store content")
struct StoreContentTests {
    @Test("The Pro offer's features are complete")
    func offerFeaturesAreComplete() {
        let features = MergeformProOffer.features
        #expect(features.count == 3)
        #expect(features.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(features.map(\.id)).count == features.count)
    }

    @Test("The offer states the free plan's job allowance")
    func offerStatesTheAllowance() {
        #expect(MergeformProOffer.subheadline.contains("\(JobAllowance.freeJobLimit) jobs"))
    }
}

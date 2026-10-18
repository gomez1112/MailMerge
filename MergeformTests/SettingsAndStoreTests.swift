import Foundation
import SwiftData
import Testing
@testable import Mergeform

@MainActor
@Suite("Pro access")
struct ProAccessTests {
    @Test("The lifetime purchase unlocks Pro without a subscription")
    func lifetimeUnlocksPro() {
        #expect(MailMergeTier.hasProAccess(subscriptionTier: .free, purchasedProductIDs: [MailMergeProductIDs.lifetimePurchase]))
        #expect(MailMergeTier.hasProAccess(subscriptionTier: .pro, purchasedProductIDs: []))
        #expect(MailMergeTier.hasProAccess(subscriptionTier: .free, purchasedProductIDs: []) == false)
    }

    @Test("The paywall offers what Pro actually unlocks")
    func offerIsTruthful() {
        let titles = MergeformProOffer.features.map(\.title)
        #expect(titles.first == "Unlimited Jobs")
        // These work on the free plan, so selling them as Pro features is misleading.
        for freeFeature in ["Unlimited Records", "Batch PDF Output", "Smart Field Matching", "Field Transformations", "Custom Output Patterns"] {
            #expect(!titles.contains(freeFeature))
        }
    }

    @Test("The job limit message explains that deleting jobs doesn't free a slot")
    func limitMessageExplainsLifetimeCount() {
        #expect(JobAllowance.limitReachedMessage.contains("deleting"))
    }
}

@MainActor
@Suite("Settings")
struct SettingsTests {
    @Test("New jobs use the default file name pattern from Settings")
    func defaultPatternIsUsed() throws {
        let suiteName = "MergeformTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Invoice_{Row}", forKey: "defaultOutputPattern")

        let job = MailMergeJob.makeNew(name: "Invoices", category: nil, defaults: defaults)
        #expect(job.outputFileNamePattern == "Invoice_{Row}")

        defaults.set("   ", forKey: "defaultOutputPattern")
        #expect(MailMergeJob.makeNew(name: "Blank", category: nil, defaults: defaults).outputFileNamePattern == "Letter_{FirstName}_{LastName}")
    }

    @Test("Turning off relative dates shows the date itself")
    func absoluteDates() {
        let job = MailMergeJob(name: "Letters")
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        job.modifiedAt = date
        let text = job.modifiedDescription(relative: false, relativeTo: date.addingTimeInterval(3 * 86_400))
        #expect(text == "Modified \(date.formatted(date: .abbreviated, time: .shortened))")
    }

    @Test("With auto-match on, newly scanned fields are matched to columns")
    func autoMatchOnScan() throws {
        let schema = Schema(versionedSchema: MailMergeSchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let job = MailMergeJob(name: "Letters")
        container.mainContext.insert(job)
        job.availableColumns = ["Email", "Zip Code"]

        job.syncFieldMappings(with: ["Email"], in: container.mainContext, autoMatch: true)
        let email = try #require(job.fieldMappings.first)
        #expect(email.columnName == "Email")
        #expect(email.isAutoMatched)

        job.fieldMappings.append(FieldMapping(placeholderText: "Zip", job: job))
        job.autoMatchUnmappedFields()
        #expect(job.fieldMappings.first { $0.placeholderText == "Zip" }?.columnName == "Zip Code")
    }
}

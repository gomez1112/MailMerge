import Foundation

/// What the paywall says Mergeform Pro includes.
///
/// Every feature works on the free plan; what Pro unlocks is the number of jobs. The
/// offer says exactly that.
enum MergeformProOffer {
    struct Feature: Identifiable {
        var systemImage: String
        var title: String
        var detail: String

        var id: String { title }
    }

    static let headline = "Mergeform Pro"
    static let subheadline = "Create as many jobs as you need. The free plan includes \(JobAllowance.freeJobLimit) jobs in total."

    static let features: [Feature] = [
        Feature(
            systemImage: "infinity",
            title: "Unlimited Jobs",
            detail: "Set up a job for every client, campaign, and letter. Deleting jobs on the free plan doesn't free up a slot."
        ),
        Feature(
            systemImage: "tray.full.fill",
            title: "Keep Every Setup Ready",
            detail: "Each job keeps its template, data, field mappings, and output settings, ready to run again."
        ),
        Feature(
            systemImage: "heart.fill",
            title: "Support Mergeform",
            detail: "Your purchase funds new features and updates."
        )
    ]
}

import Foundation

/// The free plan's job allowance: a number of jobs in total. Deleting a job doesn't give
/// one back.
nonisolated enum JobAllowance {
    static let freeJobLimit = 3

    static let limitReachedMessage = "The free plan includes \(freeJobLimit) jobs in total, and deleting a job doesn't free up a slot. Upgrade to Pro or Lifetime for unlimited jobs."

    /// Where the number of jobs created on the free plan is kept.
    static let createdJobCountKey = "jobCreationCount"

    static func createdJobCount(in defaults: UserDefaults) -> Int {
        defaults.integer(forKey: createdJobCountKey)
    }

    static func recordJobCreation(in defaults: UserDefaults) {
        defaults.set(createdJobCount(in: defaults) + 1, forKey: createdJobCountKey)
    }

    /// Pro has no limit. Until purchases have been checked, nothing is allowed, so callers
    /// wait for the check first.
    static func canCreateJob(access: ProAccess, createdJobCount: Int) -> Bool {
        switch access {
        case .pro: true
        case .free: createdJobCount < freeJobLimit
        case .unknown: false
        }
    }
}

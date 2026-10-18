import Foundation

/// Decisions about which job the Jobs list shows and which job menu commands act on.
enum JobNavigation {
    /// The navigation path to show when the Jobs list appears: a job just opened from
    /// the Templates tab, or else the path saved for this window without jobs that have
    /// since been deleted.
    static func initialPath(pendingJobID: UUID?, savedPath: [UUID], existingJobIDs: Set<UUID>) -> [UUID] {
        if let pendingJobID {
            return [pendingJobID]
        }
        return savedPath.filter { existingJobIDs.contains($0) }
    }

    /// The job the Job menu acts on: the one that's open. Back on the list, where no job
    /// is highlighted, there's nothing to act on.
    static func focusedJobID(path: [UUID]) -> UUID? {
        path.last
    }
}

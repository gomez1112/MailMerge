import Foundation
import Observation

/// Carries Job menu commands from the menu bar to the window that owns the focused job.
///
/// The menu publishes a request here rather than calling a closure: closures stored in
/// focused values can't be compared, so they would invalidate the menu on every update.
/// The owning view observes `pendingCommand`, performs it, and clears it.
@Observable
final class JobCommandRouter {
    /// The most recent command that hasn't been handled yet.
    var pendingCommand: JobCommand?
}

/// A Job menu request for a specific job.
struct JobCommand: Equatable {
    enum Kind {
        case rename
        case delete
    }

    var kind: Kind
    var jobID: UUID
}

/// The job the Job menu acts on, published as a focused scene value.
///
/// Holds only comparable data (an ID and a stable router reference), so SwiftUI can tell
/// when it actually changes.
struct FocusedJobCommands {
    var jobID: UUID
    var router: JobCommandRouter

    func rename() {
        router.pendingCommand = JobCommand(kind: .rename, jobID: jobID)
    }

    func delete() {
        router.pendingCommand = JobCommand(kind: .delete, jobID: jobID)
    }
}

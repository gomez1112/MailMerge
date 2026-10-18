import Foundation
import Observation

/// Carries menu commands that apply to a whole window, such as File > New Job, to the
/// focused window only.
@Observable
final class WindowCommandRouter {
    /// Set when New Job is chosen; the Jobs list starts a new job and clears it.
    var isNewJobRequested = false
}

/// The focused window's commands, published as a focused scene value.
struct FocusedWindowCommands {
    var router: WindowCommandRouter

    func newJob() {
        router.isNewJobRequested = true
    }
}

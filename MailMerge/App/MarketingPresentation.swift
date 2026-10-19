#if DEBUG
import Observation
import SwiftUI

/// Drives the real interface for repeatable marketing captures. Supplied only by the
/// opt-in test harness; ordinary Debug launches and all Release builds use normal state.
@Observable
final class MarketingPresentation {
    enum Screen: String {
        case jobs = "01-jobs"
        case mapping = "02-mapping"
        case data = "03-data"
        case run = "04-run"
        case templates = "05-templates"
        case requests = "06-requests"

        var step: MergeStep? {
            switch self {
            case .mapping: .fieldMapping
            case .data: .dataSource
            case .run: .preview
            default: nil
            }
        }
    }

    var screen: Screen = .jobs
    var jobID: UUID

    init(jobID: UUID) { self.jobID = jobID }
}

extension EnvironmentValues {
    @Entry var marketingPresentation: MarketingPresentation? = nil
}
#endif

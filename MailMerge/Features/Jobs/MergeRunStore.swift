import Foundation
import Observation

/// Owns the merges in progress, one per job, so a merge keeps its progress, Cancel
/// button, and result when the Preview step is left and reopened.
@Observable
final class MergeRunStore {
    private var runs: [UUID: MergeRun] = [:]

    /// The latest merge for a job: running, or finished with its outcome.
    func run(for jobID: UUID) -> MergeRun? {
        runs[jobID]
    }

    /// Starts a merge unless one is already running or still stopping for the job, in
    /// which case it returns nil. `onCompletion` runs only when the merge succeeds.
    @discardableResult
    func start(
        job: MailMergeJob,
        singleDocument: Bool,
        engine: MergeEngine,
        onCompletion: @escaping (MergeResult) -> Void = { _ in }
    ) -> MergeRun? {
        if let existing = runs[job.id], existing.isActive {
            return nil
        }
        let run = MergeRun(jobID: job.id)
        runs[job.id] = run
        run.task = Task {
            do {
                let result = try await engine.performMerge(job: job, singleDocument: singleDocument) { progress in
                    run.progress = progress
                }
                run.outcome = .completed(result)
                onCompletion(result)
            } catch is CancellationError {
                run.outcome = .cancelled
            } catch {
                run.outcome = .failed(error.localizedDescription)
            }
        }
        return run
    }

    /// Stops the job's merge, if one is running.
    func cancel(jobID: UUID) {
        runs[jobID]?.cancel()
    }
}

/// One merge of one job.
@Observable
final class MergeRun {
    enum Outcome {
        case completed(MergeResult)
        case failed(String)
        case cancelled
    }

    let jobID: UUID
    let startedAt = Date()
    fileprivate(set) var progress = MergeProgress(completed: 0, total: 0)
    fileprivate(set) var outcome: Outcome?
    private(set) var isCancelling = false
    fileprivate var task: Task<Void, Never>?

    init(jobID: UUID) {
        self.jobID = jobID
    }

    /// Whether the merge is still working, including while it stops after Cancel.
    var isActive: Bool { outcome == nil }

    /// Records merged per second so far.
    var recordsPerSecond: Double? {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard progress.completed > 0, elapsed > 0 else { return nil }
        return Double(progress.completed) / elapsed
    }

    /// Seconds until the merge finishes at the current rate.
    var estimatedTimeRemaining: TimeInterval? {
        guard let recordsPerSecond, recordsPerSecond > 0 else { return nil }
        return Double(progress.total - progress.completed) / recordsPerSecond
    }

    func cancel() {
        guard isActive, !isCancelling else { return }
        isCancelling = true
        task?.cancel()
    }

    /// Waits until the merge has finished or stopped.
    func waitUntilFinished() async {
        await task?.value
    }
}

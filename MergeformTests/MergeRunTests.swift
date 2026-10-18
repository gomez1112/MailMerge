import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Mergeform

@MainActor
@Suite("Running a merge", .serialized)
struct MergeRunTests {
    @Test("A completed merge writes one file per record and marks the job completed")
    func completedMerge() async throws {
        let fixture = try MergeFixture(recordCount: 3)
        defer { fixture.remove() }

        let result = try await MergeFixture.makeEngine().performMerge(job: fixture.job, singleDocument: false, progress: { _ in })

        #expect(result.recordCount == 3)
        #expect(fixture.outputFileNames == ["Letter_Person 1.pdf", "Letter_Person 2.pdf", "Letter_Person 3.pdf"])
        #expect(fixture.job.status == .completed)
        #expect(fixture.job.lastRunRecordCount == 3)
    }

    @Test("Cancelling a merge stops it and doesn't mark the job failed")
    func cancellingStopsTheMerge() async throws {
        let fixture = try MergeFixture(recordCount: 40)
        defer { fixture.remove() }
        let engine = MergeFixture.makeEngine()

        let task = Task { try await engine.performMerge(job: fixture.job, singleDocument: false, progress: { _ in }) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.job.status == .configured)
        #expect(fixture.outputFileNames.count < 40)
    }

    @Test("Cancelling a combined merge writes no PDF")
    func cancellingCombinedMerge() async throws {
        let fixture = try MergeFixture(recordCount: 40)
        defer { fixture.remove() }
        let engine = MergeFixture.makeEngine()

        let task = Task { try await engine.performMerge(job: fixture.job, singleDocument: true, progress: { _ in }) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.outputFileNames.isEmpty)
        #expect(fixture.job.status == .configured)
    }

    @Test("A combined PDF is attached to email from a copy the app can always read")
    func combinedAttachmentIsACopy() async throws {
        let fixture = try MergeFixture(recordCount: 2)
        defer { fixture.remove() }

        let result = try await MergeFixture.makeEngine().performMerge(job: fixture.job, singleDocument: true, progress: { _ in })

        let attachment = try #require(result.attachmentURL)
        #expect(attachment.deletingLastPathComponent().standardizedFileURL != fixture.outputFolder.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: attachment.path))
        #expect(fixture.outputFileNames == ["Merged_Fixture Job.pdf"])
    }

    @Test("Previews use the template's paper size")
    func previewUsesTemplatePaperSize() async throws {
        let fixture = try MergeFixture(recordCount: 1, pageSizeTwips: CGSize(width: 11_906, height: 16_838))
        defer { fixture.remove() }

        let preview = try await MergeFixture.makeEngine().generatePreview(job: fixture.job, recordIndex: 0)
        let page = try #require(PDFDocument(data: preview.data)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(abs(bounds.width - 595.3) < 1)
        #expect(abs(bounds.height - 841.9) < 1)
    }
}

@MainActor
@Suite("Merge run store", .serialized)
struct MergeRunStoreTests {
    @Test("A second merge can't start while the first is still running or stopping")
    func oneMergePerJob() async throws {
        let fixture = try MergeFixture(recordCount: 30)
        defer { fixture.remove() }
        let store = MergeRunStore()
        let engine = MergeFixture.makeEngine()

        let first = try #require(store.start(job: fixture.job, singleDocument: false, engine: engine))
        #expect(store.start(job: fixture.job, singleDocument: true, engine: engine) == nil)

        first.cancel()
        // Still stopping: a restart must wait until the first merge has ended.
        #expect(store.start(job: fixture.job, singleDocument: true, engine: engine) == nil)
        await first.waitUntilFinished()

        guard case .cancelled = try #require(first.outcome) else {
            Issue.record("Expected the merge to be cancelled")
            return
        }
        #expect(fixture.job.status == .configured)
        let second = try #require(store.start(job: fixture.job, singleDocument: false, engine: engine))
        await second.waitUntilFinished()
        guard case .completed(let result) = try #require(second.outcome) else {
            Issue.record("Expected the second merge to complete")
            return
        }
        #expect(result.recordCount == 30)
    }

    @Test("A finished merge's result stays available for the job")
    func resultOutlivesTheView() async throws {
        let fixture = try MergeFixture(recordCount: 2)
        defer { fixture.remove() }
        let store = MergeRunStore()

        let run = try #require(store.start(job: fixture.job, singleDocument: false, engine: MergeFixture.makeEngine()))
        await run.waitUntilFinished()

        #expect(store.run(for: fixture.job.id) === run)
        #expect(run.isActive == false)
        #expect(run.progress == MergeProgress(completed: 2, total: 2))
    }

    @Test("Deleting a job during its merge stops the merge safely")
    func deletingARunningJob() async throws {
        let fixture = try MergeFixture(recordCount: 30)
        defer { fixture.remove() }
        let store = MergeRunStore()

        let run = try #require(store.start(job: fixture.job, singleDocument: false, engine: MergeFixture.makeEngine()))
        store.cancel(jobID: fixture.job.id)
        fixture.container.mainContext.delete(fixture.job)
        await run.waitUntilFinished()

        guard case .cancelled = try #require(run.outcome) else {
            Issue.record("Expected the merge to be cancelled")
            return
        }
    }
}

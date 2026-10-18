import Foundation
import Testing
@testable import Mergeform

@MainActor
@Suite("Job menu commands")
struct JobCommandRouterTests {
    @Test("Rename and delete post a request for the focused job")
    func postsRequests() {
        let router = JobCommandRouter()
        let jobID = UUID()
        let commands = FocusedJobCommands(jobID: jobID, router: router)

        commands.rename()
        #expect(router.pendingCommand == JobCommand(kind: .rename, jobID: jobID))

        commands.delete()
        #expect(router.pendingCommand == JobCommand(kind: .delete, jobID: jobID))
    }

    @Test("A new router starts with no pending command")
    func startsEmpty() {
        #expect(JobCommandRouter().pendingCommand == nil)
    }
}

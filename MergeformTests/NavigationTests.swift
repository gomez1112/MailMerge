import AppKit
import Foundation
import Testing
@testable import Mergeform

@MainActor
@Suite("Job navigation")
struct JobNavigationTests {
    @Test("A job opened from the Templates tab is shown instead of the saved path")
    func pendingJobWins() {
        let opened = UUID()
        let previous = UUID()
        let path = JobNavigation.initialPath(pendingJobID: opened, savedPath: [previous], existingJobIDs: [opened, previous])
        #expect(path == [opened])
    }

    @Test("A saved path to a deleted job isn't restored")
    func deletedJobsAreDropped() {
        let deleted = UUID()
        #expect(JobNavigation.initialPath(pendingJobID: nil, savedPath: [deleted], existingJobIDs: []).isEmpty)
    }

    @Test("After going back to the list, the Job menu has no job to act on")
    func noJobAfterGoingBack() {
        #expect(JobNavigation.focusedJobID(path: []) == nil)
        let open = UUID()
        #expect(JobNavigation.focusedJobID(path: [open]) == open)
    }
}

@MainActor
@Suite("Delete Job shortcut")
struct DeleteShortcutTests {
    @Test("Command-Delete in a text field deletes text instead of the job")
    func textFieldGetsTheShortcut() {
        let textView = NSTextView()
        textView.string = "Letter_{FirstName}"
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

        #expect(TextEditingShortcut.forwardsDeleteToText(responder: textView, isKeyEquivalent: true))
        #expect(textView.string.isEmpty)
    }

    @Test("Choosing Delete Job from the menu still deletes the job")
    func menuClickStillDeletes() {
        let textView = NSTextView()
        textView.string = "Pattern"
        #expect(TextEditingShortcut.forwardsDeleteToText(responder: textView, isKeyEquivalent: false) == false)
        #expect(textView.string == "Pattern")
    }

    @Test("Outside a text field the shortcut deletes the job")
    func otherRespondersDeleteTheJob() {
        #expect(TextEditingShortcut.forwardsDeleteToText(responder: NSView(), isKeyEquivalent: true) == false)
        let readOnly = NSTextView()
        readOnly.isEditable = false
        #expect(TextEditingShortcut.forwardsDeleteToText(responder: readOnly, isKeyEquivalent: true) == false)
    }
}

@MainActor
@Suite("Template library")
struct TemplateLibraryTests {
    @Test("Jobs using the same file share one template card")
    func sameFileIsOneItem() {
        let now = Date()
        let sources = [
            TemplateLibraryItem.Source(bookmarkData: Data([1]), fileName: "Invoice.docx", lastUsed: now),
            TemplateLibraryItem.Source(bookmarkData: Data([2]), fileName: "Invoice.docx", lastUsed: now.addingTimeInterval(-60)),
            TemplateLibraryItem.Source(bookmarkData: Data([3]), fileName: "Letter.docx", lastUsed: now.addingTimeInterval(-120))
        ]
        let identities: [Data: String] = [Data([1]): "/Docs/Invoice.docx", Data([2]): "/Docs/Invoice.docx", Data([3]): "/Docs/Letter.docx"]

        let items = TemplateLibraryItem.items(from: sources, fileIdentity: { identities[$0] })

        #expect(items.map(\.fileName) == ["Invoice.docx", "Letter.docx"])
        #expect(items.first?.usageCount == 2)
    }
}

@MainActor
@Suite("Window commands")
struct WindowCommandTests {
    @Test("New Job is requested only in the window it was sent to")
    func newJobTargetsOneWindow() {
        let focused = WindowCommandRouter()
        let other = WindowCommandRouter()
        FocusedWindowCommands(router: focused).newJob()
        #expect(focused.isNewJobRequested)
        #expect(other.isNewJobRequested == false)
    }
}

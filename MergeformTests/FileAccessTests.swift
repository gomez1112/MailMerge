import Foundation
import Testing
@testable import Mergeform

/// A file in a fresh temporary directory, deleted with the directory.
private struct TemporaryFile {
    let directory: URL
    let url: URL

    init(named name: String, contents: String = "data") throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: name)
        try Data(contents.utf8).write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
@Suite("Saving file references")
struct FileAccessTests {
    @Test("A dropped file without a security scope can still be saved")
    func bookmarkForPlainURL() throws {
        let file = try TemporaryFile(named: "Letter.docx")
        defer { file.remove() }

        // Like a URL read from a drag, this one carries no security scope of its own.
        let plainURL = URL(fileURLWithPath: file.url.path)
        let bookmark = try SecurityScopedAccess.makeBookmark(for: plainURL)
        let resolved = try SecurityScopedAccess.startAccessing(bookmarkData: bookmark)
        defer { SecurityScopedAccess.stopAccessing(resolved) }
        #expect(resolved.lastPathComponent == "Letter.docx")
    }

    @Test("A file renamed after it was picked still opens")
    func renamedFileStillOpens() throws {
        let file = try TemporaryFile(named: "Customers.xlsx")
        defer { file.remove() }
        let bookmark = try SecurityScopedAccess.makeBookmark(for: file.url)
        let renamed = file.directory.appending(path: "Customers 2025.xlsx")
        try FileManager.default.moveItem(at: file.url, to: renamed)

        let resolved = try SecurityScopedAccess.startAccessing(bookmarkData: bookmark)
        defer { SecurityScopedAccess.stopAccessing(resolved) }
        #expect(resolved.lastPathComponent == "Customers 2025.xlsx")
    }

    @Test("A job's references to moved files are refreshed with the new names")
    func jobRefreshesMovedFiles() throws {
        let file = try TemporaryFile(named: "Letter.docx")
        defer { file.remove() }
        let job = MailMergeJob(name: "Letters")
        job.templateBookmarkData = try SecurityScopedAccess.makeBookmark(for: file.url)
        job.templateFileName = "Letter.docx"
        let renamed = file.directory.appending(path: "Letter v2.docx")
        try FileManager.default.moveItem(at: file.url, to: renamed)

        let original = job.templateBookmarkData
        job.refreshStaleBookmarks()

        #expect(job.templateFileName == "Letter v2.docx")
        #expect(job.templateBookmarkData != original)
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: try #require(job.templateBookmarkData),
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #expect(url.lastPathComponent == "Letter v2.docx")
        #expect(isStale == false)
    }
}

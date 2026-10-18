import Foundation
import Testing
@testable import Mergeform

@Suite("ZIP archives")
struct ZIPArchiveTests {
    @Test("Entries written stored or deflated read back unchanged", arguments: [ZIPCompressionMethod.stored, .deflated])
    func roundTrip(method: ZIPCompressionMethod) throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.zip")
        let text = Data(String(repeating: "Dear {{Name}}, ", count: 2_000).utf8)

        let writer = try ZIPArchiveWriter(url: url)
        try writer.addEntry(path: "word/document.xml", contents: text, method: method)
        try writer.addEntry(path: "Résumé – Ünïcode.txt", contents: Data("ok".utf8), method: method)
        try writer.addEntry(path: "empty.txt", contents: Data(), method: method)
        try writer.finish()

        let archive = try ZIPArchive(url: url)
        #expect(archive.entries.map(\.path) == ["word/document.xml", "Résumé – Ünïcode.txt", "empty.txt"])
        #expect(try archive.data(at: "word/document.xml") == text)
        #expect(try archive.data(at: "Résumé – Ünïcode.txt") == Data("ok".utf8))
        #expect(try archive.data(at: "empty.txt") == Data())
    }

    @Test("Paths match exactly first, then ignoring case, and missing paths are nil")
    func lookup() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.zip")
        let writer = try ZIPArchiveWriter(url: url)
        try writer.addEntry(path: "xl/Workbook.xml", contents: Data("mixed".utf8))
        try writer.addEntry(path: "xl/workbook.xml", contents: Data("lower".utf8))
        try writer.finish()

        let archive = try ZIPArchive(url: url)
        #expect(try archive.data(at: "xl/workbook.xml") == Data("lower".utf8))
        #expect(try archive.data(at: "XL/WORKBOOK.XML") == Data("mixed".utf8))
        #expect(try archive.data(at: "xl/missing.xml") == nil)
    }

    @Test("A ZIP64 archive written by Info-ZIP reads correctly")
    func readsZIP64() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "zip64.zip")
        try #require(Data(base64Encoded: Self.infoZIP64Archive)).write(to: url)

        let archive = try ZIPArchive(url: url)
        #expect(archive.entries.map(\.path) == ["sub/", "sub/b.txt", "a.txt"])
        #expect(try archive.data(at: "sub/b.txt") == Data("hi\n".utf8))
        let deflated = try #require(try archive.data(at: "a.txt"))
        #expect(deflated == Data(String(repeating: "alpha ", count: 2_000).utf8))
        #expect(CRC32.checksum(of: deflated) == 0xC003_0CAC)
    }

    @Test("A file that isn't a ZIP archive is rejected")
    func rejectsOtherFiles() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.txt")
        try Data("This is plain text, not a spreadsheet.".utf8).write(to: url)

        #expect(throws: ZIPArchiveError.self) { try ZIPArchive(url: url) }
    }

    @Test("CRC-32 matches the standard check value")
    func checksum() {
        #expect(CRC32.checksum(of: Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(of: Data()) == 0)
    }

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// `zip -r -fz` of a folder holding `a.txt` ("alpha " × 2,000, deflated) and
    /// `sub/b.txt` ("hi\n", stored), which forces ZIP64 headers and end records.
    private static let infoZIP64Archive = "UEsDBC0AAAAAAAa5UV0AAAAA//////////8EADAAc3ViL1VUCQADHDjUahw41Gp1eAsAAQT1AQAABAAAAAABABAAAAAAAAAAAAAAAAAAAAAAAFBLAwQtAAAAAAAGuVFdenpv7f//////////CQAwAHN1Yi9iLnR4dFVUCQADHDjUahw41Gp1eAsAAQT1AQAABAAAAAABABAAAwAAAAAAAAADAAAAAAAAAGhpClBLAwQtAAAACAAGuVFdrAwDwP//////////BQAwAGEudHh0VVQJAAMcONRqHDjUanV4CwABBPUBAAAEAAAAAAEAEADgLgAAAAAAACsAAAAAAAAA7cQhAQAACAOwKlS7QyDor4iB2cQy26nYtm3btm3btm3btm3btm3btv36AVBLAQIeAwoAAAAAAAa5UV0AAAAAAAAAAP////8EACQAAAAAAAAAEADtQQAAAABzdWIvVVQFAAMcONRqdXgLAAEE9QEAAAQAAAAAAQAIAAAAAAAAAAAAUEsBAh4DLQAAAAAABrlRXXp6b+0DAAAA/////wkAJAAAAAAAAQAAAKSBUgAAAHN1Yi9iLnR4dFVUBQADHDjUanV4CwABBPUBAAAEAAAAAAEACAADAAAAAAAAAFBLAQIeAy0AAAAIAAa5UV2sDAPAKwAAAP////8FACQAAAAAAAEAAACkgawAAABhLnR4dFVUBQADHDjUanV4CwABBPUBAAAEAAAAAAEACADgLgAAAAAAAFBLBgYsAAAAAAAAAB4DLQAAAAAAAAAAAAMAAAAAAAAAAwAAAAAAAAAIAQAAAAAAACoBAAAAAAAAUEsGBwAAAAAyAgAAAAAAAAEAAABQSwUGAAAAAAMAAwAIAQAA/////wAA"
}

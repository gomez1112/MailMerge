import Foundation
import Observation
import Synchronization
import PDFKit
import SwiftData
import Testing
@testable import Mergeform

@MainActor
@Suite("1.2.1 regressions", .serialized)
struct ReleaseRegressionTests {
    @Test("Excel special formats preserve literals and conditions", arguments: [
        (123456789.0, #"00000\-0000"#, "12345-6789"),
        (123456789.0, #"000\-00\-0000"#, "123-45-6789"),
        (5551234567.0, #"[<=9999999]###\-####;\(###\)\ ###\-####"#, "(555) 123-4567"),
        (5551234.0, #"[<=9999999]###\-####;\(###\)\ ###\-####"#, "555-1234"),
        (500.0, #"[>=1000000]0.0,,"M";[>=1000]0.0,"K";0"#, "500"),
        (-1500.0, #"[>=1000000]0.0,,"M";[>=1000]0.0,"K";0"#, "-1500"),
        (5.0, #"General" kg""#, "5 kg"),
        (1234.5, "[Blue]General", "1234.5"),
        (-3.0, "General;[Red]-General", "-3"),
        (0.0, #"_("$"* #,##0.00_);_("$"* \(#,##0.00\);_("$"* "-"??_);_(@_)"#, "$-"),
        (0.0, "#,###", ""),
        (0.25, "# ?/?", "1/4"),
        (12345.0, "##0.0E+0", "12.3E+3")
    ])
    func excelFormats(value: Double, code: String, expected: String) {
        let formatter = ExcelValueFormatter(locale: Locale(identifier: "en_US"), usesDate1904: false)
        #expect(formatter.string(forNumber: value, formatID: 164, formatCode: code) == expected)
    }

    @Test("Built-in accounting format 44 works without a custom definition")
    func builtInAccounting() {
        let formatter = ExcelValueFormatter(locale: Locale(identifier: "en_US"), usesDate1904: false)
        #expect(formatter.string(forNumber: 1234.5, formatID: 44, formatCode: nil) == "$1,234.50")
    }

    @Test("Formatting transformations round like Excel")
    func rounding() {
        #expect(FieldTransformation.numberFormat.apply(to: "2.5", formatString: "#,##0") == "3")
        #expect(FieldTransformation.numberFormat.apply(to: "0.125", formatString: "#,##0.00") == "0.13")
        #expect(FieldTransformation.currencyFormat.apply(to: "10.125", formatString: "USD") == "$10.13")
        #expect(FieldTransformation.currencyFormat.apply(to: "1.005", formatString: "USD") == "$1.01")
    }

    @Test("Two same-named jobs keep independent email attachments", arguments: [false, true])
    func attachmentsAreIndependent(combined: Bool) async throws {
        let first = try MergeFixture(recordCount: 1)
        let second = try MergeFixture(recordCount: 3)
        defer { first.remove(); second.remove() }
        let engine = MergeFixture.makeEngine()
        let a = try await engine.performMerge(job: first.job, singleDocument: combined, progress: { _ in })
        let urlA = try #require(a.attachmentURL)
        let original = try Data(contentsOf: urlA)
        let b = try await engine.performMerge(job: second.job, singleDocument: combined, progress: { _ in })
        #expect(urlA != b.attachmentURL)
        #expect(try Data(contentsOf: urlA) == original)
    }

    @Test("Repeated merges preserve existing PDFs", arguments: [false, true])
    func preservesExistingOutput(combined: Bool) async throws {
        let fixture = try MergeFixture(recordCount: 1)
        defer { fixture.remove() }
        let engine = MergeFixture.makeEngine()
        let first = try await engine.performMerge(job: fixture.job, singleDocument: combined, progress: { _ in })
        let oldURL = fixture.outputFolder.appending(path: try #require(first.savedFileNames.first))
        let marker = Data("An existing document must survive".utf8)
        try marker.write(to: oldURL)
        let next = try await engine.performMerge(job: fixture.job, singleDocument: combined, progress: { _ in })
        #expect(next.savedFileNames != first.savedFileNames)
        #expect(try Data(contentsOf: oldURL) == marker)
    }

    @Test("Loading transient column names invalidates observed views")
    func columnObservation() {
        let job = MailMergeJob(name: "Columns")
        let changed = ChangeFlag()
        withObservationTracking { _ = job.availableColumns } onChange: { changed.mark() }
        job.updateAvailableColumns(["Name"])
        #expect(changed.wasMarked)
    }


    @Test("Switching sheets and back restores manual column choices")
    func manualMappingsSurviveSheetSwitch() {
        let job = MailMergeJob(name: "Mappings", selectedSheetName: "Customers")
        let mapping = FieldMapping(placeholderText: "Name", columnName: "Preferred Name", job: job)
        job.fieldMappings = [mapping]
        job.updateAvailableColumns(["Name", "Preferred Name"])
        job.selectSheet("Orders")
        job.updateAvailableColumns(["Order", "Name"])
        job.autoMatchUnmappedFields()
        #expect(mapping.columnName == "Name")
        job.selectSheet("Customers")
        job.updateAvailableColumns(["Name", "Preferred Name"])
        job.autoMatchUnmappedFields()
        #expect(mapping.columnName == "Preferred Name")
        #expect(mapping.isAutoMatched == false)
    }

    @Test("Reloading a workbook reconciles a deleted or renamed selected sheet")
    func renamedSheet() {
        let job = MailMergeJob(name: "Sheets", selectedSheetName: "Old")
        job.updateAvailableColumns(["Old Column"])
        job.updateAvailableSheets(["New", "Other"])
        #expect(job.selectedSheetName == nil)
        #expect(job.availableColumns.isEmpty)
        job.updateAvailableSheets(["New"])
        #expect(job.selectedSheetName == "New")
    }

    @Test("Date transformations use the original cell date, including its century", arguments: ["m/d/yy", "dd/mm/yyyy;@"])
    func originalExcelDates(format: String) async throws {
        let formatter = ExcelValueFormatter(locale: Locale(identifier: "en_US"), usesDate1904: false)
        let original = try Date.ISO8601FormatStyle().year().month().day().parse("1940-05-01")
        let serial = formatter.serial(for: original)
        let fixture = XLSXFixture(rowsXML: """
        <row r="1"><c r="A1" t="inlineStr"><is><t>Birth Date</t></is></c></row>
        <row r="2"><c r="A2" s="1"><v>\(serial)</v></c></row>
        """, stylesXML: XLSXFixture.styles(numberFormatIDs: [0, 164], customFormats: [164: format]))
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        let rawDate = try #require(sheet.datesByColumn(at: 0)["Birth Date"])
        #expect(FieldTransformation.dateFormat.apply(to: sheet.rows[0][0], formatString: "yyyy-MM-dd", dateValue: rawDate) == "1940-05-01")
        let mapping = FieldMapping(placeholderText: "Date", columnName: "Birth Date", transformation: .dateFormat, formatString: "yyyy-MM-dd")
        let merged = MergeEngine.merge(template: NSAttributedString(string: "{{Date}}"), rowData: ["Birth Date": sheet.rows[0][0]], mappings: [MappingSnapshot(from: mapping)], datesByColumn: sheet.datesByColumn(at: 0))
        #expect(merged.string == "1940-05-01")
    }

    @Test("Jobs created from the template library already have scanned fields")
    func templateLibraryScansFields() async throws {
        let fixture = try MergeFixture(recordCount: 1)
        defer { fixture.remove() }
        let bookmark = try #require(fixture.job.templateBookmarkData)
        let job = try await MergeFixture.makeEngine().createJobFromTemplate(bookmark: bookmark, fileName: "Thank You.docx", category: nil, in: fixture.container.mainContext)
        #expect(job.name == "Thank You")
        #expect(job.fieldMappings.map(\.displayName) == ["Name"])
    }

    @Test("Malformed spreadsheet references fail without overflow or huge allocations", arguments: ["ZZZZZZZZZZZZZZ1", "XFE1"])
    func malformedSpreadsheet(reference: String) async throws {
        let fixture = XLSXFixture(rowsXML: "<row r=\"1\"><c r=\"\(reference)\"><v>1</v></c></row>")
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(throws: (any Error).self) {
            _ = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        }
    }

    @Test("Saving a deletion during a merge never touches the detached model")
    func savedDeletionDuringMerge() async throws {
        let fixture = try MergeFixture(recordCount: 40)
        defer { fixture.remove() }
        let context = fixture.container.mainContext
        try context.save()
        let engine = MergeFixture.makeEngine()
        var mergeTask: Task<MergeResult, Error>?
        mergeTask = Task {
            try await engine.performMerge(job: fixture.job, singleDocument: false) { progress in
                guard progress.completed == 1 else { return }
                mergeTask?.cancel()
                context.delete(fixture.job)
                do { try context.save() } catch { Issue.record(error) }
            }
        }
        let task = try #require(mergeTask)
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(fixture.outputFileNames.count == 1)
        // A queued preview can also begin after the deletion was saved.
        await #expect(throws: CancellationError.self) {
            _ = try await engine.generatePreview(job: fixture.job, recordIndex: 0)
        }

    }

}

// Mutex keeps Observation's Sendable callback safe without an isolation escape hatch.
nonisolated private final class ChangeFlag: Sendable {
    private let storage = Mutex(false)
    func mark() { storage.withLock { $0 = true } }
    var wasMarked: Bool { storage.withLock { $0 } }
}

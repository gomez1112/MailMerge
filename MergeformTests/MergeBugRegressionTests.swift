import Foundation
import Testing
@testable import Mergeform

@MainActor
@Suite("Merge row data")
struct MergeRowDataTests {
    @Test("Headers with stray whitespace still resolve to their trimmed column names")
    func trimsHeaderKeys() {
        // The column picker offers trimmed header names, so the row lookup must use them too.
        let rowData = MergeEngine.rowData(headers: ["First Name ", " City"], row: ["Ada", "London"])
        #expect(rowData["First Name"] == "Ada")
        #expect(rowData["City"] == "London")
    }
}

@MainActor
@Suite("Output file names")
struct OutputFileNameTests {
    @Test("Records that produce the same name get distinct files")
    func duplicateNamesAreMadeUnique() {
        var usedNames: Set<String> = []
        let row = ["FirstName": "Ada", "LastName": "Lovelace"]
        let names = (1...3).map { index in
            MergeEngine.outputFileName(
                pattern: "Letter_{FirstName}_{LastName}",
                rowIndex: index,
                rowData: row,
                usedNames: &usedNames
            )
        }
        #expect(names == ["Letter_Ada_Lovelace.pdf", "Letter_Ada_Lovelace 2.pdf", "Letter_Ada_Lovelace 3.pdf"])
    }

    @Test("Uniqueness ignores case, matching the default macOS file system")
    func uniquenessIsCaseInsensitive() {
        var usedNames: Set<String> = []
        let first = MergeEngine.outputFileName(pattern: "{Name}", rowIndex: 1, rowData: ["Name": "ada"], usedNames: &usedNames)
        let second = MergeEngine.outputFileName(pattern: "{Name}", rowIndex: 2, rowData: ["Name": "ADA"], usedNames: &usedNames)
        #expect(first == "ada.pdf")
        #expect(second == "ADA 2.pdf")
    }

    @Test("Unique names keep the existing row and sanitizing behavior")
    func uniqueNamesStillSanitize() {
        var usedNames: Set<String> = []
        let name = MergeEngine.outputFileName(pattern: "{Row}_{Name}", rowIndex: 4, rowData: ["Name": "A/B"], usedNames: &usedNames)
        #expect(name == "4_A_B.pdf")
    }
}

@MainActor
@Suite("Spreadsheet text cells")
struct SpreadsheetTextCellTests {
    @Test("Text cells keep leading zeros and decimal-looking text verbatim")
    func preservesTextCells() async throws {
        let url = try XLSXFixture(
            rowsXML: """
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>
            <row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c><c r="C2" t="s"><v>5</v></c></row>
            """,
            sharedStrings: ["Name", "Zip", "Code", "Ada", "02134", "0.250000"]
        ).write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        #expect(sheet.headers == ["Name", "Zip", "Code"])
        #expect(sheet.rows == [["Ada", "02134", "0.250000"]])
    }

    @Test("Numeric cells are still normalized")
    func numericCellsStillNormalize() async throws {
        let url = try XLSXFixture(
            rowsXML: """
            <row r="1"><c r="A1" t="s"><v>0</v></c></row>
            <row r="2"><c r="A2"><v>42</v></c></row>
            """,
            sharedStrings: ["Amount"]
        ).write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        #expect(sheet.rows == [["42"]])
    }
}

import Foundation
import Testing
import ZIPFoundation
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
        let url = try XLSXFixture.make(
            sharedStrings: ["Name", "Zip", "Code", "Ada", "02134", "0.250000"],
            rows: [
                [(0, "s"), (1, "s"), (2, "s")],
                [(3, "s"), (4, "s"), (5, "s")]
            ]
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        #expect(sheet.headers == ["Name", "Zip", "Code"])
        #expect(sheet.rows == [["Ada", "02134", "0.250000"]])
    }

    @Test("Numeric cells are still normalized")
    func numericCellsStillNormalize() async throws {
        let url = try XLSXFixture.make(
            sharedStrings: ["Amount"],
            rows: [
                [(0, "s")],
                [(42, "n")]
            ]
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        #expect(sheet.rows == [["42"]])
    }
}

/// Builds a minimal single-sheet .xlsx file in a fresh temporary directory.
private enum XLSXFixture {
    /// Each row is a list of cells; a cell is (value, type) where type "s" means the
    /// value is a shared-string index and "n" means it is a literal number.
    static func make(sharedStrings: [String], rows: [[(Int, String)]]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixture.xlsx")
        let archive = try Archive(url: url, accessMode: .create)

        let columns = Array("ABCDEFGHIJ")
        let sheetRows = rows.enumerated().map { rowIndex, cells in
            let cellXML = cells.enumerated().map { columnIndex, cell in
                let reference = "\(columns[columnIndex])\(rowIndex + 1)"
                let typeAttribute = cell.1 == "s" ? " t=\"s\"" : ""
                return "<c r=\"\(reference)\"\(typeAttribute)><v>\(cell.0)</v></c>"
            }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cellXML)</row>"
        }.joined()
        let stringItems = sharedStrings.map { "<si><t>\($0)</t></si>" }.joined()

        let entries: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>
            """),
            ("xl/worksheets/sheet1.xml", """
            <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(sheetRows)</sheetData></worksheet>
            """),
            ("xl/sharedStrings.xml", """
            <?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(stringItems)</sst>
            """)
        ]
        for (path, contents) in entries {
            let data = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }
}

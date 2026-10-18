import Foundation
import ZIPFoundation

/// Builds a minimal .xlsx package in a fresh temporary directory so tests can exercise
/// the spreadsheet reader against real-world file shapes.
struct XLSXFixture {
    /// The `<row>` elements that go inside `<sheetData>`.
    var rowsXML: String
    /// Plain shared strings, written as simple `<si><t>…</t></si>` items.
    var sharedStrings: [String] = []
    /// Raw `<si>` items appended after `sharedStrings`, for rich text and other shapes.
    var extraSharedStringItemsXML = ""
    /// A complete `xl/styles.xml` document, or nil to omit the part.
    var stylesXML: String?
    /// Attributes for `<workbookPr>`, such as `date1904="1"`.
    var workbookPropertiesAttributes = ""
    /// The officeDocument target in `_rels/.rels`.
    var rootWorkbookTarget = "xl/workbook.xml"
    /// Extra `<Relationship>` elements for `xl/_rels/workbook.xml.rels`.
    var extraWorkbookRelationshipsXML = ""
    /// Extra `<sheet>` elements for `xl/workbook.xml`.
    var extraSheetsXML = ""
    /// Additional package parts, keyed by path.
    var extraParts: [String: String] = [:]
    var sheetName = "Sheet1"

    /// Writes the package and returns its URL. Delete `url.deletingLastPathComponent()`
    /// when done.
    func write() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixture.xlsx")
        let archive = try Archive(url: url, accessMode: .create)

        let plainItems = sharedStrings.map { "<si><t xml:space=\"preserve\">\(Self.escaped($0))</t></si>" }.joined()
        var parts: [String: String] = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="\(rootWorkbookTarget)"/></Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><workbookPr \(workbookPropertiesAttributes)/><sheets><sheet name="\(Self.escaped(sheetName))" sheetId="1" r:id="rId1"/>\(extraSheetsXML)</sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\(extraWorkbookRelationshipsXML)</Relationships>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rowsXML)</sheetData></worksheet>
            """,
            "xl/sharedStrings.xml": """
            <?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\(plainItems)\(extraSharedStringItemsXML)</sst>
            """
        ]
        if let stylesXML {
            parts["xl/styles.xml"] = stylesXML
        }
        parts.merge(extraParts) { _, new in new }

        for (path, contents) in parts.sorted(by: { $0.key < $1.key }) {
            let data = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    /// A styles part whose `cellXfs` use the given number format IDs, in order, so a cell
    /// with `s="n"` uses `numberFormatIDs[n]`.
    static func styles(numberFormatIDs: [Int], customFormats: [Int: String] = [:], extraXML: String = "") -> String {
        let formats = customFormats.sorted(by: { $0.key < $1.key })
            .map { "<numFmt numFmtId=\"\($0.key)\" formatCode=\"\(escaped($0.value))\"/>" }
            .joined()
        let xfs = numberFormatIDs.map { "<xf numFmtId=\"\($0)\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="\(customFormats.count)">\(formats)</numFmts><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="\(numberFormatIDs.count)">\(xfs)</cellXfs>\(extraXML)</styleSheet>
        """
    }

    static func escaped(_ text: String) -> String {
        text.replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
    }
}

import Foundation

/// Reads worksheets from an .xlsx package with a streaming XML parser.
///
/// Spreadsheets in the wild contain parts that strict schema decoders reject, such as
/// conditional-format styles without number formats, relationship types added in newer
/// Excel versions, and absolute part paths. This reader only looks at the handful of
/// elements a mail merge needs and ignores everything else.
nonisolated struct XLSXPackageReader {
    nonisolated struct SheetReference: Equatable {
        var name: String
        /// The package path of the worksheet part, such as `xl/worksheets/sheet1.xml`.
        var path: String
    }

    /// Worksheets in workbook order. Chart sheets and other non-grid sheets are excluded.
    let sheets: [SheetReference]
    /// Whether serial dates count from 1904 (older Mac workbooks) instead of 1900.
    let usesDate1904: Bool

    private let archive: ZIPArchive
    private let sharedStringsPath: String?
    private let stylesPath: String?

    init(url: URL) throws {
        do {
            archive = try ZIPArchive(url: url)
        } catch {
            throw MergeError.invalidSpreadsheet
        }

        let rootRelationships = try Self.relationships(in: archive, forPartAt: "")
        guard let workbookPath = rootRelationships.first(where: { $0.type.hasSuffix("/officeDocument") })?.target else {
            throw MergeError.invalidSpreadsheet
        }
        let workbookRelationships = try Self.relationships(in: archive, forPartAt: workbookPath)
        let workbook = WorkbookHandler()
        try Self.parse(archive, path: workbookPath, with: workbook)

        let relationshipsByID = Dictionary(
            workbookRelationships.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        sheets = workbook.sheets.compactMap { sheet in
            guard let relationship = relationshipsByID[sheet.relationshipID],
                  relationship.type.hasSuffix("/worksheet") else {
                return nil
            }
            return SheetReference(name: sheet.name, path: relationship.target)
        }
        usesDate1904 = workbook.usesDate1904
        sharedStringsPath = workbookRelationships.first { $0.type.hasSuffix("/sharedStrings") }?.target
        stylesPath = workbookRelationships.first { $0.type.hasSuffix("/styles") }?.target
    }

    /// The workbook's shared string table, with rich-text runs joined into plain text.
    func sharedStrings() throws -> [String] {
        guard let sharedStringsPath, Self.entryData(in: archive, path: sharedStringsPath) != nil else {
            return []
        }
        let handler = SharedStringsHandler()
        try Self.parse(archive, path: sharedStringsPath, with: handler)
        return handler.items
    }

    /// The number formats used by cell styles. A missing or unreadable styles part yields
    /// no formats, so values still load as General.
    func styles() -> XLSXStyles {
        guard let stylesPath else { return XLSXStyles() }
        let handler = StylesHandler()
        do {
            try Self.parse(archive, path: stylesPath, with: handler)
        } catch {
            return XLSXStyles()
        }
        return XLSXStyles(cellFormatIDs: handler.cellFormatIDs, customFormats: handler.customFormats)
    }

    /// Every row in the worksheet part, in document order.
    func rows(inSheetAt path: String) throws -> [XLSXRow] {
        let handler = WorksheetHandler()
        try Self.parse(archive, path: path, with: handler)
        return handler.rows
    }

    // MARK: - Package Helpers

    nonisolated private struct Relationship {
        var id: String
        var type: String
        var target: String
    }

    /// Reads the relationships of the part at `partPath` (or of the package when empty),
    /// with targets resolved to package paths.
    private static func relationships(in archive: ZIPArchive, forPartAt partPath: String) throws -> [Relationship] {
        let directory = (partPath as NSString).deletingLastPathComponent
        let fileName = (partPath as NSString).lastPathComponent
        let relationshipsPath = directory.isEmpty
            ? "_rels/\(fileName).rels"
            : "\(directory)/_rels/\(fileName).rels"
        guard entryData(in: archive, path: relationshipsPath) != nil else { return [] }
        let handler = RelationshipsHandler()
        try parse(archive, path: relationshipsPath, with: handler)
        return handler.relationships.map { relationship in
            Relationship(
                id: relationship.id,
                type: relationship.type,
                target: resolve(relationship.target, relativeTo: directory)
            )
        }
    }

    /// Resolves a relationship target against the directory of its source part. Targets
    /// may be relative (`worksheets/sheet1.xml`, `../xl/styles.xml`) or absolute
    /// (`/xl/workbook.xml`).
    static func resolve(_ target: String, relativeTo directory: String) -> String {
        var components = target.hasPrefix("/") ? [] : directory.split(separator: "/").map(String.init)
        for part in target.split(separator: "/") {
            switch part {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    /// The contents of the part at `path`, matched ignoring case. A part that can't be
    /// read is treated like a missing one.
    private static func entryData(in archive: ZIPArchive, path: String) -> Data? {
        do {
            return try archive.data(at: path)
        } catch {
            return nil
        }
    }

    private static func parse(_ archive: ZIPArchive, path: String, with delegate: some XMLParserDelegate) throws {
        guard let data = entryData(in: archive, path: path) else {
            throw MergeError.invalidSpreadsheet
        }
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MergeError.invalidSpreadsheet
        }
    }
}

// MARK: - Parsed Values

/// One worksheet row. Cells are sparse: empty cells are usually absent.
nonisolated struct XLSXRow {
    var cells: [XLSXCell] = []
}

nonisolated struct XLSXCell {
    /// Zero-based column index.
    var column: Int
    /// The raw `t` attribute: `s`, `str`, `inlineStr`, `b`, `e`, `d`, `n`, or nil.
    var type: String?
    var styleIndex: Int?
    /// The text of the `<v>` element.
    var value: String?
    /// The text of an `<is>` inline string, with rich-text runs joined.
    var inlineText: String?
}

nonisolated struct XLSXStyles {
    /// The number format ID of each cell format (`cellXfs`), indexed by a cell's `s`.
    var cellFormatIDs: [Int] = []
    /// Format codes defined in the workbook, keyed by number format ID.
    var customFormats: [Int: String] = [:]

    func numberFormatID(forStyleIndex index: Int?) -> Int {
        guard let index, cellFormatIDs.indices.contains(index) else { return 0 }
        return cellFormatIDs[index]
    }
}

// MARK: - XML Handlers

/// Strips a namespace prefix, so `x:row` and `row` are treated alike.
nonisolated private func localName(_ name: String) -> String {
    guard let colon = name.lastIndex(of: ":") else { return name }
    return String(name[name.index(after: colon)...])
}

nonisolated private func localAttributes(_ attributes: [String: String]) -> [String: String] {
    Dictionary(attributes.map { (localName($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
}

/// Decodes the `_xHHHH_` escapes OOXML uses for control characters in strings.
nonisolated private func decodeOOXMLEscapes(_ text: String) -> String {
    guard text.contains("_x") else { return text }
    let regex = /_x([0-9A-Fa-f]{4})_/
    return text.replacing(regex) { match in
        guard let scalarValue = UInt32(match.1, radix: 16), let scalar = Unicode.Scalar(scalarValue) else {
            return String(match.0)
        }
        return String(Character(scalar))
    }
}

nonisolated private final class RelationshipsHandler: NSObject, XMLParserDelegate {
    nonisolated struct Item {
        var id: String
        var type: String
        var target: String
    }

    var relationships: [Item] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        guard localName(elementName) == "Relationship" else { return }
        let attributes = localAttributes(attributes)
        guard attributes["TargetMode"] != "External",
              let id = attributes["Id"],
              let type = attributes["Type"],
              let target = attributes["Target"] else {
            return
        }
        relationships.append(Item(id: id, type: type, target: target))
    }
}

nonisolated private final class WorkbookHandler: NSObject, XMLParserDelegate {
    nonisolated struct Sheet {
        var name: String
        var relationshipID: String
    }

    var sheets: [Sheet] = []
    var usesDate1904 = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let attributes = localAttributes(attributes)
        switch localName(elementName) {
        case "workbookPr":
            let value = attributes["date1904"]?.lowercased()
            usesDate1904 = value == "1" || value == "true"
        case "sheet":
            // `r:id` becomes "id" once the prefix is stripped; `sheetId` is a different key.
            if let name = attributes["name"], let relationshipID = attributes["id"] {
                sheets.append(Sheet(name: name, relationshipID: relationshipID))
            }
        default:
            break
        }
    }
}

nonisolated private final class SharedStringsHandler: NSObject, XMLParserDelegate {
    var items: [String] = []
    private var current: String?
    private var isInText = false
    private var phoneticDepth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch localName(elementName) {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": isInText = current != nil && phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText { current?.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "si":
            items.append(decodeOOXMLEscapes(current ?? ""))
            current = nil
        case "rPh": phoneticDepth -= 1
        case "t": isInText = false
        default: break
        }
    }
}

nonisolated private final class StylesHandler: NSObject, XMLParserDelegate {
    var cellFormatIDs: [Int] = []
    var customFormats: [Int: String] = [:]
    private var stack: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let name = localName(elementName)
        let attributes = localAttributes(attributes)
        // Only top-level formats count; <dxf> elements carry their own numFmt and xf-like
        // children that must not be mixed in.
        if name == "numFmt", stack.last == "numFmts",
           let id = attributes["numFmtId"].flatMap(Int.init),
           let code = attributes["formatCode"] {
            customFormats[id] = code
        } else if name == "xf", stack.last == "cellXfs" {
            cellFormatIDs.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
        }
        stack.append(name)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }
}

nonisolated private final class WorksheetHandler: NSObject, XMLParserDelegate {
    var rows: [XLSXRow] = []
    private var currentRow: XLSXRow?
    private var currentCell: XLSXCell?
    private var nextColumn = 0
    private var buffer = ""
    private var isInValue = false
    private var isInInlineString = false
    private var isInInlineText = false
    private var phoneticDepth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let attributes = localAttributes(attributes)
        switch localName(elementName) {
        case "row":
            currentRow = XLSXRow()
            nextColumn = 0
        case "c":
            let column: Int
            if let reference = attributes["r"] {
                guard let parsed = Self.columnIndex(fromReference: reference) else {
                    parser.abortParsing()
                    return
                }
                column = parsed
            } else {
                guard nextColumn < 16_384 else { parser.abortParsing(); return }
                column = nextColumn
            }
            currentCell = XLSXCell(
                column: column,
                type: attributes["t"],
                styleIndex: attributes["s"].flatMap(Int.init)
            )
            nextColumn = column + 1
        case "v":
            isInValue = currentCell != nil
            buffer = ""
        case "is":
            isInInlineString = currentCell != nil
            buffer = ""
        case "rPh":
            phoneticDepth += 1
        case "t":
            isInInlineText = isInInlineString && phoneticDepth == 0
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInValue || isInInlineText { buffer.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "v":
            if isInValue { currentCell?.value = buffer }
            isInValue = false
        case "t":
            isInInlineText = false
        case "rPh":
            phoneticDepth -= 1
        case "is":
            if isInInlineString { currentCell?.inlineText = decodeOOXMLEscapes(buffer) }
            isInInlineString = false
        case "c":
            if let currentCell { currentRow?.cells.append(currentCell) }
            currentCell = nil
        case "row":
            if let currentRow { rows.append(currentRow) }
            currentRow = nil
        default:
            break
        }
    }

    /// Converts the letters of a reference like `AB12` to a zero-based column index.
    static func columnIndex(fromReference reference: String) -> Int? {
        var result = 0
        var sawLetter = false
        for scalar in reference.unicodeScalars {
            let uppercase: UInt32
            switch scalar.value {
            case 65...90: uppercase = scalar.value
            case 97...122: uppercase = scalar.value - 32
            default: return sawLetter ? result - 1 : nil
            }
            // Excel has at most 16,384 columns (XFD). Bound before multiplying,
            // preventing overflow and huge allocations on malformed references.
            guard result <= 630 else { return nil }
            result = result * 26 + Int(uppercase - 64)
            guard result <= 16_384 else { return nil }
            sawLetter = true
        }
        return sawLetter ? result - 1 : nil
    }
}

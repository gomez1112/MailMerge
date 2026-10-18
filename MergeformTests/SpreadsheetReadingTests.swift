import Foundation
import Testing
@testable import Mergeform

/// Reads a one-column fixture and returns its header and first data value.
@MainActor
private func readSingleColumn(
    _ fixture: XLSXFixture,
    locale: Locale = Locale(identifier: "en_US")
) async throws -> (header: String?, value: String?) {
    let url = try fixture.write()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil, locale: locale)
    return (sheet.headers.first, sheet.rows.first?.first)
}

/// A fixture with a "Header" shared-string header and one numeric data cell.
private func numericFixture(_ value: String, style: Int? = nil, styles: String? = nil, header: String = "Header") -> XLSXFixture {
    let styleAttribute = style.map { " s=\"\($0)\"" } ?? ""
    return XLSXFixture(
        rowsXML: """
        <row r="1"><c r="A1" t="s"><v>0</v></c></row>
        <row r="2"><c r="A2"\(styleAttribute)><v>\(value)</v></c></row>
        """,
        sharedStrings: [header],
        stylesXML: styles
    )
}

@MainActor
@Suite("Spreadsheet cell text")
struct SpreadsheetCellTextTests {
    @Test("Rich-text shared strings keep their text instead of showing the string index")
    func richTextSharedStrings() async throws {
        let fixture = XLSXFixture(
            rowsXML: """
            <row r="1"><c r="A1" t="s"><v>0</v></c></row>
            <row r="2"><c r="A2" t="s"><v>1</v></c></row>
            """,
            sharedStrings: ["Name"],
            extraSharedStringItemsXML: #"<si><r><rPr><b/></rPr><t>John</t></r><r><t xml:space="preserve"> Smith</t></r><rPh sb="0" eb="1"><t>ジョン</t></rPh></si>"#
        )
        let result = try await readSingleColumn(fixture)
        #expect(result.value == "John Smith")
    }

    @Test("Rich inline strings keep their text")
    func richInlineStrings() async throws {
        let fixture = XLSXFixture(rowsXML: """
            <row r="1"><c r="A1" t="inlineStr"><is><t>Word</t></is></c></row>
            <row r="2"><c r="A2" t="inlineStr"><is><r><t>Ri</t></r><r><t>ch</t></r></is></c></row>
            """)
        let result = try await readSingleColumn(fixture)
        #expect(result.header == "Word")
        #expect(result.value == "Rich")
    }

    @Test("TRUE and FALSE cells read as TRUE and FALSE")
    func booleanCells() async throws {
        let fixture = XLSXFixture(
            rowsXML: """
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
            <row r="2"><c r="A2" t="b"><v>1</v></c><c r="B2" t="b"><v>0</v></c></row>
            """,
            sharedStrings: ["Subscribed", "Archived"]
        )
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        #expect(sheet.rows == [["TRUE", "FALSE"]])
    }

    @Test("A blank, formatted first row is skipped when finding the header row")
    func skipsBlankLeadingRows() async throws {
        let fixture = XLSXFixture(
            rowsXML: """
            <row r="1" ht="30" customHeight="1"><c r="A1" s="0"/><c r="B1" s="0"/></row>
            <row r="2"><c r="A2" t="s"><v>0</v></c><c r="B2" t="s"><v>1</v></c></row>
            <row r="3"><c r="A3" t="s"><v>2</v></c><c r="B3"><v>7</v></c></row>
            """,
            sharedStrings: ["Name", "Count", "Ada"]
        )
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sheet = try await ExcelParserService().loadSheet(at: url, sheetName: "Sheet1", rowLimit: nil)
        #expect(sheet.headers == ["Name", "Count"])
        #expect(sheet.rows == [["Ada", "7"]])
    }
}

@MainActor
@Suite("Spreadsheet number formats")
struct SpreadsheetNumberFormatTests {
    @Test("Percent cells show as percentages, not clock times")
    func percentages() async throws {
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 10, 9])
        #expect(try await readSingleColumn(numericFixture("0.0825", style: 1, styles: styles, header: "Discount")).value == "8.25%")
        #expect(try await readSingleColumn(numericFixture("0.15", style: 2, styles: styles, header: "Tax")).value == "15%")
    }

    @Test("Small decimals are not turned into clock times")
    func smallDecimalsStayNumbers() async throws {
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 2])
        #expect(try await readSingleColumn(numericFixture("0.4536", style: 1, styles: styles, header: "Weight (kg)")).value == "0.45")
        #expect(try await readSingleColumn(numericFixture("0.30000000000000004", header: "Total")).value == "0.3")
        #expect(try await readSingleColumn(numericFixture("0.375", header: "Start Time")).value == "0.375")
    }

    @Test("Formula results don't show floating-point noise", arguments: [
        ("434.99999999999994", "435"),
        ("110.00000000000001", "110"),
        ("3.3000000000000003", "3.3"),
        ("-1234.5", "-1234.5")
    ])
    func generalNumbersUseFifteenDigits(raw: String, expected: String) async throws {
        #expect(try await readSingleColumn(numericFixture(raw)).value == expected)
    }

    @Test("Currency, thousands and negative-section formats are applied")
    func numberFormats() async throws {
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 165, 3, 39], customFormats: [165: "\"$\"#,##0.00"])
        #expect(try await readSingleColumn(numericFixture("1234.5", style: 1, styles: styles)).value == "$1,234.50")
        #expect(try await readSingleColumn(numericFixture("-1234", style: 2, styles: styles)).value == "-1,234")
        #expect(try await readSingleColumn(numericFixture("-5", style: 3, styles: styles)).value == "(5.00)")
    }

    @Test("Backslash-escaped letters in a number format are text, not date parts")
    func escapedLiterals() async throws {
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 166], customFormats: [166: #"0.0\ \k\m"#])
        #expect(try await readSingleColumn(numericFixture("12.5", style: 1, styles: styles)).value == "12.5 km")
    }
}

@MainActor
@Suite("Spreadsheet dates and times")
struct SpreadsheetDateTests {
    @Test("Dates keep their format when the styles part has parts the old decoder rejected")
    func toleratesUnusualStyles() async throws {
        // A conditional-format <dxf> without numFmtId, a custom cell style without
        // builtinId, and a colors part with only mruColors.
        let extra = """
        <cellStyles count="2"><cellStyle name="Normal" xfId="0" builtinId="0"/><cellStyle name="Normal 2" xfId="0"/></cellStyles><dxfs count="1"><dxf><font><color rgb="FF9C0006"/></font><fill><patternFill><bgColor rgb="FFFFC7CE"/></patternFill></fill></dxf></dxfs><colors><mruColors><color rgb="FF00B050"/></mruColors></colors>
        """
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 164], customFormats: [164: "mm/dd/yyyy"], extraXML: extra)
        #expect(try await readSingleColumn(numericFixture("43101", style: 1, styles: styles)).value == "01/01/2018")
    }

    @Test("Built-in and custom date and time formats")
    func dateAndTimeFormats() async throws {
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 15, 20, 46, 31])
        #expect(try await readSingleColumn(numericFixture("43101", style: 1, styles: styles)).value == "1-Jan-18")
        #expect(try await readSingleColumn(numericFixture("0.375", style: 2, styles: styles)).value == "9:00")
        // Elapsed time keeps counting past 24 hours.
        #expect(try await readSingleColumn(numericFixture("1.5625", style: 3, styles: styles)).value == "37:30:00")
        // A built-in East Asian date format is still a date.
        #expect(try await readSingleColumn(numericFixture("45306", style: 4, styles: styles)).value == "1/15/2024")
    }

    @Test("Locale-dependent built-in date formats follow the given locale")
    func localeDateFormats() async throws {
        let styles = XLSXFixture.styles(numberFormatIDs: [0, 14, 22])
        let british = Locale(identifier: "en_GB")
        let date = try await readSingleColumn(numericFixture("45385", style: 1, styles: styles), locale: british).value
        #expect(date == "03/04/2024")
        let dateTime = try await readSingleColumn(numericFixture("45385.4375", style: 2, styles: styles), locale: british).value
        #expect(dateTime?.contains("03/04/2024") == true)
        #expect(dateTime?.contains("10:30") == true)
    }

    @Test("Workbooks using the 1904 date system read the right dates")
    func dateSystem1904() async throws {
        var fixture = numericFixture("0", style: 1, styles: XLSXFixture.styles(numberFormatIDs: [0, 164], customFormats: [164: "yyyy-mm-dd"]))
        fixture.workbookPropertiesAttributes = #"date1904="1""#
        #expect(try await readSingleColumn(fixture).value == "1904-01-01")
    }

    @Test("ISO 8601 date cells are shown as dates")
    func isoDateCells() async throws {
        let fixture = XLSXFixture(
            rowsXML: """
            <row r="1"><c r="A1" t="s"><v>0</v></c></row>
            <row r="2"><c r="A2" t="d" s="1"><v>2024-01-15T00:00:00Z</v></c></row>
            """,
            sharedStrings: ["Joined"],
            stylesXML: XLSXFixture.styles(numberFormatIDs: [0, 14])
        )
        #expect(try await readSingleColumn(fixture).value == "1/15/2024")
    }
}

@MainActor
@Suite("Spreadsheet package structure")
struct SpreadsheetPackageTests {
    @Test("Sheets load when the workbook has relationship types the old decoder didn't know")
    func unknownRelationshipTypes() async throws {
        var fixture = numericFixture("5")
        fixture.extraWorkbookRelationshipsXML = #"<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sheetMetadata" Target="metadata.xml"/>"#
        fixture.extraParts = ["xl/metadata.xml": #"<?xml version="1.0" encoding="UTF-8"?><metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>"#]
        #expect(try await readSingleColumn(fixture).value == "5")
    }

    @Test("Sheets load when the root relationship uses an absolute workbook path")
    func absoluteWorkbookPath() async throws {
        var fixture = numericFixture("6")
        fixture.rootWorkbookTarget = "/xl/workbook.xml"
        #expect(try await readSingleColumn(fixture).value == "6")
    }

    @Test("Chart sheets aren't offered as data sheets")
    func chartSheetsAreExcluded() async throws {
        var fixture = numericFixture("1")
        fixture.extraSheetsXML = #"<sheet name="Chart1" sheetId="2" r:id="rId8"/>"#
        fixture.extraWorkbookRelationshipsXML = #"<Relationship Id="rId8" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet" Target="chartsheets/sheet1.xml"/>"#
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try await ExcelParserService().sheetNames(at: url) == ["Sheet1"])
    }
}

/// Kept separate because the old code crashed the whole test process on this input.
@MainActor
@Suite("Spreadsheet huge numbers")
struct SpreadsheetHugeNumberTests {
    @Test("Whole numbers beyond Int range don't crash")
    func hugeWholeNumbers() async throws {
        let value = try await readSingleColumn(numericFixture("1.2345678901234567E+19")).value
        #expect(value?.hasPrefix("123456789012346") == true)
        #expect(value?.count == 20)
    }
}

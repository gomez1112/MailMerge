import Foundation
import ZIPFoundation
import PDFKit
import SwiftUI
import CoreText
import CoreXLSX
#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif

actor DOCXParserService {
    func parseTemplate(bookmarkData: Data) async throws -> AttributedTemplate {
        #if os(macOS)
        let url = try SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData)
        defer { SecurityScopedAccess.stopAccessing(url) }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        return try await MainActor.run {
            let attributed = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            return AttributedTemplate(value: attributed)
        }
        #else
        throw MergeError.featureUnavailable
        #endif
    }

    func extractPlaceholders(from content: AttributedTemplate) async -> [String] {
        let plainText = await MainActor.run { content.value.string }
        let patterns = ["\\{\\{(.*?)\\}\\}", "<<(.+?)>>", "\\$\\{(.+?)\\}", "\\[\\[(.+?)\\]\\]"]
        var results: Set<String> = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: plainText, range: NSRange(plainText.startIndex..., in: plainText))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                if let range = Range(match.range(at: 1), in: plainText) {
                    results.insert(String(plainText[range]))
                }
            }
        }
        return Array(results).sorted()
    }

    func headerImageData(bookmarkData: Data) async -> Data? {
        #if os(iOS) || os(visionOS)
        return nil
        #else
        guard let url = try? SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData) else {
            return nil
        }
        defer { SecurityScopedAccess.stopAccessing(url) }

        guard let documentRelsData = unzipEntry(from: url, entryPath: "word/_rels/document.xml.rels"),
              let documentRels = String(data: documentRelsData, encoding: .utf8),
              let headerTarget = matchFirstGroup(
                in: documentRels,
                pattern: "<Relationship[^>]*Type=\\\"[^\\\"]*\\/header\\\"[^>]*Target=\\\"([^\\\"]+)\\\""
              ) else {
            return nil
        }

        let headerPath = normalizeDOCXPath("word/" + headerTarget)
        guard let headerData = unzipEntry(from: url, entryPath: headerPath),
              let headerXML = String(data: headerData, encoding: .utf8),
              let embedId = matchFirstGroup(
                in: headerXML,
                pattern: "r:embed=\\\"([^\\\"]+)\\\""
              ) else {
            return nil
        }

        let headerFileName = (headerPath as NSString).lastPathComponent
        let headerRelsPath = "word/_rels/\(headerFileName).rels"
        guard let headerRelsData = unzipEntry(from: url, entryPath: headerRelsPath),
              let headerRelsXML = String(data: headerRelsData, encoding: .utf8),
              let imageTarget = matchFirstGroup(
                in: headerRelsXML,
                pattern: "<Relationship[^>]*Id=\\\"\(NSRegularExpression.escapedPattern(for: embedId))\\\"[^>]*Target=\\\"([^\\\"]+)\\\""
              ) else {
            return nil
        }

        let imagePath = normalizeDOCXPath("word/" + imageTarget)
        return unzipEntry(from: url, entryPath: imagePath)
        #endif
    }

    private func unzipEntry(from url: URL, entryPath: String) -> Data? {
        do {
            let archive = try Archive(url: url, accessMode: .read)
            guard let entry = archive[entryPath] else {
                return nil
            }
            var data = Data()
            _ = try archive.extract(entry, consumer: { chunk in
                data.append(chunk)
            })
            return data
        } catch {
            return nil
        }
    }

    private func matchFirstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[groupRange])
    }

    private func normalizeDOCXPath(_ path: String) -> String {
        var normalized = path.replacingOccurrences(of: "../", with: "")
        if normalized.hasPrefix("/") {
            normalized.removeFirst()
        }
        return normalized
    }
}

actor ExcelParserService {
    func sheetNames(bookmarkData: Data) async throws -> [String] {
        let url = try SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData)
        defer { SecurityScopedAccess.stopAccessing(url) }
        guard let file = XLSXFile(filepath: url.path) else {
            throw MergeError.invalidSpreadsheet
        }
        let workbooks = try file.parseWorkbooks()
        guard let workbook = workbooks.first else {
            throw MergeError.invalidSpreadsheet
        }
        return workbook.sheets.items.compactMap(\.name)
    }

    func previewSheet(bookmarkData: Data, sheetName: String, rowCount: Int) async throws -> SheetData {
        try await loadSheet(bookmarkData: bookmarkData, sheetName: sheetName, rowLimit: rowCount)
    }

    func columnHeaders(bookmarkData: Data, sheetName: String) async throws -> [String] {
        let sheet = try await loadSheet(bookmarkData: bookmarkData, sheetName: sheetName, rowLimit: 1)
        return sheet.headers
    }

    func fullSheet(bookmarkData: Data, sheetName: String) async throws -> SheetData {
        try await loadSheet(bookmarkData: bookmarkData, sheetName: sheetName, rowLimit: nil)
    }

    private func loadSheet(bookmarkData: Data, sheetName: String, rowLimit: Int?) async throws -> SheetData {
        let url = try SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData)
        defer { SecurityScopedAccess.stopAccessing(url) }
        guard let file = XLSXFile(filepath: url.path) else {
            throw MergeError.invalidSpreadsheet
        }
        let sharedStrings = try? file.parseSharedStrings()
        let styles = try? file.parseStyles()
        let workbooks = try file.parseWorkbooks()
        guard let workbook = workbooks.first else {
            throw MergeError.invalidSpreadsheet
        }
        let worksheets = try file.parseWorksheetPathsAndNames(workbook: workbook)
        guard let worksheetPath = worksheets.first(where: { $0.name == sheetName })?.path else {
            throw MergeError.sheetNotFound
        }
        let worksheet = try file.parseWorksheet(at: worksheetPath)
        guard let rows = worksheet.data?.rows, let headerRow = rows.first else {
            throw MergeError.emptySheet
        }

        let headers = valuesForRow(
            headerRow,
            headers: nil,
            sharedStrings: sharedStrings,
            styles: styles,
            minimumCount: nil
        )
        let dataRows = rows.dropFirst()
        var previewRows: [[String]] = []
        for (index, row) in dataRows.enumerated() {
            if let rowLimit, index >= rowLimit { break }
            let values = valuesForRow(
                row,
                headers: headers,
                sharedStrings: sharedStrings,
                styles: styles,
                minimumCount: headers.count
            )
            previewRows.append(values)
        }
        return SheetData(headers: headers, rows: previewRows)
    }

    private func valuesForRow(
        _ row: Row,
        headers: [String]?,
        sharedStrings: SharedStrings?,
        styles: Styles?,
        minimumCount: Int?
    ) -> [String] {
        var values: [Int: String] = [:]
        for cell in row.cells {
            let columnName = cell.reference.column.value
            let index = columnIndex(from: columnName)
            let headerName = headers?.indices.contains(index) == true ? headers?[index] : nil
            let value = cellString(
                cell,
                sharedStrings: sharedStrings,
                styles: styles,
                headerName: headerName
            )
            values[index] = value
        }
        let maxIndex = max(values.keys.max() ?? -1, (minimumCount ?? 0) - 1)
        guard maxIndex >= 0 else { return [] }
        var output = Array(repeating: "", count: maxIndex + 1)
        for (index, value) in values {
            if index < output.count {
                output[index] = value
            }
        }
        return output
    }

    private func columnIndex(from column: String) -> Int {
        var result = 0
        for scalar in column.uppercased().unicodeScalars {
            let offset = Int(scalar.value) - 64
            result = result * 26 + offset
        }
        return max(result - 1, 0)
    }

    private func cellString(
        _ cell: Cell,
        sharedStrings: SharedStrings?,
        styles: Styles?,
        headerName: String?
    ) -> String {
        if cell.type == .inlineStr, let inline = cell.inlineString?.text {
            return inline
        }
        if cell.type == .sharedString, let sharedStrings, let value = cell.stringValue(sharedStrings) {
            if let formatted = formattedStringValue(
                value,
                cell: cell,
                styles: styles,
                headerName: headerName
            ) {
                return formatted
            }
            return normalizeNumericString(value)
        }
        if cell.type == .string, let rawValue = cell.value {
            return rawValue
        }
        guard let rawValue = cell.value else { return "" }
        if let formatted = formattedCellValue(
            rawValue,
            cell: cell,
            styles: styles,
            headerName: headerName
        ) {
            return formatted
        }
        return normalizeNumericString(rawValue)
    }

    private func formattedStringValue(
        _ value: String,
        cell: Cell,
        styles: Styles?,
        headerName: String?
    ) -> String? {
        guard let number = Double(value) else { return nil }
        if cell.type == .date {
            return formatDate(excelDate(from: number), kind: inferredDateKind(for: number), formatCode: "m/d/yy h:mm")
        }
        guard let format = formatCode(for: cell, styles: styles) else {
            if shouldForceTime(headerName: headerName, rawValue: value, number: number) {
                return formatDate(excelDate(from: number), kind: .time, formatCode: "h:mm")
            }
            return formatPlainNumber(number, rawValue: value)
        }
        let formatKind = formatKind(for: format)
        if formatKind == .number, shouldForceTime(headerName: headerName, rawValue: value, number: number) {
            return formatDate(excelDate(from: number), kind: .time, formatCode: "h:mm")
        }
        switch formatKind {
        case .date, .time, .dateTime:
            let date = excelDate(from: number)
            return formatDate(date, kind: formatKind, formatCode: format)
        case .number:
            return formatPlainNumber(number, rawValue: value)
        }
    }

    private func formattedCellValue(
        _ rawValue: String,
        cell: Cell,
        styles: Styles?,
        headerName: String?
    ) -> String? {
        guard let number = Double(rawValue) else { return nil }
        if cell.type == .date {
            return formatDate(excelDate(from: number), kind: inferredDateKind(for: number), formatCode: "m/d/yy h:mm")
        }
        guard let format = formatCode(for: cell, styles: styles) else {
            if shouldForceTime(headerName: headerName, rawValue: rawValue, number: number) {
                return formatDate(excelDate(from: number), kind: .time, formatCode: "h:mm")
            }
            return formatPlainNumber(number, rawValue: rawValue)
        }

        let formatKind = formatKind(for: format)
        if formatKind == .number, shouldForceTime(headerName: headerName, rawValue: rawValue, number: number) {
            return formatDate(excelDate(from: number), kind: .time, formatCode: "h:mm")
        }
        switch formatKind {
        case .date, .time, .dateTime:
            let date = excelDate(from: number)
            return formatDate(date, kind: formatKind, formatCode: format)
        case .number:
            return formatPlainNumber(number, rawValue: rawValue)
        }
    }

    private func formatPlainNumber(_ number: Double, rawValue: String) -> String {
        if number.rounded() == number {
            return String(Int(number))
        }
        return rawValue
    }

    private func formatCode(for cell: Cell, styles: Styles?) -> String? {
        guard let styles,
              let styleIndex = cell.styleIndex,
              let cellFormats = styles.cellFormats?.items,
              styleIndex < cellFormats.count else {
            return nil
        }
        let format = cellFormats[styleIndex]
        let numFmtId = format.numberFormatId
        if let numberFormats = styles.numberFormats?.items,
           let matched = numberFormats.first(where: { $0.id == numFmtId }) {
            return matched.formatCode
        }
        return builtinFormatCode(for: numFmtId)
    }

    private func builtinFormatCode(for numFmtId: Int) -> String? {
        switch numFmtId {
        case 14: return "m/d/yyyy"
        case 15: return "d-mmm-yy"
        case 16: return "d-mmm"
        case 17: return "mmm-yy"
        case 18: return "h:mm AM/PM"
        case 19: return "h:mm:ss AM/PM"
        case 20: return "h:mm"
        case 21: return "h:mm:ss"
        case 22: return "m/d/yyyy h:mm"
        case 45: return "mm:ss"
        case 46: return "[h]:mm:ss"
        case 47: return "mm:ss.0"
        default: return nil
        }
    }

    private enum ExcelFormatKind {
        case date
        case time
        case dateTime
        case number
    }

    private func formatKind(for formatCode: String) -> ExcelFormatKind {
        let sanitized = stripFormatLiterals(formatCode.lowercased())
        let hasHour = sanitized.contains("h")
        let hasSecond = sanitized.contains("s")
        let hasYear = sanitized.contains("y")
        let hasDay = sanitized.contains("d")
        let hasMonth = sanitized.contains("m")

        let hasTime = hasHour || hasSecond
        let hasDate = hasYear || hasDay || (hasMonth && !hasTime)
        if hasDate && hasTime { return .dateTime }
        if hasTime { return .time }
        if hasDate { return .date }
        return .number
    }

    private func stripFormatLiterals(_ format: String) -> String {
        var output = ""
        var isInQuote = false
        var isInBracket = false
        for char in format {
            if char == "\"" {
                isInQuote.toggle()
                continue
            }
            if char == "[" {
                isInBracket = true
                continue
            }
            if char == "]" {
                isInBracket = false
                continue
            }
            if isInQuote || isInBracket { continue }
            output.append(char)
        }
        return output
    }

    private func excelDate(from serial: Double) -> Date {
        let adjustedSerial: Double
        if serial >= 60 {
            adjustedSerial = serial - 1
        } else {
            adjustedSerial = serial
        }
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 1899,
            month: 12,
            day: 31
        )) ?? Date(timeIntervalSince1970: 0)
        return base.addingTimeInterval(adjustedSerial * 86_400)
    }

    private func formatDate(_ date: Date, kind: ExcelFormatKind, formatCode: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale.current
        let upperCode = formatCode.uppercased()
        let includesSeconds = upperCode.contains("S")
        switch kind {
        case .date:
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        case .time:
            formatter.dateStyle = .none
            formatter.dateFormat = upperCode.contains("AM/PM")
                ? (includesSeconds ? "h:mm:ss a" : "h:mm a")
                : (includesSeconds ? "H:mm:ss" : "H:mm")
        case .dateTime:
            formatter.dateStyle = .short
            formatter.dateFormat = upperCode.contains("AM/PM")
                ? (includesSeconds ? "M/d/yy h:mm:ss a" : "M/d/yy h:mm a")
                : (includesSeconds ? "M/d/yy H:mm:ss" : "M/d/yy H:mm")
        case .number:
            return formatPlainNumber(Double(date.timeIntervalSince1970), rawValue: "\(date.timeIntervalSince1970)")
        }
        return formatter.string(from: date)
    }

    private func inferredDateKind(for serial: Double) -> ExcelFormatKind {
        if serial < 1 { return .time }
        if serial.rounded() == serial { return .date }
        return .dateTime
    }

    private func isLikelyTimeHeader(_ headerName: String?) -> Bool {
        guard let headerName else { return false }
        let normalized = headerName.lowercased()
        return normalized.contains("time")
            || normalized.contains("arrival")
            || normalized.contains("departure")
            || normalized.contains("check in")
            || normalized.contains("check-in")
            || normalized.contains("check out")
            || normalized.contains("check-out")
    }

    private func shouldForceTime(headerName: String?, rawValue: String, number: Double) -> Bool {
        guard number > 0, number < 1 else { return false }
        if isLikelyTimeHeader(headerName) { return true }
        if isLikelyPercentHeader(headerName) { return false }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasManyDecimals = trimmed.contains(".") && trimmed.count >= 6
        return hasManyDecimals
    }

    private func isLikelyPercentHeader(_ headerName: String?) -> Bool {
        guard let headerName else { return false }
        let normalized = headerName.lowercased()
        return normalized.contains("percent")
            || normalized.contains("%")
            || normalized.contains("rate")
            || normalized.contains("ratio")
    }

    private func normalizeNumericString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".0"), let number = Double(trimmed), number.rounded() == number {
            return String(Int(number))
        }
        return trimmed
    }
}

final class PDFGeneratorService {
    func generatePDF(
        from attributedString: NSAttributedString,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImageData: Data?
    ) throws -> Data {
        try generatePDF(pages: [attributedString], pageSize: pageSize, margins: margins, headerImageData: headerImageData)
    }

    func generatePDF(
        pages: [NSAttributedString],
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImageData: Data?
    ) throws -> Data {
        try generatePDF(
            pages: AnySequence(pages),
            pageSize: pageSize,
            margins: margins,
            headerImageData: headerImageData
        )
    }

    func generatePDF<S: Sequence>(
        pages: S,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImageData: Data?
    ) throws -> Data where S.Element == NSAttributedString {
        let baseTextRect = CGRect(
            x: margins.leading,
            y: margins.top,
            width: pageSize.width - margins.leading - margins.trailing,
            height: pageSize.height - margins.top - margins.bottom
        )
        let headerImage = headerImageData.flatMap { PlatformImage(data: $0) }
        let headerRect = headerImage.flatMap { headerFrame(for: $0, pageSize: pageSize, margins: margins) }
        let textRect: CGRect
        if let headerRect {
            let topInset = max(baseTextRect.minY, headerRect.maxY + 12)
            textRect = CGRect(
                x: baseTextRect.minX,
                y: topInset,
                width: baseTextRect.width,
                height: max(pageSize.height - topInset - margins.bottom, 0)
            )
        } else {
            textRect = baseTextRect
        }
        let pdfDocument = PDFDocument()
        for page in pages {
#if canImport(AppKit)
            renderAttributedString(
                page,
                pdfDocument: pdfDocument,
                pageSize: pageSize,
                textRect: textRect,
                headerImage: headerImage,
                headerRect: headerRect
            )
#else
            let data = renderAttributedStringData(
                page,
                pageSize: pageSize,
                textRect: textRect,
                headerImage: headerImage,
                headerRect: headerRect
            )
            if let pageDocument = PDFDocument(data: data) {
                for index in 0..<pageDocument.pageCount {
                    if let pdfPage = pageDocument.page(at: index) {
                        pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
                    }
                }
            }
#endif
        }
        guard let data = pdfDocument.dataRepresentation() else {
            throw MergeError.pdfGenerationFailed
        }
        return data
    }

    #if canImport(AppKit)
    private func renderAttributedString(
        _ attributedString: NSAttributedString,
        pdfDocument: PDFDocument,
        pageSize: CGSize,
        textRect: CGRect,
        headerImage: PlatformImage?,
        headerRect: CGRect?
    ) {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            let textContainer = NSTextContainer(size: textRect.size)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            if glyphRange.length == 0 {
                break
            }

            let viewFrame = CGRect(origin: .zero, size: pageSize)
            let drawOrigin = CGPoint(x: textRect.minX, y: textRect.minY)
            let pageView = PDFTextPageView(
                frame: viewFrame,
                layoutManager: layoutManager,
                textContainer: textContainer,
                glyphRange: glyphRange,
                textOrigin: drawOrigin,
                headerImage: headerImage,
                headerRect: headerRect
            )
            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            if let pageDocument = PDFDocument(data: pageData),
               let pdfPage = pageDocument.page(at: 0) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }

            glyphIndex = NSMaxRange(glyphRange)
        }
    }
    #else
    private func renderAttributedStringData(
        _ attributedString: NSAttributedString,
        pageSize: CGSize,
        textRect: CGRect,
        headerImage: PlatformImage?,
        headerRect: CGRect?
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            let textStorage = NSTextStorage(attributedString: attributedString)
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)

            var glyphIndex = 0
            var isFirstPage = true
            while glyphIndex < layoutManager.numberOfGlyphs {
                if isFirstPage {
                    isFirstPage = false
                } else {
                    context.beginPage()
                }

                if let headerImage, let headerRect {
                    headerImage.draw(in: headerRect)
                }

                let textContainer = NSTextContainer(size: textRect.size)
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)

                let glyphRange = layoutManager.glyphRange(for: textContainer)
                if glyphRange.length == 0 { break }
                let drawOrigin = CGPoint(x: textRect.minX, y: textRect.minY)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: drawOrigin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawOrigin)

                glyphIndex = NSMaxRange(glyphRange)
            }
        }
    }
    #endif

    private func headerFrame(for image: PlatformImage, pageSize: CGSize, margins: EdgeInsets) -> CGRect {
        let maxWidth = pageSize.width - margins.leading - margins.trailing
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let scale = maxWidth / imageSize.width
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = margins.leading
        let y: CGFloat = 0
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
#if canImport(AppKit)
private final class PDFTextPageView: NSView {
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let glyphRange: NSRange
    private let textOrigin: CGPoint
    private let headerImage: PlatformImage?
    private let headerRect: CGRect?

    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        glyphRange: NSRange,
        textOrigin: CGPoint,
        headerImage: PlatformImage?,
        headerRect: CGRect?
    ) {
        self.layoutManager = layoutManager
        self.textContainer = textContainer
        self.glyphRange = glyphRange
        self.textOrigin = textOrigin
        self.headerImage = headerImage
        self.headerRect = headerRect
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let headerImage, let headerRect {
            headerImage.draw(in: headerRect)
        }
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: textOrigin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)
    }
}
#endif

final class MergeEngine {
    private let docxParser: DOCXParserService
    private let excelParser: ExcelParserService
    private let pdfGenerator: PDFGeneratorService

    init(docxParser: DOCXParserService, excelParser: ExcelParserService, pdfGenerator: PDFGeneratorService) {
        self.docxParser = docxParser
        self.excelParser = excelParser
        self.pdfGenerator = pdfGenerator
    }

    func analyzeTemplate(bookmarkData: Data) async throws -> [String] {
        let content = try await docxParser.parseTemplate(bookmarkData: bookmarkData)
        return await docxParser.extractPlaceholders(from: content)
    }

    func getSheetNames(bookmarkData: Data) async throws -> [String] {
        try await excelParser.sheetNames(bookmarkData: bookmarkData)
    }

    func getSheetPreview(bookmarkData: Data, sheetName: String, rowCount: Int) async throws -> SheetData {
        try await excelParser.previewSheet(bookmarkData: bookmarkData, sheetName: sheetName, rowCount: rowCount)
    }

    func getColumnHeaders(bookmarkData: Data, sheetName: String) async throws -> [String] {
        try await excelParser.columnHeaders(bookmarkData: bookmarkData, sheetName: sheetName)
    }

    func generatePreview(job: MailMergeJob, recordIndex: Int) async throws -> (data: Data, totalRecords: Int) {
        guard let templateBookmarkData = job.templateBookmarkData else {
            throw MergeError.invalidTemplate
        }
        guard let dataBookmarkData = job.dataSourceBookmarkData,
              let sheetName = job.selectedSheetName else {
            throw MergeError.invalidSpreadsheet
        }

        let templateText = try await docxParser.parseTemplate(bookmarkData: templateBookmarkData)
        let headerImageData = await docxParser.headerImageData(bookmarkData: templateBookmarkData)
        let sheet = try await excelParser.fullSheet(bookmarkData: dataBookmarkData, sheetName: sheetName)
        let dataRows = filteredRows(sheet.rows)
        let totalRecords = dataRows.count
        guard totalRecords > 0 else {
            throw MergeError.noRecords
        }

        let safeIndex = max(0, min(recordIndex, totalRecords - 1))
        let row = dataRows[safeIndex]
        let mappingSnapshots = job.fieldMappings.map { MappingSnapshot(from: $0) }
        let rowData = buildRowData(headers: sheet.headers, row: row)
        let attributedString = applyMappings(templateText: templateText.value, rowData: rowData, mappings: mappingSnapshots)
        let data = try await MainActor.run {
            try pdfGenerator.generatePDF(
                from: attributedString,
                pageSize: CGSize(width: 612, height: 792),
                margins: EdgeInsets(top: 48, leading: 48, bottom: 48, trailing: 48),
                headerImageData: headerImageData
            )
        }
        return (data, totalRecords)
    }

    func performMerge(
        job: MailMergeJob,
        singleDocument: Bool,
        progress: @escaping @Sendable @MainActor (Int, Int) -> Void
    ) async throws -> MergeResult {
        let start = Date()
        guard let templateBookmarkData = job.templateBookmarkData else {
            throw MergeError.invalidTemplate
        }
        guard let dataBookmarkData = job.dataSourceBookmarkData,
              let sheetName = job.selectedSheetName else {
            throw MergeError.invalidSpreadsheet
        }
        guard let outputBookmarkData = job.outputFolderBookmarkData else {
            throw MergeError.outputAccessDenied
        }

        await MainActor.run {
            job.status = .running
            job.lastRunDate = Date()
            job.lastRunRecordCount = nil
        }

        do {
            let templateText = try await docxParser.parseTemplate(bookmarkData: templateBookmarkData)
            let headerImageData = await docxParser.headerImageData(bookmarkData: templateBookmarkData)
            let sheet = try await excelParser.fullSheet(bookmarkData: dataBookmarkData, sheetName: sheetName)
            let dataRows = filteredRows(sheet.rows)
            let totalRecords = dataRows.count
            guard totalRecords > 0 else { throw MergeError.noRecords }

            let mappings = job.fieldMappings.map { MappingSnapshot(from: $0) }
            let jobName = job.name
            let filePattern = job.outputFileNamePattern
            let pageSize = CGSize(width: 612, height: 792)
            let margins = EdgeInsets(top: 48, leading: 48, bottom: 48, trailing: 48)

            let outputURL: URL?
            let attachmentURL: URL?
            let outputFolderURL = try SecurityScopedAccess.startAccessing(bookmarkData: outputBookmarkData)
            defer { SecurityScopedAccess.stopAccessing(outputFolderURL) }
            if singleDocument {
                var index = 0
                let pages = AnySequence<NSAttributedString> {
                    AnyIterator {
                        guard index < dataRows.count else { return nil }
                        let row = dataRows[index]
                        let rowData = self.buildRowData(headers: sheet.headers, row: row)
                        let mergedText = self.applyMappings(
                            templateText: templateText.value,
                            rowData: rowData,
                            mappings: mappings
                        )
                        index += 1
                        Task { @MainActor in
                            progress(index, totalRecords)
                        }
                        return mergedText
                    }
                }
                let data = try await MainActor.run {
                    try pdfGenerator.generatePDF(
                        pages: pages,
                        pageSize: pageSize,
                        margins: margins,
                        headerImageData: headerImageData
                    )
                }
                let filename = sanitizeFileName("Merged_\(jobName)").appending(".pdf")
                let fileURL = outputFolderURL.appending(path: filename)
                try data.write(to: fileURL)
                outputURL = fileURL
                attachmentURL = fileURL
            } else {
                var outputFiles: [URL] = []
                var lastOutput: URL? = nil
                for (index, row) in dataRows.enumerated() {
                    let rowData = buildRowData(headers: sheet.headers, row: row)
                    let attributed = applyMappings(templateText: templateText.value, rowData: rowData, mappings: mappings)
                    let data = try await MainActor.run {
                        try pdfGenerator.generatePDF(
                            from: attributed,
                            pageSize: pageSize,
                            margins: margins,
                            headerImageData: headerImageData
                        )
                    }
                    let fileName = outputFileName(
                        pattern: filePattern,
                        rowIndex: index + 1,
                        rowData: rowData
                    )
                    let fileURL = outputFolderURL.appending(path: fileName)
                    try data.write(to: fileURL)
                    lastOutput = fileURL
                    outputFiles.append(fileURL)
                    await MainActor.run {
                        progress(index + 1, totalRecords)
                    }
                }
                outputURL = lastOutput
                attachmentURL = try createZipAttachment(
                    files: outputFiles,
                    jobName: jobName
                )
            }

            let duration = Date().timeIntervalSince(start)
            await MainActor.run {
                job.status = .completed
                job.lastRunDate = Date()
                job.lastRunRecordCount = totalRecords
            }
            return MergeResult(
                outputURL: outputURL,
                attachmentURL: attachmentURL,
                recordCount: totalRecords,
                duration: duration
            )
        } catch {
            await MainActor.run {
                job.status = .failed
                job.lastRunDate = Date()
                job.lastRunRecordCount = nil
            }
            throw error
        }
    }

    private func applyMappings(
        templateText: NSAttributedString,
        rowData: [String: String],
        mappings: [MappingSnapshot]
    ) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: templateText)
        for mapping in mappings {
            guard let columnName = mapping.columnName else { continue }
            let rawValue = rowData[columnName] ?? ""
            let transformed = mapping.transformation.apply(to: rawValue, formatString: mapping.formatString)
            for placeholder in placeholderVariants(for: mapping.placeholderText) {
                replaceAllOccurrences(in: output, placeholder: placeholder, replacement: transformed)
            }
            for pattern in placeholderRegexVariants(for: mapping.placeholderText) {
                replaceAllRegexOccurrences(in: output, pattern: pattern, replacement: transformed)
            }
        }
        // Strip any remaining placeholder tokens (unmapped fields) so they
        // don't appear as raw {{...}}, <<...>>, ${...}, or [[...]] in the output.
        for pattern in ["\\{\\{.*?\\}\\}", "<<.*?>>", "\\$\\{.*?\\}", "\\[\\[.*?\\]\\]"] {
            replaceAllRegexOccurrences(in: output, pattern: pattern, replacement: "")
        }
        return output
    }

    private func buildRowData(headers: [String], row: [String]) -> [String: String] {
        var data: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            let value = index < row.count ? row[index] : ""
            data[header] = value
        }
        return data
    }

    private func filteredRows(_ rows: [[String]]) -> [[String]] {
        rows.filter { row in
            row.contains { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }

    private func outputFileName(pattern: String, rowIndex: Int, rowData: [String: String]) -> String {
        var fileName = pattern.replacingOccurrences(of: "{Row}", with: "\(rowIndex)")
        for (key, value) in rowData {
            fileName = fileName.replacingOccurrences(of: "{\(key)}", with: value)
        }
        let sanitized = sanitizeFileName(fileName)
        return sanitized.hasSuffix(".pdf") ? sanitized : "\(sanitized).pdf"
    }

    private func replaceAllOccurrences(
        in attributedString: NSMutableAttributedString,
        placeholder: String,
        replacement: String
    ) {
        guard !placeholder.isEmpty else { return }
        var searchRange = NSRange(location: 0, length: attributedString.length)
        while true {
            let foundRange = (attributedString.string as NSString).range(of: placeholder, options: [], range: searchRange)
            if foundRange.location == NSNotFound { break }
            let attributes = attributedString.attributes(at: foundRange.location, effectiveRange: nil)
            let replacementString = NSAttributedString(string: replacement, attributes: attributes)
            attributedString.replaceCharacters(in: foundRange, with: replacementString)
            let nextLocation = foundRange.location + replacementString.length
            if nextLocation >= attributedString.length { break }
            searchRange = NSRange(location: nextLocation, length: attributedString.length - nextLocation)
        }
    }

    private func replaceAllRegexOccurrences(
        in attributedString: NSMutableAttributedString,
        pattern: String,
        replacement: String
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return
        }
        let fullRange = NSRange(location: 0, length: attributedString.length)
        let matches = regex.matches(in: attributedString.string, range: fullRange).reversed()
        for match in matches {
            let range = match.range
            guard range.location != NSNotFound else { continue }
            let attributes = attributedString.attributes(at: range.location, effectiveRange: nil)
            let replacementString = NSAttributedString(string: replacement, attributes: attributes)
            attributedString.replaceCharacters(in: range, with: replacementString)
        }
    }

    private func placeholderVariants(for placeholder: String) -> [String] {
        let base = normalizedPlaceholder(placeholder)
        guard !base.isEmpty else { return [] }
        // Only include the full wrapped forms. Never match the bare field name,
        // as it would match inside e.g. {{First Name}} replacing just "First Name"
        // with the value and leaving orphaned {{ }} in the output.
        var variants: [String] = [
            "{{\(base)}}",
            "<<\(base)>>",
            "${\(base)}",
            "[[\(base)]]"
        ]
        // If the stored placeholder already contains wrapping (e.g. stored as
        // "{{First Name}}" from an older code path), include it too.
        if placeholder != base {
            variants.insert(placeholder, at: 0)
        }
        return variants
    }

    private func placeholderRegexVariants(for placeholder: String) -> [String] {
        let base = normalizedPlaceholder(placeholder)
        guard !base.isEmpty else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: base)
        return [
            "\\{\\{\\s*\(escaped)\\s*\\}\\}",
            "<<\\s*\(escaped)\\s*>>",
            "\\$\\{\\s*\(escaped)\\s*\\}",
            "\\[\\[\\s*\(escaped)\\s*\\]\\]"
        ]
    }

    private func normalizedPlaceholder(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: [(String, String)] = [("{{", "}}"), ("<<", ">>"), ("${", "}"), ("[[", "]]"), ("(", ")")]
        var didStrip = true
        while didStrip {
            didStrip = false
            for (open, close) in wrappers {
                if trimmed.hasPrefix(open), trimmed.hasSuffix(close), trimmed.count >= open.count + close.count + 1 {
                    trimmed = String(trimmed.dropFirst(open.count).dropLast(close.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    didStrip = true
                    break
                }
            }
        }
        return trimmed
    }

    private func sanitizeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let components = value.components(separatedBy: invalidCharacters)
        return components.joined(separator: "_")
    }

    private func createZipAttachment(files: [URL], jobName: String) throws -> URL? {
        guard !files.isEmpty else { return nil }
        let zipName = sanitizeFileName("Merged_\(jobName)").appending(".zip")
        let zipURL = FileManager.default.temporaryDirectory.appending(path: zipName)
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try? FileManager.default.removeItem(at: zipURL)
        }
        let archive = try Archive(url: zipURL, accessMode: .create)
        for file in files {
            try archive.addEntry(
                with: file.lastPathComponent,
                relativeTo: file.deletingLastPathComponent()
            )
        }
        return zipURL
    }
}

private struct MappingSnapshot: Sendable {
    let placeholderText: String
    let columnName: String?
    let transformation: FieldTransformation
    let formatString: String?

    init(from mapping: FieldMapping) {
        placeholderText = mapping.placeholderText
        columnName = mapping.columnName
        transformation = mapping.transformation
        formatString = mapping.formatString
    }
}

struct AttributedTemplate: @unchecked Sendable {
    let value: NSAttributedString
}

final class ServiceContainer {
    static let shared = ServiceContainer()

    let docxParser = DOCXParserService()
    let excelParser = ExcelParserService()
    let pdfGenerator = PDFGeneratorService()
    let mergeEngine: MergeEngine

    private init() {
        mergeEngine = MergeEngine(docxParser: docxParser, excelParser: excelParser, pdfGenerator: pdfGenerator)
    }
}

struct ServiceContainerKey: EnvironmentKey {
    static var defaultValue: ServiceContainer = .shared
}

extension EnvironmentValues {
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}

enum SecurityScopedAccess {
    nonisolated static func startAccessing(bookmarkData: Data) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            throw MergeError.staleBookmark
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw MergeError.securityScopeUnavailable
        }
        return url
        #else
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            throw MergeError.staleBookmark
        }
        return url
        #endif
    }

    nonisolated static func stopAccessing(_ url: URL) {
        #if os(macOS)
        url.stopAccessingSecurityScopedResource()
        #endif
    }
}

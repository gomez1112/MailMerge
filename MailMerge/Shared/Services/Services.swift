import Foundation
import ZIPFoundation
import PDFKit
import SwiftUI
import CoreText
import CoreXLSX
import AppKit

actor DOCXParserService {
    func parseTemplate(bookmarkData: Data) async throws -> AttributedTemplate {
        let url = try SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData)
        defer { SecurityScopedAccess.stopAccessing(url) }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        return try await MainActor.run {
            let attributed = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            return AttributedTemplate(value: attributed)
        }
    }

    func extractPlaceholders(from content: AttributedTemplate) async -> [String] {
        let plainText = await MainActor.run { content.value.string }
        let patterns = ["\\{\\{(.*?)\\}\\}", "<<(.+?)>>", "\\$\\{(.+?)\\}", "\\[\\[(.+?)\\]\\]"]
        var results: Set<String> = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: plainText, range: NSRange(plainText.startIndex..., in: plainText))
            for match in matches {
                if let range = Range(match.range, in: plainText) {
                    results.insert(String(plainText[range]))
                }
            }
        }
        return Array(results).sorted()
    }

    func headerImageData(bookmarkData: Data) async -> Data? {
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

        let headers = valuesForRow(headerRow, sharedStrings: sharedStrings, minimumCount: nil)
        let dataRows = rows.dropFirst()
        var previewRows: [[String]] = []
        for (index, row) in dataRows.enumerated() {
            if let rowLimit, index >= rowLimit { break }
            let values = valuesForRow(row, sharedStrings: sharedStrings, minimumCount: headers.count)
            previewRows.append(values)
        }
        return SheetData(headers: headers, rows: previewRows)
    }

    private func valuesForRow(_ row: Row, sharedStrings: SharedStrings?, minimumCount: Int?) -> [String] {
        var values: [Int: String] = [:]
        for cell in row.cells {
            let columnName = cell.reference.column.value
            let index = columnIndex(from: columnName)
            let value = cellString(cell, sharedStrings: sharedStrings)
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

    private func cellString(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if let sharedStrings, let value = cell.stringValue(sharedStrings) {
            return value
        }
        return cell.value ?? ""
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
        let baseTextRect = CGRect(
            x: margins.leading,
            y: margins.top,
            width: pageSize.width - margins.leading - margins.trailing,
            height: pageSize.height - margins.top - margins.bottom
        )
        let headerImage = headerImageData.flatMap { NSImage(data: $0) }
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
            renderAttributedString(
                page,
                pdfDocument: pdfDocument,
                pageSize: pageSize,
                textRect: textRect,
                headerImage: headerImage,
                headerRect: headerRect
            )
        }
        guard let data = pdfDocument.dataRepresentation() else {
            throw MergeError.pdfGenerationFailed
        }
        return data
    }

    private func renderAttributedString(
        _ attributedString: NSAttributedString,
        pdfDocument: PDFDocument,
        pageSize: CGSize,
        textRect: CGRect,
        headerImage: NSImage?,
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

    private func headerFrame(for image: NSImage, pageSize: CGSize, margins: EdgeInsets) -> CGRect {
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

private final class PDFTextPageView: NSView {
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let glyphRange: NSRange
    private let textOrigin: CGPoint
    private let headerImage: NSImage?
    private let headerRect: CGRect?

    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        glyphRange: NSRange,
        textOrigin: CGPoint,
        headerImage: NSImage?,
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

        job.status = .running
        job.lastRunDate = Date()
        job.lastRunRecordCount = nil

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
            let outputFolderURL = try SecurityScopedAccess.startAccessing(bookmarkData: outputBookmarkData)
            defer { SecurityScopedAccess.stopAccessing(outputFolderURL) }
            if singleDocument {
                var pages: [NSAttributedString] = []
                for (index, row) in dataRows.enumerated() {
                    let rowData = buildRowData(headers: sheet.headers, row: row)
                    let mergedText = applyMappings(templateText: templateText.value, rowData: rowData, mappings: mappings)
                    pages.append(mergedText)
                    await MainActor.run {
                        progress(index + 1, totalRecords)
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
                let fileURL = outputFolderURL.appendingPathComponent(filename)
                try data.write(to: fileURL)
                outputURL = fileURL
            } else {
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
                    let fileURL = outputFolderURL.appendingPathComponent(fileName)
                    try data.write(to: fileURL)
                    lastOutput = fileURL
                    await MainActor.run {
                        progress(index + 1, totalRecords)
                    }
                }
                outputURL = lastOutput
            }

            let duration = Date().timeIntervalSince(start)
            job.status = .completed
            job.lastRunDate = Date()
            job.lastRunRecordCount = totalRecords
            return MergeResult(outputURL: outputURL, recordCount: totalRecords, duration: duration)
        } catch {
            job.status = .failed
            job.lastRunDate = Date()
            job.lastRunRecordCount = nil
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
            replaceAllOccurrences(in: output, placeholder: mapping.placeholderText, replacement: transformed)
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

    private func sanitizeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let components = value.components(separatedBy: invalidCharacters)
        return components.joined(separator: "_")
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
    }

    nonisolated static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

import Foundation
import ZIPFoundation
import PDFKit
import SwiftUI
import CoreText
import AppKit

typealias PlatformImage = NSImage

actor DOCXParserService {
    func parseTemplate(bookmarkData: Data) async throws -> AttributedTemplate {
        let url = try SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData)
        defer { SecurityScopedAccess.stopAccessing(url) }
        return try await parseTemplate(at: url)
    }

    /// Reads the template's text along with its paper size and margins.
    func parseTemplate(at url: URL) async throws -> AttributedTemplate {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        let layout = (try? DOCXPackage(url: url))?.pageLayout()
        return try await MainActor.run {
            let text = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            return AttributedTemplate(value: text, pageSize: layout?.pageSize, margins: layout?.margins)
        }
    }

    func extractPlaceholders(from content: AttributedTemplate) async -> [String] {
        let plainText = await MainActor.run { content.value.string }
        return TemplatePlaceholders.fieldNames(in: plainText)
    }

    /// The picture in the template's page header, if any. A template that can't be
    /// opened has no header picture; reading its text reports the error.
    func headerImage(bookmarkData: Data) async -> DOCXHeaderImage? {
        guard let url = try? SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData) else {
            return nil
        }
        defer { SecurityScopedAccess.stopAccessing(url) }
        return headerImage(at: url)
    }

    func headerImage(at url: URL) -> DOCXHeaderImage? {
        (try? DOCXPackage(url: url))?.headerImage()
    }
}

actor ExcelParserService {
    func sheetNames(bookmarkData: Data) async throws -> [String] {
        let url = try SecurityScopedAccess.startAccessing(bookmarkData: bookmarkData)
        defer { SecurityScopedAccess.stopAccessing(url) }
        return try sheetNames(at: url)
    }

    /// Names of the workbook's data sheets, in workbook order.
    func sheetNames(at url: URL) throws -> [String] {
        try XLSXPackageReader(url: url).sheets.map(\.name)
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
        return try loadSheet(at: url, sheetName: sheetName, rowLimit: rowLimit)
    }

    /// Reads a sheet from an already-accessible file URL. The caller is responsible
    /// for any security-scoped access the URL requires.
    ///
    /// The header row is the first row with any text, so blank formatted rows above a
    /// table are skipped. Values are the text Excel displays, formatted for `locale`.
    func loadSheet(at url: URL, sheetName: String, rowLimit: Int?, locale: Locale = .current) throws -> SheetData {
        let reader = try XLSXPackageReader(url: url)
        guard let sheet = reader.sheets.first(where: { $0.name == sheetName }) else {
            throw MergeError.sheetNotFound
        }
        let sharedStrings = try reader.sharedStrings()
        let styles = reader.styles()
        let formatter = ExcelValueFormatter(locale: locale, usesDate1904: reader.usesDate1904)
        let rows = try reader.rows(inSheetAt: sheet.path)

        func values(of row: XLSXRow, minimumCount: Int) -> [String] {
            let count = max((row.cells.map(\.column).max() ?? -1) + 1, minimumCount)
            var values = Array(repeating: "", count: count)
            for cell in row.cells {
                values[cell.column] = formatter.displayString(for: cell, sharedStrings: sharedStrings, styles: styles)
            }
            return values
        }

        var headers: [String]?
        var dataRows: [[String]] = []
        for row in rows {
            guard let currentHeaders = headers else {
                let candidate = values(of: row, minimumCount: 0)
                if candidate.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    headers = candidate
                }
                continue
            }
            if let rowLimit, dataRows.count >= rowLimit { break }
            dataRows.append(values(of: row, minimumCount: currentHeaders.count))
        }
        guard let headers else {
            throw MergeError.emptySheet
        }
        return SheetData(headers: headers, rows: dataRows)
    }
}

@MainActor
final class PDFGeneratorService {
    func generatePDF(
        from attributedString: NSAttributedString,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImageData: Data?
    ) throws -> Data {
        try generatePDF(
            pages: [attributedString],
            pageSize: pageSize,
            margins: margins,
            headerImage: headerImageData.map { DOCXHeaderImage(data: $0, size: nil) }
        )
    }

    func generatePDF(
        from attributedString: NSAttributedString,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImage: DOCXHeaderImage?
    ) throws -> Data {
        try generatePDF(pages: [attributedString], pageSize: pageSize, margins: margins, headerImage: headerImage)
    }
    
    /// Async version of generatePDF that yields cooperatively during processing
    func generatePDFAsync(
        from attributedString: NSAttributedString,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImage: DOCXHeaderImage?
    ) async throws -> Data {
        // Yield before starting to allow UI to update
        await Task.yield()
        
        let data = try generatePDF(
            from: attributedString,
            pageSize: pageSize,
            margins: margins,
            headerImage: headerImage
        )
        
        // Yield after completion to allow UI to process the result
        await Task.yield()
        
        return data
    }
    
    /// Async version for multiple pages with cooperative yielding
    func generatePDFAsync<S: Sequence>(
        pages: S,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImage: DOCXHeaderImage?
    ) async throws -> Data where S.Element == NSAttributedString {
        await Task.yield()
        
        let data = try generatePDF(
            pages: pages,
            pageSize: pageSize,
            margins: margins,
            headerImage: headerImage
        )
        
        await Task.yield()
        
        return data
    }

    func generatePDF<S: Sequence>(
        pages: S,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImage headerPicture: DOCXHeaderImage?
    ) throws -> Data where S.Element == NSAttributedString {
        let baseTextRect = CGRect(
            x: margins.leading,
            y: margins.top,
            width: pageSize.width - margins.leading - margins.trailing,
            height: pageSize.height - margins.top - margins.bottom
        )
        let headerImage = headerPicture.flatMap { PlatformImage(data: $0.data) }
        let headerRect = headerImage.map { image in
            Self.headerFrame(imageSize: headerPicture?.size ?? image.size, pageSize: pageSize, margins: margins)
        }
        let textRect: CGRect
        if let headerRect, !headerRect.isEmpty {
            let topInset = max(baseTextRect.minY, headerRect.maxY + 12)
            textRect = CGRect(
                x: baseTextRect.minX,
                y: topInset,
                width: baseTextRect.width,
                // A zero-height container would lay all text out below the page.
                height: max(pageSize.height - topInset - margins.bottom, Self.minimumTextHeight)
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

    /// Word's default distance from the top of the paper to the header: half an inch.
    static let headerTopInset: CGFloat = 36
    static let minimumTextHeight: CGFloat = 72

    /// Where the header picture goes: at its own size, scaled down only to fit within the
    /// text width and a quarter of the page height, at the top-left of the header area.
    static func headerFrame(imageSize: CGSize, pageSize: CGSize, margins: EdgeInsets) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let maxWidth = max(pageSize.width - margins.leading - margins.trailing, 1)
        let maxHeight = pageSize.height / 4
        let scale = min(1, maxWidth / imageSize.width, maxHeight / imageSize.height)
        return CGRect(
            x: margins.leading,
            y: min(headerTopInset, margins.top),
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}
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
        let headerImage = await docxParser.headerImage(bookmarkData: templateBookmarkData)
        let sheet = try await excelParser.fullSheet(bookmarkData: dataBookmarkData, sheetName: sheetName)
        let dataRows = filteredRows(sheet.rows)
        let totalRecords = dataRows.count
        guard totalRecords > 0 else {
            throw MergeError.noRecords
        }
        let page = Self.pageSetup(for: templateText)

        let safeIndex = max(0, min(recordIndex, totalRecords - 1))
        let row = dataRows[safeIndex]
        let mappingSnapshots = job.fieldMappings.map { MappingSnapshot(from: $0) }
        let rowData = Self.rowData(headers: sheet.headers, row: row)
        let attributedString = Self.merge(template: templateText.value, rowData: rowData, mappings: mappingSnapshots)
        
        // Use async version for better UI responsiveness
        let data = try await pdfGenerator.generatePDFAsync(
            from: attributedString,
            pageSize: page.size,
            margins: page.margins,
            headerImage: headerImage
        )
        return (data, totalRecords)
    }

    func performMerge(
        job: MailMergeJob,
        singleDocument: Bool,
        progress: @escaping @Sendable @MainActor (Int, Int) -> Void,
        nsProgress: Progress? = nil
    ) async throws -> MergeResult {
        let start = Date()
        
        // Prevent system sleep/app nap during long-running merge
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Performing mail merge operation"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }
        
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
            let headerImage = await docxParser.headerImage(bookmarkData: templateBookmarkData)
            let sheet = try await excelParser.fullSheet(bookmarkData: dataBookmarkData, sheetName: sheetName)
            let dataRows = filteredRows(sheet.rows)
            let totalRecords = dataRows.count
            guard totalRecords > 0 else { throw MergeError.noRecords }
            
            // Set up NSProgress if provided
            let progressTracker = nsProgress ?? Progress(totalUnitCount: Int64(totalRecords))
            progressTracker.localizedDescription = "Merging documents"
            progressTracker.localizedAdditionalDescription = "Processing 0 of \(totalRecords) records"

            let mappings = job.fieldMappings.map { MappingSnapshot(from: $0) }
            let jobName = job.name
            let filePattern = job.outputFileNamePattern
            let page = Self.pageSetup(for: templateText)
            let pageSize = page.size
            let margins = page.margins

            let outputURL: URL?
            let attachmentURL: URL?
            let outputFolderURL = try SecurityScopedAccess.startAccessing(bookmarkData: outputBookmarkData)
            defer { SecurityScopedAccess.stopAccessing(outputFolderURL) }
            
            // Update UI every 10 records or 0.1 seconds to avoid overwhelming the main thread
            let progressUpdateInterval = max(1, totalRecords / 100) // Update ~100 times total
            var lastProgressUpdate = Date()
            
            if singleDocument {
                // For single document mode, we need to generate all pages at once
                // But we can still yield between data preparation and PDF generation
                var attributedPages: [NSAttributedString] = []
                
                for (index, row) in dataRows.enumerated() {
                    // Check for cancellation
                    if progressTracker.isCancelled {
                        throw CancellationError()
                    }
                    
                    let rowData = Self.rowData(headers: sheet.headers, row: row)
                    let mergedText = Self.merge(
                        template: templateText.value,
                        rowData: rowData,
                        mappings: mappings
                    )
                    attributedPages.append(mergedText)
                    
                    let currentIndex = index + 1
                    let shouldUpdate = currentIndex % progressUpdateInterval == 0 
                        || currentIndex == totalRecords 
                        || Date().timeIntervalSince(lastProgressUpdate) > 0.1
                    
                    if shouldUpdate {
                        lastProgressUpdate = Date()
                        await MainActor.run {
                            progress(currentIndex, totalRecords)
                            progressTracker.completedUnitCount = Int64(currentIndex)
                            progressTracker.localizedAdditionalDescription = "Preparing \(currentIndex) of \(totalRecords) records"
                        }
                        // Yield to allow UI updates
                        await Task.yield()
                    }
                }
                
                // Generate the combined PDF with cooperative yielding
                await MainActor.run {
                    progressTracker.localizedAdditionalDescription = "Generating combined PDF..."
                }
                
                let data = try await pdfGenerator.generatePDFAsync(
                    pages: attributedPages,
                    pageSize: pageSize,
                    margins: margins,
                    headerImage: headerImage
                )
                
                let filename = Self.combinedFileName(jobName: jobName)
                let fileURL = outputFolderURL.appending(path: filename)
                try data.write(to: fileURL)
                outputURL = fileURL
                attachmentURL = fileURL
            } else {
                var outputFiles: [URL] = []
                var usedFileNames: Set<String> = []
                var lastOutput: URL? = nil
                var lastProgressUpdate = Date()
                
                // Process documents with explicit yielding to keep UI responsive
                for (index, row) in dataRows.enumerated() {
                    // Check for cancellation before each row
                    if progressTracker.isCancelled {
                        throw CancellationError()
                    }
                    
                    // Yield before processing each document to keep UI responsive
                    await Task.yield()
                    
                    // Prepare the data (fast, can stay on current task)
                    let rowData = Self.rowData(headers: sheet.headers, row: row)
                    let attributed = Self.merge(template: templateText.value, rowData: rowData, mappings: mappings)
                    
                    // Generate PDF with cooperative yielding
                    let data = try await pdfGenerator.generatePDFAsync(
                        from: attributed,
                        pageSize: pageSize,
                        margins: margins,
                        headerImage: headerImage
                    )
                    
                    let fileName = Self.outputFileName(
                        pattern: filePattern,
                        rowIndex: index + 1,
                        rowData: rowData,
                        usedNames: &usedFileNames
                    )
                    let fileURL = outputFolderURL.appending(path: fileName)
                    try data.write(to: fileURL)
                    lastOutput = fileURL
                    outputFiles.append(fileURL)
                    
                    // Update progress
                    let currentIndex = index + 1
                    let shouldUpdate = currentIndex % progressUpdateInterval == 0 
                        || currentIndex == totalRecords 
                        || Date().timeIntervalSince(lastProgressUpdate) > 0.1
                    
                    if shouldUpdate {
                        lastProgressUpdate = Date()
                        await MainActor.run {
                            progress(currentIndex, totalRecords)
                            progressTracker.completedUnitCount = Int64(currentIndex)
                            progressTracker.localizedAdditionalDescription = "Processing \(currentIndex) of \(totalRecords) records"
                        }
                        // Explicit yield after UI update to allow rendering
                        await Task.yield()
                        // Add a small suspension to force RunLoop processing
                        try? await Task.sleep(for: .milliseconds(1))
                    } else {
                        // Still update NSProgress without UI update, but yield periodically
                        progressTracker.completedUnitCount = Int64(currentIndex)
                        // Yield every few documents even when not updating UI
                        if currentIndex % 3 == 0 {
                            await Task.yield()
                        }
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


    /// Fills a template with one record's values.
    ///
    /// Every placeholder in the template is replaced in a single pass, so text that comes
    /// from the data, even if it looks like a placeholder, is never replaced again.
    /// Placeholders without a mapped column are removed. Replacements keep the formatting
    /// of the placeholder they replace.
    static func merge(
        template: NSAttributedString,
        rowData: [String: String],
        mappings: [MappingSnapshot]
    ) -> NSAttributedString {
        var mappingsByField: [String: MappingSnapshot] = [:]
        for mapping in mappings {
            let field = TemplatePlaceholders.fieldName(for: mapping.placeholderText)
            // If an older job stored the same field twice, prefer the mapped entry.
            if mappingsByField[field]?.columnName == nil {
                mappingsByField[field] = mapping
            }
        }

        let output = NSMutableAttributedString(attributedString: template)
        for occurrence in TemplatePlaceholders.occurrences(in: template.string).reversed() {
            var replacement = ""
            if let mapping = mappingsByField[occurrence.name], let columnName = mapping.columnName {
                replacement = mapping.transformation.apply(to: rowData[columnName] ?? "", formatString: mapping.formatString)
            }
            let attributes = output.attributes(at: occurrence.range.location, effectiveRange: nil)
            output.replaceCharacters(in: occurrence.range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        return output
    }

    /// The paper size and margins to render a template with: the template's own, or US
    /// Letter with two-thirds-inch margins when it doesn't specify them.
    static func pageSetup(for template: AttributedTemplate) -> (size: CGSize, margins: EdgeInsets) {
        let size = template.pageSize ?? CGSize(width: 612, height: 792)
        let fallback = EdgeInsets(top: 48, leading: 48, bottom: 48, trailing: 48)
        var margins = template.margins ?? fallback
        // Margins that leave less than an inch of text area can't be laid out sensibly.
        if margins.leading + margins.trailing > size.width - 72 {
            margins.leading = fallback.leading
            margins.trailing = fallback.trailing
        }
        if margins.top + margins.bottom > size.height - 72 {
            margins.top = fallback.top
            margins.bottom = fallback.bottom
        }
        return (size, margins)
    }

    /// Keys are trimmed header names, matching the column names offered for mapping.
    /// When trimmed headers collide, the first column wins, as it does in the column picker.
    static func rowData(headers: [String], row: [String]) -> [String: String] {
        var data: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            let key = header.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, data[key] == nil else { continue }
            data[key] = index < row.count ? row[index] : ""
        }
        return data
    }

    private func filteredRows(_ rows: [[String]]) -> [[String]] {
        rows.filter { row in
            row.contains { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }

    /// The name of the single PDF written when records are combined.
    static func combinedFileName(jobName: String) -> String {
        let base = cleanedBaseName("Merged_\(jobName)")
        return "\(base.isEmpty ? "Merged" : base).pdf"
    }

    /// The file name the Output step shows as an example of what a merge produces.
    static func previewFileName(pattern: String, combinesIntoSinglePDF: Bool, jobName: String) -> String {
        if combinesIntoSinglePDF {
            return combinedFileName(jobName: jobName)
        }
        var usedNames: Set<String> = []
        return outputFileName(pattern: pattern, rowIndex: 1, rowData: [:], usedNames: &usedNames)
    }

    /// The file name for one record's PDF.
    ///
    /// `{Row}` is the record number and `{Column}` is that column's value. Tokens match
    /// columns ignoring spaces, punctuation, and capitalization, so `{FirstName}` finds a
    /// "First Name" column. Names that would be empty or hidden fall back to
    /// "Record N", and names already in `usedNames` get a number appended.
    static func outputFileName(
        pattern: String,
        rowIndex: Int,
        rowData: [String: String],
        usedNames: inout Set<String>
    ) -> String {
        var looseLookup: [String: String] = [:]
        for key in rowData.keys.sorted() {
            let looseKey = looseTokenKey(key)
            if looseLookup[looseKey] == nil {
                looseLookup[looseKey] = rowData[key]
            }
        }
        let filled = pattern
            .replacing("{Row}", with: "\(rowIndex)")
            .replacing(/\{([^{}]+)\}/) { match in
                let token = String(match.output.1)
                return rowData[token] ?? looseLookup[looseTokenKey(token)] ?? String(match.output.0)
            }
        var baseName = cleanedBaseName(filled)
        if baseName.isEmpty {
            baseName = "Record \(rowIndex)"
        }
        // Two records can resolve to the same name. Number the duplicates so no record
        // overwrites another, comparing case-insensitively like the default macOS file
        // system does.
        var candidate = "\(baseName).pdf"
        var suffix = 2
        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(baseName) \(suffix).pdf"
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }

    private static func looseTokenKey(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// A file name without extension that's safe to write: no path separators or
    /// characters Finder rejects, no line breaks, not hidden, and short enough to leave
    /// room for a duplicate number and the extension within the 255-byte limit.
    static func cleanedBaseName(_ raw: String) -> String {
        var name = FileNameSanitizer.sanitize(raw)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .replacing("\t", with: " ")
        if name.lowercased().hasSuffix(".pdf") {
            name = String(name.dropLast(4))
        }
        name = String(name.drop { $0 == "." || $0.isWhitespace })
        while let last = name.last, last == "." || last.isWhitespace {
            name.removeLast()
        }
        var shortened = ""
        var byteCount = 0
        for character in name {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= 240 else { break }
            shortened.append(character)
            byteCount += characterBytes
        }
        while let last = shortened.last, last.isWhitespace {
            shortened.removeLast()
        }
        return shortened
    }

    private func createZipAttachment(files: [URL], jobName: String) throws -> URL? {
        guard !files.isEmpty else { return nil }
        let zipName = Self.combinedFileName(jobName: jobName).dropLast(4).appending(".zip")
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

struct MappingSnapshot: Sendable {
    var placeholderText: String
    var columnName: String?
    var transformation: FieldTransformation = .none
    var formatString: String?

    init(placeholderText: String, columnName: String?, transformation: FieldTransformation = .none, formatString: String? = nil) {
        self.placeholderText = placeholderText
        self.columnName = columnName
        self.transformation = transformation
        self.formatString = formatString
    }

    init(from mapping: FieldMapping) {
        placeholderText = mapping.placeholderText
        columnName = mapping.columnName
        transformation = mapping.transformation
        formatString = mapping.formatString
    }
}

struct AttributedTemplate: @unchecked Sendable {
    let value: NSAttributedString
    /// The template's paper size in points, when the document specifies one.
    var pageSize: CGSize? = nil
    /// The template's page margins in points, when the document specifies them.
    var margins: EdgeInsets? = nil
}

/// The picture in a template's page header.
nonisolated struct DOCXHeaderImage: Sendable {
    var data: Data
    /// The size Word displays the picture at, in points, when the document specifies it.
    var size: CGSize?
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

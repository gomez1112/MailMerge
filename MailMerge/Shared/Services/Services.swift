import Foundation
import PDFKit
import SwiftData
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
        var dateRows: [[Date?]] = []
        for row in rows {
            guard let currentHeaders = headers else {
                let candidate = values(of: row, minimumCount: 0)
                if candidate.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    headers = candidate
                }
                continue
            }
            if let rowLimit, dataRows.count >= rowLimit { break }
            let text = values(of: row, minimumCount: currentHeaders.count)
            dataRows.append(text)
            var dates = Array<Date?>(repeating: nil, count: text.count)
            for cell in row.cells {
                dates[cell.column] = formatter.dateValue(for: cell, styles: styles)
            }
            dateRows.append(dates)
        }
        guard let headers else {
            throw MergeError.emptySheet
        }
        return SheetData(headers: headers, rows: dataRows, dates: dateRows)
    }
}

@MainActor
final class PDFGeneratorService {
    /// Where text and the header picture go on every page of a document.
    struct PageLayout {
        var pageSize: CGSize
        var textRect: CGRect
        var headerImage: PlatformImage?
        var headerRect: CGRect?
    }

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

    func generatePDF<S: Sequence>(
        pages: S,
        pageSize: CGSize,
        margins: EdgeInsets,
        headerImage: DOCXHeaderImage?
    ) throws -> Data where S.Element == NSAttributedString {
        let layout = layout(pageSize: pageSize, margins: margins, headerImage: headerImage)
        let pdfDocument = PDFDocument()
        for page in pages {
            appendPages(of: page, to: pdfDocument, layout: layout)
        }
        guard let data = pdfDocument.dataRepresentation() else {
            throw MergeError.pdfGenerationFailed
        }
        return data
    }

    func layout(pageSize: CGSize, margins: EdgeInsets, headerImage headerPicture: DOCXHeaderImage?) -> PageLayout {
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
        var textRect = baseTextRect
        if let headerRect, !headerRect.isEmpty {
            let topInset = max(baseTextRect.minY, headerRect.maxY + 12)
            textRect = CGRect(
                x: baseTextRect.minX,
                y: topInset,
                width: baseTextRect.width,
                // A zero-height container would lay all text out below the page.
                height: max(pageSize.height - topInset - margins.bottom, Self.minimumTextHeight)
            )
        }
        return PageLayout(pageSize: pageSize, textRect: textRect, headerImage: headerImage, headerRect: headerRect)
    }

    /// Lays out one record's text and appends its pages to `document`.
    func appendPages(of attributedString: NSAttributedString, to document: PDFDocument, layout: PageLayout) {
        renderAttributedString(
            attributedString,
            pdfDocument: document,
            pageSize: layout.pageSize,
            textRect: layout.textRect,
            headerImage: layout.headerImage,
            headerRect: layout.headerRect
        )
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

    /// Scans before inserting/counting a template-based job. An invalid or inaccessible
    /// template never consumes a free job slot or creates a blocked setup flow.
    func createJobFromTemplate(bookmark: Data, fileName: String, category: Category?, in context: ModelContext) async throws -> MailMergeJob {
        let fields = try await analyzeTemplate(bookmarkData: bookmark)
        try Task.checkCancellation()
        let job = MailMergeJob.makeNew(name: URL(filePath: fileName).deletingPathExtension().lastPathComponent, category: category)
        job.templateBookmarkData = bookmark
        job.templateFileName = fileName
        context.insert(job)
        job.syncFieldMappings(with: fields, in: context)
        return job
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
        try Task.checkCancellation()
        guard job.modelContext != nil, !job.isDeleted else { throw CancellationError() }
        job.refreshStaleBookmarks()
        guard let templateBookmarkData = job.templateBookmarkData else {
            throw MergeError.invalidTemplate
        }
        guard let dataBookmarkData = job.dataSourceBookmarkData,
              let sheetName = job.selectedSheetName else {
            throw MergeError.invalidSpreadsheet
        }

        let mappings = job.fieldMappings.map { MappingSnapshot(from: $0) }
        let reference = JobReference(job)
        let templateText = try await docxParser.parseTemplate(bookmarkData: templateBookmarkData)
        let headerImage = await docxParser.headerImage(bookmarkData: templateBookmarkData)
        let sheet = try await excelParser.fullSheet(bookmarkData: dataBookmarkData, sheetName: sheetName)
        try Task.checkCancellation()
        guard reference.exists else { throw CancellationError() }
        let rowIndices = nonemptyRowIndices(sheet.rows)
        let dataRows = rowIndices.map { sheet.rows[$0] }
        let totalRecords = dataRows.count
        guard totalRecords > 0 else {
            throw MergeError.noRecords
        }
        let page = Self.pageSetup(for: templateText)

        let safeIndex = max(0, min(recordIndex, totalRecords - 1))
        let row = dataRows[safeIndex]
        let rowData = Self.rowData(headers: sheet.headers, row: row)
        let attributedString = Self.merge(template: templateText.value, rowData: rowData, mappings: mappings, datesByColumn: sheet.datesByColumn(at: rowIndices[safeIndex]))
        
        let data = try pdfGenerator.generatePDF(
            from: attributedString,
            pageSize: page.size,
            margins: page.margins,
            headerImage: headerImage
        )
        return (data, totalRecords)
    }

    /// Runs a merge, writing a PDF for each record (or one combined PDF) to the job's
    /// output folder.
    ///
    /// Cancelling the calling task stops the merge before the next record. The job then
    /// keeps the status it had before the merge, and a combined PDF isn't written. The
    /// work runs on the main actor, which text layout and PDF drawing require, and pauses
    /// between records so the app stays responsive.
    func performMerge(
        job: MailMergeJob,
        singleDocument: Bool,
        progress: (MergeProgress) -> Void
    ) async throws -> MergeResult {
        // Keep the Mac awake and out of App Nap during a long merge.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Performing mail merge operation"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }

        try Task.checkCancellation()
        guard job.modelContext != nil, !job.isDeleted else { throw CancellationError() }
        let reference = JobReference(job)
        job.refreshStaleBookmarks()
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

        let previousStatus = job.status
        let previousRunDate = job.lastRunDate
        let previousRecordCount = job.lastRunRecordCount
        job.status = .running
        job.lastRunDate = Date()
        job.lastRunRecordCount = nil

        do {
            let result = try await mergeRecords(
                mappings: job.fieldMappings.map { MappingSnapshot(from: $0) },
                jobName: job.name,
                filePattern: job.outputFileNamePattern,
                templateBookmarkData: templateBookmarkData,
                dataBookmarkData: dataBookmarkData,
                sheetName: sheetName,
                outputBookmarkData: outputBookmarkData,
                singleDocument: singleDocument,
                progress: progress
            )
            // The job may have been deleted while the merge ran.
            if reference.exists {
                job.status = .completed
                job.lastRunDate = Date()
                job.lastRunRecordCount = result.recordCount
            }
            return result
        } catch is CancellationError {
            if reference.exists {
                job.status = previousStatus == .running ? (job.isConfigured ? .configured : .draft) : previousStatus
                job.lastRunDate = previousRunDate
                job.lastRunRecordCount = previousRecordCount
            }
            throw CancellationError()
        } catch {
            if reference.exists {
                job.status = .failed
                job.lastRunDate = Date()
                job.lastRunRecordCount = nil
            }
            throw error
        }
    }

    private func mergeRecords(
        mappings: [MappingSnapshot],
        jobName: String,
        filePattern: String,
        templateBookmarkData: Data,
        dataBookmarkData: Data,
        sheetName: String,
        outputBookmarkData: Data,
        singleDocument: Bool,
        progress: (MergeProgress) -> Void
    ) async throws -> MergeResult {
        let start = Date()
        let templateText = try await docxParser.parseTemplate(bookmarkData: templateBookmarkData)
        let headerImage = await docxParser.headerImage(bookmarkData: templateBookmarkData)
        let sheet = try await excelParser.fullSheet(bookmarkData: dataBookmarkData, sheetName: sheetName)
        try Task.checkCancellation()

        let rowIndices = nonemptyRowIndices(sheet.rows)
        let dataRows = rowIndices.map { sheet.rows[$0] }
        let totalRecords = dataRows.count
        guard totalRecords > 0 else { throw MergeError.noRecords }
        progress(MergeProgress(completed: 0, total: totalRecords))

        let page = Self.pageSetup(for: templateText)
        let layout = pdfGenerator.layout(pageSize: page.size, margins: page.margins, headerImage: headerImage)
        var pacer = InterfacePacer()

        let outputFolderURL = try SecurityScopedAccess.startAccessing(bookmarkData: outputBookmarkData)
        defer { SecurityScopedAccess.stopAccessing(outputFolderURL) }

        if singleDocument {
            let document = PDFDocument()
            for (index, row) in dataRows.enumerated() {
                try Task.checkCancellation()
                let text = Self.merge(template: templateText.value, rowData: Self.rowData(headers: sheet.headers, row: row), mappings: mappings, datesByColumn: sheet.datesByColumn(at: rowIndices[index]))
                pdfGenerator.appendPages(of: text, to: document, layout: layout)
                progress(MergeProgress(completed: index + 1, total: totalRecords))
                try await pacer.letInterfaceUpdate()
            }
            try Task.checkCancellation()
            guard let data = document.dataRepresentation() else {
                throw MergeError.pdfGenerationFailed
            }
            let fileURL = try Self.writeNewPDF(data, named: Self.combinedFileName(jobName: jobName), in: outputFolderURL)
            // Mail reads the attachment after the merge gives up access to the output
            // folder, so attach a copy from the app's temporary folder.
            let attachmentURL = try Self.attachmentDirectory().appending(path: fileURL.lastPathComponent)
            try data.write(to: attachmentURL)
            return MergeResult(
                savedFileNames: [fileURL.lastPathComponent],
                outputFolderName: outputFolderURL.lastPathComponent,
                outputFolderBookmark: outputBookmarkData,
                attachmentURL: attachmentURL,
                recordCount: totalRecords,
                duration: Date().timeIntervalSince(start)
            )
        }

        var outputFiles: [URL] = []
        var usedFileNames: Set<String> = []
        for (index, row) in dataRows.enumerated() {
            try Task.checkCancellation()
            let rowData = Self.rowData(headers: sheet.headers, row: row)
            let text = Self.merge(template: templateText.value, rowData: rowData, mappings: mappings, datesByColumn: sheet.datesByColumn(at: rowIndices[index]))
            let document = PDFDocument()
            pdfGenerator.appendPages(of: text, to: document, layout: layout)
            guard let data = document.dataRepresentation() else {
                throw MergeError.pdfGenerationFailed
            }
            let fileName = Self.outputFileName(
                pattern: filePattern,
                rowIndex: index + 1,
                rowData: rowData,
                usedNames: &usedFileNames
            )
            let fileURL = try Self.writeNewPDF(data, named: fileName, in: outputFolderURL)
            outputFiles.append(fileURL)
            progress(MergeProgress(completed: index + 1, total: totalRecords))
            try await pacer.letInterfaceUpdate()
        }
        try Task.checkCancellation()
        let attachmentURL = try createZipAttachment(files: outputFiles, jobName: jobName)
        return MergeResult(
            savedFileNames: outputFiles.map(\.lastPathComponent),
            outputFolderName: outputFolderURL.lastPathComponent,
            outputFolderBookmark: outputBookmarkData,
            attachmentURL: attachmentURL,
            recordCount: totalRecords,
            duration: Date().timeIntervalSince(start)
        )
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
        mappings: [MappingSnapshot],
        datesByColumn: [String: Date] = [:]
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
                replacement = mapping.transformation.apply(to: rowData[columnName] ?? "", formatString: mapping.formatString, dateValue: datesByColumn[columnName])
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

    private func nonemptyRowIndices(_ rows: [[String]]) -> [Int] {
        rows.indices.filter { index in
            rows[index].contains { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
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

    /// Every run gets its own directory, so an older completion card always attaches
    /// that run's documents even after another job with the same name has run.
    private static func attachmentDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MergeformAttachments", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Never replaces an existing document. The exclusive write also protects against
    /// another window or process creating the same name after the directory was read.
    private static func writeNewPDF(_ data: Data, named name: String, in folder: URL) throws -> URL {
        let base = String(name.dropLast(4))
        var suffix = 1
        while true {
            try Task.checkCancellation()
            let candidate = suffix == 1 ? name : "\(base) \(suffix).pdf"
            let url = folder.appending(path: candidate)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                suffix += 1
            }
        }
    }

    private func createZipAttachment(files: [URL], jobName: String) throws -> URL? {
        guard !files.isEmpty else { return nil }
        let zipName = Self.combinedFileName(jobName: jobName).dropLast(4).appending(".zip")
        let zipURL = try Self.attachmentDirectory().appending(path: zipName)
        let archive = try ZIPArchiveWriter(url: zipURL)
        for file in files {
            try archive.addEntry(path: file.lastPathComponent, contents: try Data(contentsOf: file))
        }
        try archive.finish()
        return zipURL
    }
}

/// Gives the main run loop a chance to handle input and redraw during long main-actor
/// work. A yield alone can resume before the run loop turns, so this sleeps briefly every
/// few dozen milliseconds; sleeping also ends the work promptly once it's cancelled.
private struct InterfacePacer {
    private var lastPause = ContinuousClock.now

    mutating func letInterfaceUpdate() async throws {
        if ContinuousClock.now - lastPause >= .milliseconds(30) {
            try await Task.sleep(for: .milliseconds(1))
            lastPause = .now
        } else {
            await Task.yield()
        }
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
    /// Resolves a bookmark and starts accessing its file.
    ///
    /// A bookmark to a file that was moved or renamed still resolves to the file's new
    /// location; `MailMergeJob.refreshStaleBookmarks()` saves the new location. Only a
    /// file that can't be found at all is an error.
    nonisolated static func startAccessing(bookmarkData: Data) throws -> URL {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw MergeError.staleBookmark
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw MergeError.securityScopeUnavailable
        }
        return url
    }

    /// The path of the file a bookmark points to, without accessing the file. Bookmarks
    /// to the same file differ byte for byte, so compare these instead.
    nonisolated static func filePath(for bookmarkData: Data) -> String? {
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url?.standardizedFileURL.path
    }

    /// A new bookmark and the current URL when `bookmarkData` points at a file that was
    /// moved or renamed; nil when the bookmark is current or the file can't be found.
    nonisolated static func refreshedBookmark(for bookmarkData: Data) -> (bookmark: Data, url: URL)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), isStale else {
            return nil
        }
        guard let bookmark = try? makeBookmark(for: url) else { return nil }
        return (bookmark, url)
    }

    nonisolated static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// Opens a Finder window on a bookmarked folder with `fileNames` in it selected.
    /// Files that were moved or deleted since are skipped; when none are left, the folder
    /// itself is selected.
    static func revealInFinder(folderBookmark: Data, selecting fileNames: [String] = []) throws {
        let folder = try startAccessing(bookmarkData: folderBookmark)
        defer { stopAccessing(folder) }
        let files = fileNames
            .map { folder.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(files.isEmpty ? [folder] : files)
    }

    /// Creates a security-scoped bookmark for a file the user picked or dropped, so the
    /// app can open it again after relaunching.
    ///
    /// URLs from an open panel carry a security scope that must be started first. URLs
    /// from a drag don't: the drag itself grants access, and starting a scope on them
    /// returns false. Neither case is an error.
    nonisolated static func makeBookmark(for url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

/// A saved deletion can detach a SwiftData model and reset isDeleted. Query by the
/// captured ID before touching it after any suspension; never inspect its stale data.
private struct JobReference {
    var context: ModelContext?
    var id: UUID
    private var job: MailMergeJob

    init(_ job: MailMergeJob) {
        self.job = job
        context = job.modelContext
        id = job.id
    }

    var exists: Bool {
        guard let context else { return !job.isDeleted }
        let id = id
        var request = FetchDescriptor<MailMergeJob>(predicate: #Predicate { $0.id == id })
        request.fetchLimit = 1
        return (try? context.fetch(request).first) != nil
    }
}

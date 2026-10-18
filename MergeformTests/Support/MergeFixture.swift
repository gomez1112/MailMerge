import Foundation
import SwiftData
@testable import Mergeform

/// A complete, configured job backed by real files: a template that greets `{{Name}}`,
/// a spreadsheet with a Name column, and an empty output folder.
@MainActor
struct MergeFixture {
    let container: ModelContainer
    let job: MailMergeJob
    let outputFolder: URL
    private let directories: [URL]

    init(recordCount: Int, pageSizeTwips: CGSize? = nil) throws {
        let schema = Schema(versionedSchema: MailMergeSchemaV3.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))

        let templateURL = try DOCXFixture(
            paragraphs: ["Dear {{Name}},", "Thank you for your order."],
            pageSizeTwips: pageSizeTwips,
            marginTwips: pageSizeTwips == nil ? nil : 1_440
        ).write()
        let rows = (1...recordCount).map { index in
            #"<row r="\#(index + 1)"><c r="A\#(index + 1)" t="inlineStr"><is><t>Person \#(index)</t></is></c></row>"#
        }.joined()
        let spreadsheetURL = try XLSXFixture(
            rowsXML: #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"# + rows,
            sharedStrings: ["Name"]
        ).write()
        outputFolder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        directories = [templateURL.deletingLastPathComponent(), spreadsheetURL.deletingLastPathComponent(), outputFolder]

        job = MailMergeJob(name: "Fixture Job", status: .configured)
        container.mainContext.insert(job)
        job.templateBookmarkData = try SecurityScopedAccess.makeBookmark(for: templateURL)
        job.templateFileName = templateURL.lastPathComponent
        job.dataSourceBookmarkData = try SecurityScopedAccess.makeBookmark(for: spreadsheetURL)
        job.dataSourceFileName = spreadsheetURL.lastPathComponent
        job.selectedSheetName = "Sheet1"
        job.outputFolderBookmarkData = try SecurityScopedAccess.makeBookmark(for: outputFolder)
        job.outputFolderName = outputFolder.lastPathComponent
        job.outputFileNamePattern = "Letter_{Name}"
        job.fieldMappings = [FieldMapping(placeholderText: "Name", columnName: "Name", job: job)]
    }

    var outputFileNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path)) ?? []).sorted()
    }

    func remove() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func makeEngine() -> MergeEngine {
        MergeEngine(docxParser: DOCXParserService(), excelParser: ExcelParserService(), pdfGenerator: PDFGeneratorService())
    }
}

import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import Mergeform

@MainActor
@Suite("Placeholder extraction")
struct PlaceholderExtractionTests {
    private func placeholders(in text: String) async -> [String] {
        await DOCXParserService().extractPlaceholders(from: AttributedTemplate(value: NSAttributedString(string: text)))
    }

    @Test("A dollar sign before a placeholder isn't part of it")
    func dollarSignBeforePlaceholder() async {
        #expect(await placeholders(in: "Total due: ${{Amount}}") == ["Amount"])
    }

    @Test("Spacing inside the braces doesn't create a second field")
    func spacingVariants() async {
        #expect(await placeholders(in: "{{ First }} and {{First}}") == ["First"])
    }
}

@MainActor
@Suite("Merging values into a template")
struct TemplateMergeTests {
    private func merge(_ template: String, _ values: [String: String]) -> String {
        let mappings = values.keys.map { MappingSnapshot(placeholderText: $0, columnName: $0) }
        return MergeEngine.merge(template: NSAttributedString(string: template), rowData: values, mappings: mappings).string
    }

    @Test("A value containing placeholder syntax isn't replaced again")
    func valuesAreNotRescanned() {
        let merged = merge("Dear {{Name}}, re: {{Subject}}", ["Name": "Bob {{Subject}}", "Subject": "Invoice"])
        #expect(merged == "Dear Bob {{Subject}}, re: Invoice")
    }

    @Test("A value containing angle brackets or dollar braces is kept")
    func valuesKeepTheirText() {
        #expect(merge("{{Notes}}", ["Notes": "Press <<Enter>> to continue"]) == "Press <<Enter>> to continue")
        #expect(merge("{{Notes}}", ["Notes": "Cost is ${price} [[draft]]"]) == "Cost is ${price} [[draft]]")
    }

    @Test("Stray delimiters on different lines don't delete the text between them")
    func strayDelimitersAcrossLines() {
        let merged = merge("Line one << oops\n{{Name}}\nSecond >> end", ["Name": "Ada"])
        #expect(merged == "Line one << oops\nAda\nSecond >> end")
    }

    @Test("A dollar sign typed before a placeholder stays in the output")
    func dollarSignStays() {
        #expect(merge("Total due: ${{Amount}}", ["Amount": "1,250.00"]) == "Total due: $1,250.00")
    }

    @Test("Parentheses in a placeholder name don't replace matching literal text")
    func parenthesesInNames() {
        let merged = merge("Phone {{(Mobile)}} (Mobile) section", ["(Mobile)": "555-1234"])
        #expect(merged == "Phone 555-1234 (Mobile) section")
    }

    @Test("Unmapped placeholders are removed and replacements keep the placeholder's formatting")
    func unmappedAndAttributes() {
        let template = NSMutableAttributedString(string: "Hi ")
        template.append(NSAttributedString(string: "{{Name}}", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
        template.append(NSAttributedString(string: "{{Unknown}}!"))
        let merged = MergeEngine.merge(
            template: template,
            rowData: ["Name": "Ada"],
            mappings: [MappingSnapshot(placeholderText: "Name", columnName: "Name")]
        )
        #expect(merged.string == "Hi Ada!")
        let font = merged.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }
}

@MainActor
@Suite("Template page setup and header picture")
struct TemplatePageSetupTests {
    @Test("The template's paper size and margins are read")
    func readsPageSetup() async throws {
        let url = try DOCXFixture(
            paragraphs: ["Hello"],
            pageSizeTwips: CGSize(width: 11_906, height: 16_838),
            marginTwips: 1_440
        ).write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let template = try await DOCXParserService().parseTemplate(at: url)
        let pageSize = try #require(template.pageSize)
        #expect(abs(pageSize.width - 595.3) < 0.1)
        #expect(abs(pageSize.height - 841.9) < 0.1)
        #expect(template.margins?.top == 72)
        #expect(template.margins?.leading == 72)
    }

    @Test("The header picture keeps the size it has in Word")
    func headerPictureSize() async throws {
        let url = try DOCXFixture(
            paragraphs: ["Hello"],
            headerPicture: .init(pixelSize: CGSize(width: 600, height: 600), extentEMU: CGSize(width: 914_400, height: 914_400))
        ).write()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let image = try #require(await DOCXParserService().headerImage(at: url))
        #expect(image.size == CGSize(width: 72, height: 72))
    }
}

@MainActor
@Suite("Header picture layout")
struct HeaderLayoutTests {
    private let letter = CGSize(width: 612, height: 792)
    private let margins = EdgeInsets(top: 48, leading: 48, bottom: 48, trailing: 48)

    @Test("A small square logo isn't enlarged to the page width")
    func smallLogoKeepsItsSize() {
        let frame = PDFGeneratorService.headerFrame(imageSize: CGSize(width: 150, height: 150), pageSize: letter, margins: margins)
        #expect(frame.size == CGSize(width: 150, height: 150))
        #expect(frame.minX == 48)
    }

    @Test("A wide banner is scaled down to the text width")
    func wideBannerFitsTheWidth() {
        let frame = PDFGeneratorService.headerFrame(imageSize: CGSize(width: 2_000, height: 200), pageSize: letter, margins: margins)
        #expect(frame.width == 516)
        #expect(abs(frame.height - 51.6) < 0.01)
    }

    @Test("A tall picture is limited to a quarter of the page height")
    func tallPictureIsCapped() {
        let frame = PDFGeneratorService.headerFrame(imageSize: CGSize(width: 300, height: 600), pageSize: letter, margins: margins)
        #expect(frame.height <= 198)
        #expect(abs(frame.width / frame.height - 0.5) < 0.001)
    }

    @Test("Body text still appears on pages with a tall header picture")
    func textIsNotPushedOffThePage() throws {
        let png = DOCXFixture.pngData(size: CGSize(width: 300, height: 600))
        let data = try PDFGeneratorService().generatePDF(
            from: NSAttributedString(string: "Dear customer, thank you for your order."),
            pageSize: letter,
            margins: margins,
            headerImageData: png
        )
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.string?.contains("thank you") == true)
    }
}

@MainActor
@Suite("Output file name cleanup")
struct OutputFileNamingTests {
    private func name(_ pattern: String, _ rowData: [String: String], row: Int = 1) -> String {
        var used: Set<String> = []
        return MergeEngine.outputFileName(pattern: pattern, rowIndex: row, rowData: rowData, usedNames: &used)
    }

    @Test("A blank value doesn't produce a hidden or empty file name")
    func blankValues() {
        let fileName = name("{FirstName}", ["FirstName": ""], row: 3)
        #expect(fileName == "Record 3.pdf")
        #expect(name("", [:], row: 2) == "Record 2.pdf")
    }

    @Test("Leading dots and line breaks are removed")
    func hiddenAndMultilineNames() {
        #expect(name("{Team}", ["Team": ".NET Guild"]) == "NET Guild.pdf")
        #expect(name("{Name}", ["Name": "Ada\nLovelace"]) == "Ada Lovelace.pdf")
    }

    @Test("Very long values are shortened to a valid file name length")
    func longNames() {
        let fileName = name("{Notes}", ["Notes": String(repeating: "Lorem ipsum ", count: 40)])
        #expect(fileName.utf8.count <= 255)
        #expect(fileName.hasSuffix(".pdf"))
    }

    @Test("Tokens match columns regardless of spaces and capitalization")
    func tokensMatchLoosely() {
        #expect(name("Letter_{FirstName}_{last name}", ["First Name": "Ada", "Last Name": "Lovelace"]) == "Letter_Ada_Lovelace.pdf")
    }

    @Test("The preview matches what a merge writes")
    func previewMatchesOutput() {
        #expect(MergeEngine.previewFileName(pattern: "Invoice.pdf", combinesIntoSinglePDF: false, jobName: "Q1") == "Invoice.pdf")
        #expect(MergeEngine.previewFileName(pattern: "Letter_{Row}", combinesIntoSinglePDF: true, jobName: "Holiday: Letters") == "Merged_Holiday_ Letters.pdf")
        #expect(MergeEngine.combinedFileName(jobName: "Holiday: Letters") == "Merged_Holiday_ Letters.pdf")
    }
}

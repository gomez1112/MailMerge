import Foundation
import SwiftUI
import Testing
@testable import MailMerge

@Suite("DOCX placeholder extraction")
struct DOCXParserServiceTests {
    @MainActor
    @Test("Extracts unique placeholders across formats")
    func extractsPlaceholders() async {
        let parser = DOCXParserService()
        let template = AttributedTemplate(value: NSAttributedString(
            string: "Hello {{First}} {{Last}} <<City>> [[State]] ${Amount} {{First}}"
        ))

        let result = await parser.extractPlaceholders(from: template)
        #expect(result == ["Amount", "City", "First", "Last", "State"])
    }

    @MainActor
    @Test("No placeholders yields empty array")
    func extractsNoPlaceholders() async {
        let parser = DOCXParserService()
        let template = AttributedTemplate(value: NSAttributedString(string: "No tags here."))

        let result = await parser.extractPlaceholders(from: template)
        #expect(result.isEmpty)
    }
}

@Suite("PDF generation")
struct PDFGeneratorServiceTests {
    @MainActor
    @Test("Generates PDF data")
    func generatesPDFData() throws {
        let generator = PDFGeneratorService()
        let content = NSAttributedString(string: "Hello PDF")
        let data = try generator.generatePDF(
            from: content,
            pageSize: CGSize(width: 612, height: 792),
            margins: EdgeInsets(top: 36, leading: 36, bottom: 36, trailing: 36),
            headerImageData: nil
        )

        #expect(data.isEmpty == false)
    }
}

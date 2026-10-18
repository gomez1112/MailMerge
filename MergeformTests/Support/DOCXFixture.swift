import AppKit
import Foundation
@testable import Mergeform

/// Builds a minimal .docx package in a fresh temporary directory.
struct DOCXFixture {
    struct HeaderPicture {
        var pixelSize: CGSize
        /// The displayed size in EMUs (914,400 per inch), as Word stores it.
        var extentEMU: CGSize
    }

    var paragraphs: [String]
    /// Paper size in twips (1/20 point), or nil to omit `<w:pgSz>`.
    var pageSizeTwips: CGSize?
    /// Uniform page margin in twips, or nil to omit `<w:pgMar>`.
    var marginTwips: Int?
    var headerPicture: HeaderPicture?

    init(paragraphs: [String], pageSizeTwips: CGSize? = nil, marginTwips: Int? = nil, headerPicture: HeaderPicture? = nil) {
        self.paragraphs = paragraphs
        self.pageSizeTwips = pageSizeTwips
        self.marginTwips = marginTwips
        self.headerPicture = headerPicture
    }

    func write() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "template.docx")
        let archive = try ZIPArchiveWriter(url: url)

        let namespaces = #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#
        let body = paragraphs
            .map { #"<w:p><w:r><w:t xml:space="preserve">\#(XLSXFixture.escaped($0))</w:t></w:r></w:p>"# }
            .joined()
        var sectionProperties = ""
        if headerPicture != nil {
            sectionProperties += #"<w:headerReference w:type="default" r:id="rIdHeader"/>"#
        }
        if let pageSizeTwips {
            sectionProperties += #"<w:pgSz w:w="\#(Int(pageSizeTwips.width))" w:h="\#(Int(pageSizeTwips.height))"/>"#
        }
        if let marginTwips {
            sectionProperties += #"<w:pgMar w:top="\#(marginTwips)" w:right="\#(marginTwips)" w:bottom="\#(marginTwips)" w:left="\#(marginTwips)" w:header="708" w:footer="708" w:gutter="0"/>"#
        }

        var parts: [String: Data] = [
            "[Content_Types].xml": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/></Types>
            """.utf8),
            "_rels/.rels": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
            """.utf8),
            "word/document.xml": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document \(namespaces)><w:body>\(body)<w:sectPr>\(sectionProperties)</w:sectPr></w:body></w:document>
            """.utf8)
        ]

        if let headerPicture {
            let width = Int(headerPicture.extentEMU.width)
            let height = Int(headerPicture.extentEMU.height)
            parts["word/_rels/document.xml.rels"] = Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/></Relationships>
            """.utf8)
            parts["word/header1.xml"] = Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr \(namespaces) xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(width)" cy="\(height)"/><wp:docPr id="1" name="Logo"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="logo.png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImage"/></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p></w:hdr>
            """.utf8)
            parts["word/_rels/header1.xml.rels"] = Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdImage" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/></Relationships>
            """.utf8)
            parts["word/media/image1.png"] = Self.pngData(size: headerPicture.pixelSize)
        }

        // Word deflates its parts, so the fixtures do too.
        for (path, data) in parts.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(path: path, contents: data, method: .deflated)
        }
        try archive.finish()
        return url
    }

    /// A solid-color PNG of the given pixel size, at 72 dpi.
    static func pngData(size: CGSize) -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let representation else { return Data() }
        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                representation.setColor(.systemBlue, atX: x, y: y)
            }
        }
        return representation.representation(using: .png, properties: [:]) ?? Data()
    }
}

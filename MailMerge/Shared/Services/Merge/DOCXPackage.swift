import Foundation
import SwiftUI
import ZIPFoundation

/// Reads page setup and the header picture from a .docx package. The system's DOCX
/// importer only provides the body text, so these come straight from the package XML.
nonisolated struct DOCXPackage {
    nonisolated struct PageLayout: Sendable {
        var pageSize: CGSize?
        var margins: EdgeInsets?
    }

    private let archive: Archive
    private let documentPath: String

    init(url: URL) throws {
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw MergeError.invalidTemplate
        }
        let rootRelationships = Self.relationships(in: archive, forPartAt: "")
        documentPath = rootRelationships.first { $0.type.hasSuffix("/officeDocument") }?.target ?? "word/document.xml"
    }

    /// The paper size and margins of the document's last section, in points.
    func pageLayout() -> PageLayout {
        guard let sectionProperties = finalSectionProperties() else { return PageLayout() }
        var layout = PageLayout()
        if let size = Self.attributes(ofFirst: "pgSz", in: sectionProperties),
           let width = size["w"].flatMap(Double.init),
           let height = size["h"].flatMap(Double.init),
           width > 0, height > 0 {
            // Landscape pages may store the shorter side as the width with orient="landscape".
            let isLandscape = size["orient"] == "landscape"
            let points = CGSize(width: width / 20, height: height / 20)
            layout.pageSize = isLandscape && points.width < points.height
                ? CGSize(width: points.height, height: points.width)
                : points
        }
        if let margins = Self.attributes(ofFirst: "pgMar", in: sectionProperties) {
            // Negative top and bottom margins mean "exactly" rather than "at least".
            func points(_ key: String) -> CGFloat {
                CGFloat(abs(margins[key].flatMap(Double.init) ?? 1_440)) / 20
            }
            layout.margins = EdgeInsets(
                top: points("top"),
                leading: points("left"),
                bottom: points("bottom"),
                trailing: points("right")
            )
        }
        return layout
    }

    /// The first picture in the section's default header, with the size Word shows it at.
    func headerImage() -> DOCXHeaderImage? {
        let documentRelationships = Self.relationships(in: archive, forPartAt: documentPath)
        let headers = documentRelationships.filter { $0.type.hasSuffix("/header") }
        guard !headers.isEmpty else { return nil }

        // Prefer the header the last section uses on ordinary pages, rather than a
        // first-page or even-page header.
        var headerPath = headers[0].target
        if let sectionProperties = finalSectionProperties() {
            let references = Self.elements(named: "headerReference", in: sectionProperties)
            let preferred = references.first { $0["type"] == "default" } ?? references.first
            if let id = preferred?["id"], let header = headers.first(where: { $0.id == id }) {
                headerPath = header.target
            }
        }

        guard let headerXML = Self.string(in: archive, path: headerPath) else { return nil }
        let headerRelationships = Self.relationships(in: archive, forPartAt: headerPath)
        for drawing in Self.blocks(named: "drawing", in: headerXML) {
            guard let blip = Self.attributes(ofFirst: "blip", in: drawing),
                  let embedID = blip["embed"],
                  let target = headerRelationships.first(where: { $0.id == embedID })?.target,
                  let data = Self.data(in: archive, path: target) else {
                continue
            }
            var size: CGSize?
            if let extent = Self.attributes(ofFirst: "extent", in: drawing),
               let width = extent["cx"].flatMap(Double.init),
               let height = extent["cy"].flatMap(Double.init),
               width > 0, height > 0 {
                // DrawingML measures in EMUs: 914,400 per inch, 12,700 per point.
                size = CGSize(width: width / 12_700, height: height / 12_700)
            }
            return DOCXHeaderImage(data: data, size: size)
        }
        // Older documents embed header pictures as VML image data, without a size.
        if let imageData = Self.attributes(ofFirst: "imagedata", in: headerXML),
           let id = imageData["id"],
           let target = headerRelationships.first(where: { $0.id == id })?.target,
           let data = Self.data(in: archive, path: target) {
            return DOCXHeaderImage(data: data, size: nil)
        }
        return nil
    }

    // MARK: - XML Helpers

    private func finalSectionProperties() -> String? {
        guard let document = Self.string(in: archive, path: documentPath) else { return nil }
        return Self.blocks(named: "sectPr", in: document).last
    }

    nonisolated private struct Relationship {
        var id: String
        var type: String
        var target: String
    }

    private static func relationships(in archive: Archive, forPartAt partPath: String) -> [Relationship] {
        let directory = (partPath as NSString).deletingLastPathComponent
        let fileName = (partPath as NSString).lastPathComponent
        let path = directory.isEmpty ? "_rels/\(fileName).rels" : "\(directory)/_rels/\(fileName).rels"
        guard let xml = string(in: archive, path: path) else { return [] }
        return elements(named: "Relationship", in: xml).compactMap { attributes in
            guard attributes["TargetMode"] != "External",
                  let id = attributes["Id"],
                  let type = attributes["Type"],
                  let target = attributes["Target"] else {
                return nil
            }
            return Relationship(id: id, type: type, target: XLSXPackageReader.resolve(target, relativeTo: directory))
        }
    }

    private static func data(in archive: Archive, path: String) -> Data? {
        let entry = archive[path] ?? archive.first { $0.path.caseInsensitiveCompare(path) == .orderedSame }
        guard let entry else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: true) { chunk in
                data.append(chunk)
            }
        } catch {
            return nil
        }
        return data
    }

    private static func string(in archive: Archive, path: String) -> String? {
        data(in: archive, path: path).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The full text of each `<prefix:name …>…</prefix:name>` element, ignoring prefixes.
    private static func blocks(named name: String, in xml: String) -> [String] {
        let open = try? Regex("<(?:[A-Za-z0-9]+:)?\(name)\\b[^>]*?(?:/>|>[\\s\\S]*?</(?:[A-Za-z0-9]+:)?\(name)>)")
        guard let open else { return [] }
        return xml.matches(of: open).map { String(xml[$0.range]) }
    }

    /// The attributes of each `<prefix:name …>` start tag, keyed by local name.
    private static func elements(named name: String, in xml: String) -> [[String: String]] {
        let tag = try? Regex("<(?:[A-Za-z0-9]+:)?\(name)\\b[^>]*>")
        guard let tag else { return [] }
        return xml.matches(of: tag).map { attributes(inTag: String(xml[$0.range])) }
    }

    private static func attributes(ofFirst name: String, in xml: String) -> [String: String]? {
        elements(named: name, in: xml).first
    }

    private static func attributes(inTag tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for match in tag.matches(of: /(?:[A-Za-z0-9]+:)?([A-Za-z0-9]+)\s*=\s*"([^"]*)"/) {
            let key = String(match.output.1)
            if attributes[key] == nil {
                attributes[key] = String(match.output.2)
                    .replacing("&amp;", with: "&")
                    .replacing("&quot;", with: "\"")
                    .replacing("&lt;", with: "<")
                    .replacing("&gt;", with: ">")
            }
        }
        return attributes
    }
}

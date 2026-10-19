// Builds Mergeform's captioned Mac App Store screenshots from raw window captures.
//
// Each slide is a 2880×1800 image (the largest size the mac-profile group accepts): a
// slice of one panoramic gradient that runs across the whole set, a bold title with a
// highlighted phrase, a subtitle, and the app window bleeding off the bottom edge.
//
// Usage: swift compose.swift <slides.json> <captures folder> <output folder>
//   A slide whose capture is missing gets a labeled placeholder, for layout proofs.
//
// Raw captures come from the opt-in MarketingCaptureTests fixture, or window captures
// supplied by hand. Keep them in Captures/; only the composed images go in the listing.

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SlideSet: Decodable {
    var slides: [Slide]
}

struct Slide: Decodable {
    /// The window capture in the captures folder.
    var capture: String
    /// The image to write in the output folder.
    var output: String
    /// The title, with `highlight` drawn as a pill if it appears in it.
    var title: String
    var highlight: String?
    var subtitle: String
    /// A small label above the title, such as "New".
    var badge: String?
}

let canvas = CGSize(width: 2880, height: 1800)

/// Stops along the panorama, from the first slide's left edge to the last slide's right
/// edge: the app icon's blue, a deeper indigo, then the icon's orange.
let panorama: [(position: CGFloat, color: NSColor)] = [
    (0.00, NSColor(srgbRed: 0.00, green: 0.42, blue: 0.93, alpha: 1)),
    (0.35, NSColor(srgbRed: 0.00, green: 0.53, blue: 1.00, alpha: 1)),
    (0.60, NSColor(srgbRed: 0.27, green: 0.31, blue: 0.86, alpha: 1)),
    (0.82, NSColor(srgbRed: 0.85, green: 0.38, blue: 0.40, alpha: 1)),
    (1.00, NSColor(srgbRed: 1.00, green: 0.55, blue: 0.16, alpha: 1)),
]

func panoramaColor(at position: CGFloat) -> NSColor {
    let clamped = min(max(position, 0), 1)
    for (lower, upper) in zip(panorama, panorama.dropFirst()) where clamped <= upper.position {
        let fraction = (clamped - lower.position) / (upper.position - lower.position)
        return lower.color.blended(withFraction: fraction, of: upper.color) ?? lower.color
    }
    return panorama[panorama.count - 1].color
}

func drawBackground(slideIndex: Int, slideCount: Int) {
    let start = CGFloat(slideIndex) / CGFloat(slideCount)
    let end = CGFloat(slideIndex + 1) / CGFloat(slideCount)
    let colors = (0...6).map { panoramaColor(at: start + (end - start) * CGFloat($0) / 6) }
    NSGradient(colors: colors)?.draw(in: CGRect(origin: .zero, size: canvas), angle: 0)

    // Soft glows give the flat gradient depth; their positions alternate per slide so
    // neighbors don't repeat.
    let glows: [(CGPoint, CGFloat, CGFloat)] = slideIndex.isMultiple(of: 2)
        ? [(CGPoint(x: 400, y: 1650), 900, 0.18), (CGPoint(x: 2600, y: 300), 1100, 0.12)]
        : [(CGPoint(x: 2500, y: 1700), 950, 0.16), (CGPoint(x: 300, y: 250), 1000, 0.12)]
    for (center, radius, alpha) in glows {
        let gradient = NSGradient(colors: [NSColor.white.withAlphaComponent(alpha), NSColor.white.withAlphaComponent(0)])
        gradient?.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }
}

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

/// Draws `text` centered on `centerX` with its top at `top` (top-left coordinates).
@discardableResult
func drawCentered(_ text: NSAttributedString, centerX: CGFloat, top: CGFloat) -> CGRect {
    let size = text.size()
    let rect = CGRect(x: centerX - size.width / 2, y: canvas.height - top - size.height, width: size.width, height: size.height)
    text.draw(in: rect)
    return rect
}

func drawTitle(_ slide: Slide, top: CGFloat) -> CGFloat {
    let titleFont = font(136, .heavy)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let base: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white, .kern: -2.5]
    let title = NSMutableAttributedString(string: slide.title, attributes: base)

    // The highlighted phrase is drawn on a white pill, in the slide's own color.
    var pillRange: NSRange?
    if let highlight = slide.highlight {
        let range = (slide.title as NSString).range(of: highlight)
        if range.location != NSNotFound {
            pillRange = range
            title.addAttribute(.foregroundColor, value: NSColor(white: 0.08, alpha: 1), range: range)
            // Widen the gaps around the phrase so the pill's padding doesn't cover them.
            if range.location > 0 {
                title.addAttribute(.kern, value: 64, range: NSRange(location: range.location - 1, length: 1))
            }
            if NSMaxRange(range) < title.length {
                title.addAttribute(.kern, value: 64, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
            }
        }
    }

    let size = title.size()
    let origin = CGPoint(x: canvas.width / 2 - size.width / 2, y: canvas.height - top - size.height)
    if let pillRange {
        let prefix = title.attributedSubstring(from: NSRange(location: 0, length: pillRange.location)).size().width
        let phrase = title.attributedSubstring(from: pillRange).size().width
        let pill = CGRect(x: origin.x + prefix - 34, y: origin.y - 6, width: phrase + 68, height: size.height + 12)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    }
    title.draw(at: origin)
    return top + size.height
}

func drawBadge(_ text: String, top: CGFloat) -> CGFloat {
    let label = NSAttributedString(string: text.uppercased(), attributes: [
        .font: font(40, .bold), .foregroundColor: NSColor.white, .kern: 4,
    ])
    let size = label.size()
    let pill = CGRect(x: canvas.width / 2 - size.width / 2 - 36, y: canvas.height - top - size.height - 24, width: size.width + 72, height: size.height + 24)
    NSColor.white.withAlphaComponent(0.2).setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    NSColor.white.withAlphaComponent(0.5).setStroke()
    let border = NSBezierPath(roundedRect: pill.insetBy(dx: 1.5, dy: 1.5), xRadius: pill.height / 2, yRadius: pill.height / 2)
    border.lineWidth = 3
    border.stroke()
    label.draw(at: CGPoint(x: pill.minX + 36, y: pill.minY + 12))
    return top + pill.height
}

/// The window, scaled to a fixed width, centered, and running off the bottom edge.
func drawWindow(_ image: NSImage?, label: String, top: CGFloat) {
    let width: CGFloat = 2360
    let aspect = image.map { $0.size.height / $0.size.width } ?? (780.0 / 1200.0)
    let rect = CGRect(x: (canvas.width - width) / 2, y: canvas.height - top - width * aspect, width: width, height: width * aspect)
    let corner: CGFloat = 30

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 90
    shadow.shadowOffset = CGSize(width: 0, height: -30)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).addClip()
    if let image {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        NSColor(white: 0.93, alpha: 1).setFill()
        rect.fill()
        let text = NSAttributedString(string: "Capture: \(label)", attributes: [.font: font(64, .semibold), .foregroundColor: NSColor(white: 0.55, alpha: 1)])
        let size = text.size()
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: max(rect.minY, 0) + (min(rect.maxY, canvas.height) - max(rect.minY, 0)) / 2 - size.height / 2))
    }
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ slide: Slide, index: Int, count: Int, capturesFolder: URL) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw ComposeError.drawing }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    drawBackground(slideIndex: index, slideCount: count)
    var top: CGFloat = 130
    if let badge = slide.badge {
        top = drawBadge(badge, top: top) + 36
    } else {
        top += 40
    }
    top = drawTitle(slide, top: top) + 26
    let subtitle = NSAttributedString(string: slide.subtitle, attributes: [
        .font: font(60, .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.88),
    ])
    top = drawCentered(subtitle, centerX: canvas.width / 2, top: top).height + top + 90

    let capture = NSImage(contentsOf: capturesFolder.appending(path: slide.capture))
    drawWindow(capture, label: slide.capture, top: top)

    NSGraphicsContext.restoreGraphicsState()
    // App Store Connect rejects screenshots with transparency, so write RGB without alpha.
    guard let rendered = bitmap.cgImage,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else { throw ComposeError.drawing }
    context.draw(rendered, in: CGRect(origin: .zero, size: canvas))
    guard let opaque = context.makeImage() else { throw ComposeError.drawing }
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
        throw ComposeError.drawing
    }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else { throw ComposeError.drawing }
    return png as Data
}

enum ComposeError: Error {
    case usage, drawing
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("Usage: swift compose.swift <slides.json> <captures folder> <output folder>")
    throw ComposeError.usage
}
let set = try JSONDecoder().decode(SlideSet.self, from: Data(contentsOf: URL(filePath: arguments[1])))
let captures = URL(filePath: arguments[2], directoryHint: .isDirectory)
let output = URL(filePath: arguments[3], directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (index, slide) in set.slides.enumerated() {
    let data = try render(slide, index: index, count: set.slides.count, capturesFolder: captures)
    try data.write(to: output.appending(path: slide.output))
    let found = FileManager.default.fileExists(atPath: captures.appending(path: slide.capture).path)
    print("\(slide.output)\(found ? "" : " (placeholder: \(slide.capture) not found)")")
}

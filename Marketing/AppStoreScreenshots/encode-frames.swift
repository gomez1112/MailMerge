// Encodes the full-window frames produced by record-frames.py as 30 fps H.264.
// Uses each snapshot's real capture time and holds it until the next captured frame.
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

@main
struct EncodeFrames {
    struct Frame: Decodable { var file: String; var seconds: Double }

    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw EncodingError.usage }
        let directory = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let output = URL(filePath: CommandLine.arguments[2])
        let frames = try JSONDecoder().decode([Frame].self, from: Data(contentsOf: directory.appending(path: "frames.json")))
        guard !frames.isEmpty, frames.last.map({ $0.seconds > 24 }) == true else { throw EncodingError.incomplete }
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoExpectedSourceFrameRateKey: 30]
        ])
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        guard writer.startWriting() else { throw writer.error ?? EncodingError.failed }
        writer.startSession(atSourceTime: .zero)
        var index = 0
        var previousIndex = -1
        var buffer: CVReadOnlyPixelBuffer?
        for frame in 0..<750 {
            let seconds = Double(frame) / 30
            while index + 1 < frames.count, frames[index + 1].seconds <= seconds { index += 1 }
            if index != previousIndex {
                buffer = try makeBuffer(imageURL: directory.appending(path: frames[index].file))
                previousIndex = index
            }
            guard let buffer else { throw EncodingError.failed }
            try await receiver.append(buffer, with: CMTime(value: Int64(frame), timescale: 30))
        }
        receiver.finish()
        writer.endSession(atSourceTime: CMTime(value: 25, timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? EncodingError.failed }
        print("Encoded 25 seconds at 1920×1080 from \(frames.count) full-window captures")
    }

    private static func makeBuffer(imageURL: URL) throws -> CVReadOnlyPixelBuffer {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw EncodingError.failed }
        var buffer = try CVMutablePixelBuffer(.init(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA), size: .init(width: 1920, height: 1080)))
        try buffer.accessUnsafeMutableRawPlaneBytes { planes in
            guard let plane = planes.first,
                  let context = CGContext(data: plane.bytes.baseAddress, width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: plane.properties.bytesPerRow, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw EncodingError.failed }
            context.setFillColor(red: 0.04, green: 0.14, blue: 0.28, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let scale = min(1920 / Double(image.width), 1080 / Double(image.height))
            let width = Double(image.width) * scale
            let height = Double(image.height) * scale
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: (1920 - width) / 2, y: (1080 - height) / 2, width: width, height: height))
        }
        return CVReadOnlyPixelBuffer(buffer)
    }
}

private enum EncodingError: Error { case usage, incomplete, failed }

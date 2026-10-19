// Export a real Mac window recording as a 1920×1080 App Store preview.
// Usage: export-preview input.mov output.mp4 [maximum seconds, 15–30] (requires macOS 26+).
import AVFoundation
import AppKit
import Foundation

@main
struct PreviewExporter {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 || arguments.count == 4 else { throw ExportError.usage }
        let maximumDuration = arguments.count == 4 ? Double(arguments[3]) ?? 0 : 25
        guard (15...30).contains(maximumDuration) else { throw ExportError.usage }
        let source = AVURLAsset(url: URL(filePath: arguments[1]))
        let duration = try await source.load(.duration)
        print("Input duration:", duration.seconds)
        guard duration.seconds >= 15 else { throw ExportError.tooShort }
        let video = try await source.loadTracks(withMediaType: .video).first
        guard let video else { throw ExportError.noVideo }
        let size = try await video.load(.naturalSize)
        print("Input size:", size)
        let length = CMTime(seconds: min(duration.seconds, maximumDuration), preferredTimescale: 600)
        let range = CMTimeRange(start: .zero, duration: length)
        let composition = AVMutableComposition()
        guard let picture = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.noVideo }
        try picture.insertTimeRange(range, of: video, at: .zero)

        // App previews require an audio track. Use silence, without recording anyone's
        // microphone, system audio, or surroundings.
        let silenceURL = URL.temporaryDirectory.appending(path: "mergeform-preview-silence.wav")
        try makeSilence(at: silenceURL, seconds: length.seconds)
        let silentAsset = AVURLAsset(url: silenceURL)
        guard let silentTrack = try await silentAsset.loadTracks(withMediaType: .audio).first else { throw ExportError.noAudio }
        try audio.insertTimeRange(range, of: silentTrack, at: .zero)

        let scale = min(1920 / size.width, 1080 / size.height)
        let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(
            CGAffineTransform(translationX: (1920 - size.width * scale) / 2, y: (1080 - size.height * scale) / 2)
        )
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: picture)
        layerConfiguration.setTransform(transform, at: .zero)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            backgroundColor: NSColor(srgbRed: 0.04, green: 0.14, blue: 0.28, alpha: 1).cgColor,
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layerConfiguration)],
            timeRange: range
        ))
        let layout = AVVideoComposition(configuration: .init(
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [instruction],
            renderSize: CGSize(width: 1920, height: 1080)
        ))
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else { throw ExportError.noVideo }
        export.videoComposition = layout
        export.shouldOptimizeForNetworkUse = true
        let output = URL(filePath: arguments[2])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try await export.export(to: output, as: .mp4)
        let finished = AVURLAsset(url: output)
        let videoTracks = try await finished.loadTracks(withMediaType: .video)
        let audioTracks = try await finished.loadTracks(withMediaType: .audio)
        let finishedDuration = try await finished.load(.duration)
        let finishedSize = try await videoTracks.first?.load(.naturalSize)
        print("Output:", output.path, "duration", finishedDuration.seconds, "size", String(describing: finishedSize), "audio tracks", audioTracks.count)
    }

    private static func makeSilence(at url: URL, seconds: Double) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let count = AVAudioFrameCount((seconds * 44_100).rounded(.up))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count), let samples = buffer.floatChannelData?[0] else { throw ExportError.noAudio }
        buffer.frameLength = count
        samples.initialize(repeating: 0, count: Int(count))
        try file.write(from: buffer)
    }
}

enum ExportError: Error { case usage, tooShort, noVideo, noAudio }

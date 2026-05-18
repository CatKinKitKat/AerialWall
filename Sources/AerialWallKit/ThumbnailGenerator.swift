import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ThumbnailError: Error, Equatable {
    case sourceNotReadable(URL)
    case noVideoTrack
    case encodingFailed
}

public enum ThumbnailGenerator {

    /// Extract a single frame and write it as PNG (matches Apple's `thumbnails/` convention).
    /// Default tap point is `t=1s`, clamped to clip duration if shorter.
    public static func generate(
        from source: URL,
        to destination: URL,
        at seconds: Double = 1.0
    ) async throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ThumbnailError.sourceNotReadable(source)
        }
        let asset = AVURLAsset(url: source)
        let readable: Bool
        do { readable = try await asset.load(.isReadable) }
        catch { throw ThumbnailError.sourceNotReadable(source) }
        guard readable else { throw ThumbnailError.sourceNotReadable(source) }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw ThumbnailError.noVideoTrack }

        let duration = try await asset.load(.duration).seconds
        let clampedSeconds = duration.isFinite && duration > 0
            ? min(max(seconds, 0), max(0, duration - 0.01))
            : seconds
        let t = CMTime(seconds: clampedSeconds, preferredTimescale: 600)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let (cgImage, _) = try await gen.image(at: t)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ThumbnailError.encodingFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ThumbnailError.encodingFailed
        }
    }
}

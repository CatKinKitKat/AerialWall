import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

public struct TranscodeOptions: Sendable {
    public var width: Int = 3840
    public var height: Int = 2160
    /// Target average bitrate in bits/sec. Apple stock encodes ~12.4 Mbps.
    public var bitrate: Int = 20_000_000
    public init() {}
}

public enum TranscodeError: Error, Equatable {
    case noVideoTrack(URL)
    case inputFormatUnsupported(URL)
    case writerSetupFailed(String)
    case readerSetupFailed(String)
    case encodeFailed(String)
    case outputNotPlayable(URL)
}

extension TranscodeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .inputFormatUnsupported(let url):
            return "Couldn't read \"\(url.lastPathComponent)\" — this container or codec isn't supported by macOS AVFoundation. Try converting to .mp4 or .mov first (e.g. with HandBrake)."
        case .noVideoTrack(let url):
            return "\"\(url.lastPathComponent)\" has no video track."
        case .writerSetupFailed(let s): return "Encoder setup failed: \(s)"
        case .readerSetupFailed(let s): return "Decoder setup failed: \(s)"
        case .encodeFailed(let s):      return "Encoding failed: \(s)"
        case .outputNotPlayable(let u): return "Encoded file isn't playable: \(u.lastPathComponent)"
        }
    }
}

public typealias TranscodeProgress = @Sendable (Double) -> Void

/// Native HEVC encoder. Uses `AVAssetWriter` + VideoToolbox with
/// `kVTCompressionPropertyKey_BaseLayerFrameRate` to produce 2-layer
/// hierarchical HEVC (TSA pictures at `temporal_id 1`) — required by
/// macOS WallpaperAerialsExtension for the unlock-fade still frame (B17,
/// V48). Scale-and-pad to target dimensions via `AVMutableVideoComposition`
/// so we don't need ffmpeg in the runtime path at all.
public enum TranscodeEngine {

    public static func transcode(
        input: URL,
        output: URL,
        options: TranscodeOptions = .init(),
        progress: TranscodeProgress? = nil
    ) async throws {
        let asset = AVURLAsset(url: input)
        // AVAssetReader doesn't support WebM (and a few other containers) on
        // Tahoe; `load(.isReadable)` throws -17913 in that case.
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw TranscodeError.inputFormatUnsupported(input)
        }
        guard let videoTrack = tracks.first else {
            throw TranscodeError.noVideoTrack(input)
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFps = try await videoTrack.load(.nominalFrameRate)
        let srcFps = Double(nominalFps > 0 ? nominalFps : 30)
        let duration = try await asset.load(.duration)

        // V49: trim leading black frames. WallpaperAerialsExtension snapshots
        // PTS=0 for the desktop preview; user videos often fade in from black
        // and the snapshot would otherwise be black (B18).
        let leadingOffset = await Self.detectLeadingNonBlackTime(asset: asset)
        let effectiveStart = leadingOffset
        let durationSec = max(0, duration.seconds - effectiveStart.seconds)

        // Compose scale+pad transform: aspect-fit into renderSize, black bars.
        let composition = makeComposition(
            source: videoTrack,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            srcFps: srcFps,
            duration: duration,
            targetWidth: options.width,
            targetHeight: options.height
        )

        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        } catch {
            throw TranscodeError.writerSetupFailed("\(error)")
        }

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(options: options, srcFps: srcFps)
        )
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw TranscodeError.readerSetupFailed("\(error)")
        }
        if effectiveStart > .zero {
            reader.timeRange = CMTimeRange(start: effectiveStart, end: duration)
        }
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ]
        let trackOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: readerSettings
        )
        trackOutput.videoComposition = composition
        reader.add(trackOutput)

        guard writer.startWriting() else {
            throw TranscodeError.encodeFailed(
                writer.error?.localizedDescription ?? "writer.startWriting failed")
        }
        // V49: rebase output PTS to 0 even when reading from a non-zero source time.
        writer.startSession(atSourceTime: effectiveStart)
        guard reader.startReading() else {
            throw TranscodeError.encodeFailed(
                reader.error?.localizedDescription ?? "reader.startReading failed")
        }

        try await pumpSamples(
            reader: reader,
            input: writerInput,
            output: trackOutput,
            durationSec: durationSec,
            progress: progress
        )

        try await finishWriting(writer: writer)
    }

    /// V4: `AVURLAsset.isPlayable` post-encode check.
    public static func validate(output: URL) async throws {
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw TranscodeError.outputNotPlayable(output)
        }
        let asset = AVURLAsset(url: output)
        let playable: Bool
        do { playable = try await asset.load(.isPlayable) }
        catch { throw TranscodeError.outputNotPlayable(output) }
        guard playable else { throw TranscodeError.outputNotPlayable(output) }
    }

    public static func transcodeAndValidate(
        input: URL,
        output: URL,
        options: TranscodeOptions = .init(),
        progress: TranscodeProgress? = nil
    ) async throws {
        try await transcode(input: input, output: output, options: options, progress: progress)
        try await validate(output: output)
    }

    // MARK: - private

    private static func videoOutputSettings(
        options: TranscodeOptions,
        srcFps: Double
    ) -> [String: Any] {
        // V48: 2-layer hierarchical HEVC. WallpaperAerialsExtension's
        // video-sample-reader filters frames by temporal_id; single-layer
        // output gets skipped wholesale → gray on unlock (B17). Set
        // BaseLayerFrameRate to half source fps so VT emits TRAIL_R at
        // temporal_id 0 plus TSA_N at temporal_id 1.
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: options.bitrate,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoExpectedSourceFrameRateKey: Int(srcFps.rounded()),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoAllowFrameReorderingKey: true,
            kVTCompressionPropertyKey_BaseLayerFrameRate as String: srcFps / 2.0,
        ]
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: options.width,
            AVVideoHeightKey: options.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    private static func makeComposition(
        source videoTrack: AVAssetTrack,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        srcFps: Double,
        duration: CMTime,
        targetWidth: Int,
        targetHeight: Int
    ) -> AVVideoComposition {
        // Source dimensions after the track's preferred transform (handles
        // rotated sources like portrait phone video).
        let orientedSize = naturalSize.applying(preferredTransform)
        let srcW = abs(orientedSize.width)
        let srcH = abs(orientedSize.height)

        // Aspect-fit: largest scale that fits within target.
        let scale = min(Double(targetWidth) / srcW, Double(targetHeight) / srcH)
        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let offsetX = (Double(targetWidth) - scaledW) / 2.0
        let offsetY = (Double(targetHeight) - scaledH) / 2.0

        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

        // macOS 26 API: build via Configuration value types (V48 migration).
        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(trackID: videoTrack.trackID)
        layerConfig.setTransform(transform, at: .zero)

        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: duration)
        instructionConfig.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        instructionConfig.layerInstructions = [
            AVVideoCompositionLayerInstruction(configuration: layerConfig)
        ]

        var compositionConfig = AVVideoComposition.Configuration()
        compositionConfig.renderSize = CGSize(width: targetWidth, height: targetHeight)
        compositionConfig.frameDuration = CMTime(
            value: 1, timescale: CMTimeScale(max(srcFps.rounded(), 1))
        )
        compositionConfig.instructions = [
            AVVideoCompositionInstruction(configuration: instructionConfig)
        ]
        return AVVideoComposition(configuration: compositionConfig)
    }

    private static func pumpSamples(
        reader: AVAssetReader,
        input: AVAssetWriterInput,
        output trackOutput: AVAssetReaderVideoCompositionOutput,
        durationSec: Double,
        progress: TranscodeProgress?
    ) async throws {
        final class AtomicState: @unchecked Sendable {
            private let lock = NSLock()
            private var _isFinished = false
            func finish() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if _isFinished { return false }
                _isFinished = true
                return true
            }
        }
        let state = AtomicState()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) let r = reader
            nonisolated(unsafe) let to = trackOutput
            nonisolated(unsafe) let wi = input

            let queue = DispatchQueue(label: "TranscodeEngine.encode")
            wi.requestMediaDataWhenReady(on: queue) {
                while wi.isReadyForMoreMediaData {
                    if let sample = to.copyNextSampleBuffer() {
                        if !wi.append(sample) {
                            if state.finish() {
                                wi.markAsFinished()
                                cont.resume(throwing: TranscodeError.encodeFailed("Writer append failed: \(wi.description)"))
                            }
                            return
                        }
                        if let progress, durationSec > 0 {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                            if pts.isFinite {
                                progress(min(1.0, max(0.0, pts / durationSec)))
                            }
                        }
                    } else {
                        if state.finish() {
                            wi.markAsFinished()
                            if r.status == .failed {
                                cont.resume(throwing: TranscodeError.encodeFailed(r.error?.localizedDescription ?? "Reader failed"))
                            } else {
                                cont.resume()
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    /// V49: scan first frames of a source asset and return the timestamp of the
    /// first non-black frame. Used to trim leading fade-from-black so the
    /// wallpaper extension's PTS=0 snapshot lands on real content.
    /// Falls back to `.zero` if every scanned frame is black or scanning fails.
    static func detectLeadingNonBlackTime(
        asset: AVAsset,
        maxScanSeconds: Double = 5.0,
        sampleInterval: Double = 0.25,
        meanLuminanceThreshold: Double = 25.0      // 0…255, ~10% of full range
    ) async -> CMTime {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 96, height: 54)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: sampleInterval, preferredTimescale: 600)

        var t = 0.0
        while t < maxScanSeconds {
            let cm = CMTime(seconds: t, preferredTimescale: 600)
            if let (image, _) = try? await gen.image(at: cm),
               meanLuminance(image) > meanLuminanceThreshold {
                return cm
            }
            t += sampleInterval
        }
        return .zero
    }

    static func meanLuminance(_ image: CGImage) -> Double {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return 0 }
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum: Double = 0
        var n: Double = 0
        // Rec. 709 luma; sample every 2nd pixel to cut work 4×
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let i = y * bytesPerRow + x * 4
                let r = Double(pixels[i])
                let g = Double(pixels[i + 1])
                let b = Double(pixels[i + 2])
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }

    private static func finishWriting(writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) let w = writer
            w.finishWriting {
                if w.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: TranscodeError.encodeFailed(
                        w.error?.localizedDescription ?? "writer status \(w.status.rawValue)"
                    ))
                }
            }
        }
    }
}

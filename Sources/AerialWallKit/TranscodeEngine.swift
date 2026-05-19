import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

public struct TranscodeOptions: Sendable {
    /// V50: target 2880×1620 — VT public API caps HEVC Main10 temporal hierarchy
    /// at 3 sub-layers above this resolution; below it we get 4 layers, which
    /// is what `WallpaperAerialsExtension`'s level-3 reader needs on the desktop
    /// apply path (B19). 2880×1620 is above MacBook Air M1 native (2560×1600)
    /// and 1440p Retina, so upscale on common Mac displays is imperceptible.
    public var width: Int = 2880
    public var height: Int = 1620
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
        let durationSec = duration.seconds

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
        writer.startSession(atSourceTime: .zero)
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
        // V50: 4-layer hierarchical HEVC (temporal_id 0..3).
        // WallpaperAerialsExtension's video-sample-reader uses TWO selection
        // levels depending on render path (B19):
        //   - lock/unlock path: "our level is 2" — needs temporal_id ≥ 1
        //   - desktop apply path: "our level is 3" — needs temporal_id ≥ 3
        // V48's srcFps/2 only produced 2 layers (max temporal_id=1), satisfying
        // level 2 but not level 3 → desktop showed black on apply, only worked
        // post lock/unlock. VT's BaseLayerFrameRate at srcFps/8 produces 4
        // temporal sub-layers (VT-internal cap — going lower doesn't add more).
        // Apple stock content has 5 layers (id 0..4); 4 is sufficient.
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: options.bitrate,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoExpectedSourceFrameRateKey: Int(srcFps.rounded()),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoAllowFrameReorderingKey: true,
            kVTCompressionPropertyKey_BaseLayerFrameRate as String: srcFps / 8.0,
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
        // V50: use 240Hz high-precision timescale rather than 1/srcFps. Coarser
        // (1/srcFps) frameDuration was capping VT's hierarchy depth at 3 layers
        // (id 0..2). 1/240 lets VT schedule frame timing freely so the 4-layer
        // (id 0..3) depth from BaseLayerFrameRate=srcFps/8 can express fully.
        compositionConfig.frameDuration = CMTime(value: 1, timescale: 240)
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

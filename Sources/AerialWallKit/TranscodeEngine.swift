import Foundation
import AVFoundation

public enum VideoEncoder: String, Sendable {
    case auto
    case videoToolbox = "hevc_videotoolbox"
    case x265 = "libx265"
}

public struct TranscodeOptions: Sendable {
    public var width: Int = 3840
    public var height: Int = 2160
    public var bitrate: String = "12M"
    public var encoder: VideoEncoder = .auto
    /// Explicit ffmpeg binary path. `nil` ⇒ auto-detect via PATH-like search.
    public var ffmpegPath: String? = nil

    public init() {}
}

public enum TranscodeError: Error, Equatable {
    case ffmpegNotFound(searched: [String])
    case transcodeFailed(exitCode: Int32, stderrTail: String)
    case outputNotPlayable(URL)
    case outputValidationFailed(reason: String)
}

public enum TranscodeEngine {

    /// Search order: explicit option > AERIALWALL_FFMPEG env > common Homebrew paths > /usr/bin/ffmpeg.
    /// Bundled FFmpegKit binary slots in here at T16.
    public static func detectFFmpeg(_ explicit: String? = nil) throws -> URL {
        let candidates: [String] = [
            explicit,
            ProcessInfo.processInfo.environment["AERIALWALL_FFMPEG"],
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        throw TranscodeError.ffmpegNotFound(searched: candidates)
    }

    /// Build the canonical ffmpeg command line per §I transcode params. Pure — no IO.
    /// Tested in isolation; the actual `transcode` call uses these args verbatim.
    public static func buildArgs(
        input: URL,
        output: URL,
        options: TranscodeOptions = .init(),
        resolvedEncoder: VideoEncoder
    ) -> [String] {
        precondition(resolvedEncoder != .auto, "resolvedEncoder must be concrete")
        // V1 SDR bt709: set via the `setparams` filter so the metadata is embedded
        // at the filter graph level. Output-level `-color_*` flags are unreliable
        // with hevc_videotoolbox and may be stripped from the bitstream.
        let vf = "scale=\(options.width):\(options.height):force_original_aspect_ratio=decrease," +
            "pad=\(options.width):\(options.height):(ow-iw)/2:(oh-ih)/2," +
            "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv"
        return [
            "-y",
            "-i", input.path,
            "-an",                                              // V3
            "-vf", vf,
            "-c:v", resolvedEncoder.rawValue,                   // V23
            "-tag:v", "hvc1",                                   // V2
            "-profile:v", "main10",                             // V1
            "-pix_fmt", "p010le",                               // V1 (10-bit)
            "-b:v", options.bitrate,
            "-movflags", "+faststart",
            "-f", "mov",
            output.path,
        ]
    }

    /// V23: resolve `.auto` → `.videoToolbox` if the encoder is available, else `.x265`.
    public static func resolveEncoder(_ requested: VideoEncoder, ffmpeg: URL) throws -> VideoEncoder {
        switch requested {
        case .videoToolbox, .x265: return requested
        case .auto:
            let proc = Process()
            proc.executableURL = ffmpeg
            proc.arguments = ["-hide_banner", "-encoders"]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.contains("hevc_videotoolbox") ? .videoToolbox : .x265
        }
    }

    /// Run ffmpeg. Throws on non-zero exit with stderr tail captured.
    public static func transcode(
        input: URL,
        output: URL,
        options: TranscodeOptions = .init()
    ) async throws {
        let ffmpeg = try detectFFmpeg(options.ffmpegPath)
        let encoder = try resolveEncoder(options.encoder, ffmpeg: ffmpeg)
        let args = buildArgs(input: input, output: output, options: options, resolvedEncoder: encoder)

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = ffmpeg
            proc.arguments = args
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = Pipe()

            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: data, encoding: .utf8) ?? ""
                    let tail = String(stderr.suffix(2000))
                    cont.resume(throwing: TranscodeError.transcodeFailed(
                        exitCode: p.terminationStatus, stderrTail: tail
                    ))
                }
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// V4: confirm the produced file is something AVFoundation will actually play.
    public static func validate(output: URL) async throws {
        let asset = AVURLAsset(url: output)
        do {
            let playable = try await asset.load(.isPlayable)
            guard playable else { throw TranscodeError.outputNotPlayable(output) }
        } catch let e as TranscodeError {
            throw e
        } catch {
            throw TranscodeError.outputValidationFailed(reason: "\(error)")
        }
    }

    /// Convenience: full pipeline — transcode then validate.
    public static func transcodeAndValidate(
        input: URL,
        output: URL,
        options: TranscodeOptions = .init()
    ) async throws {
        try await transcode(input: input, output: output, options: options)
        try await validate(output: output)
    }
}

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
    /// Default 20M — Apple's own clips run ~12.4M but those are professionally
    /// mastered originals. User imports often start from an already-lossy
    /// source (web-encoded MP4 / WebM AV1); the extra headroom suppresses
    /// the grain that double-compression at 12M produces.
    public var bitrate: String = "20M"
    public var encoder: VideoEncoder = .auto
    /// Explicit ffmpeg binary path. `nil` ⇒ auto-detect via PATH-like search.
    public var ffmpegPath: String? = nil
    /// Total input duration in seconds. When set, `transcode()` emits live
    /// progress values 0…1 derived from ffmpeg's `out_time_us` reports.
    /// Without this, `transcode()` produces no progress events.
    public var inputDurationSeconds: Double? = nil

    public init() {}
}

public typealias TranscodeProgress = @Sendable (Double) -> Void

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
        // V1 SDR bt709 via `setparams` filter (output-level `-color_*` flags
        // are unreliably propagated). V44: `setpts=PTS-STARTPTS` forces first-
        // frame PTS to 0 — wallpaper extension seeks to t=0 for the unlock-
        // fade still frame (B14).
        let vf = "scale=\(options.width):\(options.height):force_original_aspect_ratio=decrease," +
            "pad=\(options.width):\(options.height):(ow-iw)/2:(oh-ih)/2," +
            "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv," +
            "setpts=PTS-STARTPTS"

        // V47: VT-specific pix_fmt is `p010le`; libx265 uses `yuv420p10le`.
        let pixFmt = resolvedEncoder == .videoToolbox ? "p010le" : "yuv420p10le"

        var args: [String] = [
            "-y",
            "-nostdin",                                          // V38
            "-progress", "pipe:1",
            "-nostats",
            "-i", input.path,
            "-an",                                              // V3
            "-vf", vf,
            "-c:v", resolvedEncoder.rawValue,                   // V23
            "-tag:v", "hvc1",                                   // V2
            "-profile:v", "main10",                             // V1
            "-pix_fmt", pixFmt,                                 // V1, V47
            "-b:v", options.bitrate,
        ]

        // V47: encoder-specific options.
        // hevc_videotoolbox produces .mov that fails wallpaper-extension still-
        // frame extraction on unlock (B17). libx265 is now the default; VT is
        // retained as a fallback / future opt-in.
        if resolvedEncoder == .x265 {
            // Apple stock: has_b_frames=4, level=5.2.1. -preset fast keeps the
            // encode tractable on 4K Main 10 (~3× realtime on M-series; far
            // faster than -preset medium which is 10×+).
            args += [
                "-preset", "fast",
                "-x265-params", "bframes=4:ref=4:level-idc=5.2:log-level=error",
            ]
        } else {
            args += ["-bf", "4", "-refs", "4"]                  // V46
        }

        args += [
            "-muxdelay", "0", "-muxpreload", "0",                // V44
            "-movflags", "+faststart",
            "-f", "mov",
            output.path,
        ]
        return args
    }

    /// V47: `.auto` now resolves to `.x265` (software) primarily. VT was the
    /// original default but its output fails wallpaper-extension still-frame
    /// extraction on unlock (B17 — confirmed via Test C: even Apple's own
    /// content re-encoded through VT goes gray). `.videoToolbox` remains
    /// explicitly selectable but is no longer the auto choice.
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
            return text.contains("libx265") ? .x265 : .videoToolbox
        }
    }

    /// V37: thread-safe buffer for streamed stderr/stdout drainage.
    /// `Process` + `Pipe` deadlocks if the kernel pipe buffer fills (~64KB) and
    /// nothing reads from it — see B8.
    private final class LogCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }
        func tail(_ count: Int) -> String {
            lock.lock(); defer { lock.unlock() }
            let suffix = data.suffix(count)
            return String(data: Data(suffix), encoding: .utf8) ?? ""
        }
    }

    /// Parse `key=value` chunks ffmpeg emits when invoked with `-progress pipe:1`.
    /// Returns the latest `out_time_us` value or nil if the chunk has no such line.
    static func extractOutTimeMicros(from chunk: String) -> Int64? {
        var latest: Int64? = nil
        for line in chunk.split(separator: "\n") {
            if let eq = line.firstIndex(of: "="),
               line[line.startIndex..<eq] == "out_time_us",
               let v = Int64(line[line.index(after: eq)...]) {
                latest = v
            }
        }
        return latest
    }

    /// Run ffmpeg. Throws on non-zero exit with stderr tail captured.
    /// If `options.inputDurationSeconds` is set and `progress` is provided,
    /// emits 0…1 values derived from ffmpeg's `-progress pipe:1` stream.
    public static func transcode(
        input: URL,
        output: URL,
        options: TranscodeOptions = .init(),
        progress: TranscodeProgress? = nil
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
            let outPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = outPipe

            let collector = LogCollector()

            // V37: drain continuously to avoid fill-buffer deadlock. ffmpeg
            // writes verbose progress info to stderr; without this the kernel
            // pipe buffer fills and ffmpeg blocks on write() forever.
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    collector.append(chunk)
                }
            }
            // stdout carries the `-progress pipe:1` stream. Parse `out_time_us`
            // and emit normalized 0…1 progress when input duration is known.
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                guard
                    let progress,
                    let durationSec = options.inputDurationSeconds, durationSec > 0,
                    let text = String(data: chunk, encoding: .utf8),
                    let outTimeUs = extractOutTimeMicros(from: text)
                else { return }
                let ratio = min(1.0, max(0.0, Double(outTimeUs) / (durationSec * 1_000_000)))
                progress(ratio)
            }

            proc.terminationHandler = { p in
                errPipe.fileHandleForReading.readabilityHandler = nil
                outPipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: TranscodeError.transcodeFailed(
                        exitCode: p.terminationStatus,
                        stderrTail: collector.tail(2000)
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
        options: TranscodeOptions = .init(),
        progress: TranscodeProgress? = nil
    ) async throws {
        try await transcode(input: input, output: output, options: options, progress: progress)
        try await validate(output: output)
    }
}

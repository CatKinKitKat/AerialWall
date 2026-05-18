import Testing
import Foundation
import AVFoundation
@testable import AerialWallKit

@Suite("TranscodeEngine — V1 codec, V2 hvc1, V3 no audio, V4 playable, V23 encoder fallback")
struct TranscodeEngineTests {

    // MARK: - pure (no shell)

    @Test func argBuilderProducesSpecExactCommand() {
        let input = URL(fileURLWithPath: "/tmp/in.mp4")
        let output = URL(fileURLWithPath: "/tmp/out.mov")
        let args = TranscodeEngine.buildArgs(
            input: input, output: output,
            options: TranscodeOptions(),
            resolvedEncoder: .videoToolbox
        )

        // V38: explicit non-interactive stdin
        #expect(args.contains("-nostdin"))
        // V3: strip audio
        #expect(args.contains("-an"))
        // V2: hvc1 tag exact
        let tagIx = args.firstIndex(of: "-tag:v")!
        #expect(args[tagIx + 1] == "hvc1")
        // V1: Main 10 profile + 10-bit pix fmt
        let profileIx = args.firstIndex(of: "-profile:v")!
        #expect(args[profileIx + 1] == "main10")
        let pixIx = args.firstIndex(of: "-pix_fmt")!
        #expect(args[pixIx + 1] == "p010le")
        // V23: resolved encoder used verbatim
        let encIx = args.firstIndex(of: "-c:v")!
        #expect(args[encIx + 1] == "hevc_videotoolbox")
        // V1 SDR bt709 embedded via setparams filter in -vf chain
        let vfIx = args.firstIndex(of: "-vf")!
        let vf = args[vfIx + 1]
        #expect(vf.contains("setparams=color_primaries=bt709"))
        #expect(vf.contains("color_trc=bt709"))
        #expect(vf.contains("colorspace=bt709"))
        // mov container
        let fIx = args.firstIndex(of: "-f")!
        #expect(args[fIx + 1] == "mov")
        // Output path is last
        #expect(args.last == output.path)
    }

    @Test func argBuilderUsesX265WhenRequested() {
        let args = TranscodeEngine.buildArgs(
            input: URL(fileURLWithPath: "/tmp/in.mp4"),
            output: URL(fileURLWithPath: "/tmp/out.mov"),
            options: TranscodeOptions(),
            resolvedEncoder: .x265
        )
        let encIx = args.firstIndex(of: "-c:v")!
        #expect(args[encIx + 1] == "libx265")
    }

    @Test func argBuilderHonorsResolution() {
        var opts = TranscodeOptions()
        opts.width = 1920
        opts.height = 1080
        let args = TranscodeEngine.buildArgs(
            input: URL(fileURLWithPath: "/tmp/in.mp4"),
            output: URL(fileURLWithPath: "/tmp/out.mov"),
            options: opts,
            resolvedEncoder: .videoToolbox
        )
        let vfIx = args.firstIndex(of: "-vf")!
        #expect(args[vfIx + 1].contains("scale=1920:1080"))
        #expect(args[vfIx + 1].contains("pad=1920:1080"))
    }

    @Test func parsesOutTimeFromProgressStream() {
        let chunk = """
        frame=42
        fps=12.34
        out_time_us=2500000
        out_time=00:00:02.500000
        progress=continue
        """
        #expect(TranscodeEngine.extractOutTimeMicros(from: chunk) == 2_500_000)
    }

    @Test func handlesMultipleProgressBlocksReturnsLatest() {
        let chunk = """
        out_time_us=1000000
        progress=continue
        out_time_us=2000000
        progress=continue
        out_time_us=3500000
        progress=continue
        """
        #expect(TranscodeEngine.extractOutTimeMicros(from: chunk) == 3_500_000)
    }

    @Test func returnsNilWhenNoOutTime() {
        #expect(TranscodeEngine.extractOutTimeMicros(from: "frame=1\nprogress=end") == nil)
    }

    @Test func detectFFmpegFindsSystemBinary() throws {
        // Will succeed on dev box with Homebrew; skip otherwise.
        do {
            let url = try TranscodeEngine.detectFFmpeg()
            #expect(FileManager.default.isExecutableFile(atPath: url.path))
        } catch TranscodeError.ffmpegNotFound {
            // not installed — fine for CI
        }
    }

    // MARK: - end-to-end (real ffmpeg)

    /// Generate a 1-second 720p test clip with audio, transcode through our engine,
    /// verify output: HEVC Main 10, hvc1 tag, 3840×2160, no audio, playable.
    @Test func endToEndTranscodeMatchesAppleSpec() async throws {
        let ffmpeg: URL
        do { ffmpeg = try TranscodeEngine.detectFFmpeg() }
        catch TranscodeError.ffmpegNotFound { return }  // skip — no ffmpeg installed

        let tmpdir = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-transcode-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpdir) }

        let inputURL = tmpdir.appending(path: "in.mp4")
        let outputURL = tmpdir.appending(path: "out.mov")

        // Synthesize input: 1s 720p testsrc + 1s sine audio (audio will be stripped).
        let gen = Process()
        gen.executableURL = ffmpeg
        gen.arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=duration=1:size=1280x720:rate=30",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "libx264", "-c:a", "aac", "-t", "1", "-shortest",
            inputURL.path,
        ]
        gen.standardError = Pipe()
        try gen.run()
        gen.waitUntilExit()
        #expect(gen.terminationStatus == 0, "input synthesis failed")

        try await TranscodeEngine.transcodeAndValidate(input: inputURL, output: outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        // ffprobe verification → JSON of streams
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: ffmpeg.deletingLastPathComponent()
            .appending(path: "ffprobe").path)
        if !FileManager.default.isExecutableFile(atPath: probe.executableURL!.path) {
            return  // skip the inspection half — ffmpeg present but ffprobe not
        }
        probe.arguments = [
            "-v", "error", "-show_streams", "-show_format", "-of", "json", outputURL.path
        ]
        let out = Pipe()
        probe.standardOutput = out
        probe.standardError = Pipe()
        try probe.run()
        probe.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let streams = json["streams"] as! [[String: Any]]

        // V3: only video stream
        #expect(streams.count == 1)
        let s = streams[0]
        #expect((s["codec_type"] as? String) == "video")
        // V1: HEVC Main 10
        #expect((s["codec_name"] as? String) == "hevc")
        #expect((s["profile"] as? String)?.contains("Main 10") == true)
        // V2: hvc1 tag
        #expect((s["codec_tag_string"] as? String) == "hvc1")
        // V1: 3840×2160 after scale+pad
        #expect((s["width"] as? Int) == 3840)
        #expect((s["height"] as? Int) == 2160)
        // V1: 10-bit (yuv420p10le from VT or libx265, both accepted)
        let pixfmt = s["pix_fmt"] as? String ?? ""
        #expect(pixfmt.contains("10le"), "pix_fmt was \(pixfmt)")
        // V1: bt709
        #expect((s["color_primaries"] as? String) == "bt709")
    }
}

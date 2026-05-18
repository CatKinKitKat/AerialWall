import Testing
import Foundation
import AVFoundation
@testable import AerialWallKit

@Suite("TranscodeEngine — native VT with temporal sub-layers (V48)")
struct TranscodeEngineTests {

    /// Locate ffmpeg only to synthesize test inputs; production code doesn't use it.
    private static func findFFmpeg() -> URL? {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func synthInput(_ ffmpeg: URL, dest: URL, duration: Int = 1) throws {
        try? FileManager.default.removeItem(at: dest)
        let proc = Process()
        proc.executableURL = ffmpeg
        proc.arguments = [
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=duration=\(duration):size=1280x720:rate=30",
            "-c:v", "libx264", "-t", "\(duration)", dest.path,
        ]
        // No pipes = no buffer to fill and deadlock
        try proc.run()
        proc.waitUntilExit()
    }

    /// End-to-end transcode + verify HEVC Main10, 3840×2160, no audio, temporal_id > 0.
    @Test func transcodeProducesTemporalSubLayers() async throws {
        guard let ffmpeg = Self.findFFmpeg() else { return }

        let tmpdir = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-transcode-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpdir) }

        let inputURL = tmpdir.appending(path: "in.mp4")
        let outputURL = tmpdir.appending(path: "out.mov")
        try Self.synthInput(ffmpeg, dest: inputURL)

        try await TranscodeEngine.transcodeAndValidate(input: inputURL, output: outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        // ffprobe — stream info
        let ffprobeURL = ffmpeg.deletingLastPathComponent().appending(path: "ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else { return }

        let probe = Process()
        probe.executableURL = ffprobeURL
        probe.arguments = [
            "-v", "error", "-show_streams", "-show_format", "-of", "json", outputURL.path
        ]
        let probeOut = Pipe()
        probe.standardOutput = probeOut
        // Don't set stderr unless we read it or it's short, to avoid buffer issues
        try probe.run()
        let probeData = probeOut.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()

        let probeJSON = try JSONSerialization.jsonObject(with: probeData) as! [String: Any]
        let streams = probeJSON["streams"] as! [[String: Any]]

        #expect(streams.count == 1, "expected video-only output (V3 strips audio)")
        let s = streams[0]
        #expect((s["codec_name"] as? String) == "hevc")
        #expect((s["codec_tag_string"] as? String) == "hvc1")
        #expect((s["profile"] as? String)?.contains("Main 10") == true)
        #expect((s["width"] as? Int) == 3840)
        #expect((s["height"] as? Int) == 2160)
        let pixFmt = s["pix_fmt"] as? String ?? ""
        #expect(pixFmt.contains("10le"), "pix_fmt was \(pixFmt)")
        // start_time = 0 (V44)
        let startTime = Double(s["start_time"] as? String ?? "0") ?? 0
        #expect(startTime == 0.0)

        // V48: temporal sub-layers must be present. trace_headers dumps NAL info.
        let trace = Process()
        trace.executableURL = ffmpeg
        trace.arguments = [
            "-y", "-nostdin", "-loglevel", "debug",
            "-i", outputURL.path, "-t", "1", "-c", "copy",
            "-bsf:v", "trace_headers", "-f", "null", "-",
        ]
        let traceErr = Pipe()
        trace.standardError = traceErr
        // No stdout pipe to avoid deadlock
        try trace.run()
        let traceData = traceErr.fileHandleForReading.readDataToEndOfFile()
        trace.waitUntilExit()

        let traceText = String(data: traceData, encoding: .utf8) ?? ""
        let hasTSA = traceText.contains("TSA_N") || traceText.contains("TSA_R")
        let hasNonZeroTemporal = traceText.contains("temporal_id: 1")
            || traceText.contains("temporal_id: 2")
        #expect(hasTSA, "V48: output must include TSA NAL units")
        #expect(hasNonZeroTemporal, "V48: output must include frames at temporal_id > 0")
    }

    @Test func validateRejectsMissingFile() async {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).mov")
        await #expect(throws: TranscodeError.self) {
            try await TranscodeEngine.validate(output: nowhere)
        }
    }
}

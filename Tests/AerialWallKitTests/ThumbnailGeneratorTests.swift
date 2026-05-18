import Testing
import Foundation
import ImageIO
@testable import AerialWallKit

@Suite("ThumbnailGenerator — PNG frame extraction")
struct ThumbnailGeneratorTests {

    @Test func generatesPNGFromSyntheticClip() async throws {
        // Locate ffmpeg only to synthesize the test input — production thumbnail
        // path uses AVAssetImageGenerator and doesn't need ffmpeg.
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let ffmpegPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let ffmpeg = URL(fileURLWithPath: ffmpegPath)

        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-thumb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mov = tmp.appending(path: "src.mp4")
        let png = tmp.appending(path: "thumb.png")

        // 3-sec testsrc so t=1s tap is well inside duration
        let gen = Process()
        gen.executableURL = ffmpeg
        gen.arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=duration=3:size=640x360:rate=30",
            "-c:v", "libx264", "-t", "3", mov.path,
        ]
        gen.standardError = Pipe()
        try gen.run()
        gen.waitUntilExit()
        #expect(gen.terminationStatus == 0)

        try await ThumbnailGenerator.generate(from: mov, to: png)
        #expect(FileManager.default.fileExists(atPath: png.path))

        // Validate the PNG is decodable and has non-zero dimensions.
        let src = CGImageSourceCreateWithURL(png as CFURL, nil)
        #expect(src != nil)
        let img = CGImageSourceCreateImageAtIndex(src!, 0, nil)
        #expect(img != nil)
        #expect(img!.width > 0)
        #expect(img!.height > 0)
        // UTI of the output should be PNG.
        let type = CGImageSourceGetType(src!)
        #expect((type as String?) == "public.png")
    }

    @Test func missingSourceThrows() async throws {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "definitely-not-here-\(UUID().uuidString).mov")
        let out = FileManager.default.temporaryDirectory.appending(path: "x.png")
        await #expect(throws: ThumbnailError.self) {
            try await ThumbnailGenerator.generate(from: nowhere, to: out)
        }
    }
}

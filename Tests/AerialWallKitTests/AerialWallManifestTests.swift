import Testing
import Foundation
@testable import AerialWallKit

@Suite("AerialWallManifest — Codable round-trip, V19 dangling refs, upsert/remove")
struct AerialWallManifestTests {

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "aw-manifest-\(UUID().uuidString).json")
    }

    private func sample(uuid: String = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        videoPath: String = "/tmp/v.mov",
                        thumbPath: String = "/tmp/t.png") -> AerialWallEntry {
        AerialWallEntry(
            uuid: uuid, name: "n", originalFilename: "o.mp4",
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 12.5, resolution: "3840x2160",
            videoPath: videoPath, thumbPath: thumbPath
        )
    }

    @Test func loadMissingFileReturnsEmpty() throws {
        let url = tmpURL()  // never written
        let m = try AerialWallManifestStore.load(from: url)
        #expect(m.wallpapers.isEmpty)
        #expect(m.schemaVersion == 1)
        #expect(m.entriesSchemaSeen == Constants.expectedEntriesSchemaVersion)
    }

    @Test func roundTrip() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let m = AerialWallManifest(wallpapers: [sample()])
        try AerialWallManifestStore.save(m, to: url)
        let loaded = try AerialWallManifestStore.load(from: url)
        #expect(loaded == m)
    }

    @Test func upsertAddsThenReplaces() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var e = sample()
        try AerialWallManifestStore.upsert(e, at: url)
        #expect(try AerialWallManifestStore.load(from: url).wallpapers.count == 1)
        e.name = "renamed"
        try AerialWallManifestStore.upsert(e, at: url)
        let loaded = try AerialWallManifestStore.load(from: url)
        #expect(loaded.wallpapers.count == 1)
        #expect(loaded.wallpapers.first?.name == "renamed")
    }

    @Test func removeDropsEntry() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try AerialWallManifestStore.upsert(sample(), at: url)
        try AerialWallManifestStore.remove(uuid: sample().uuid, at: url)
        #expect(try AerialWallManifestStore.load(from: url).wallpapers.isEmpty)
    }

    /// V19: a manifest with file paths that don't exist ⇒ flagged dangling.
    @Test func danglingEntriesDetected() throws {
        let m = AerialWallManifest(wallpapers: [
            sample(uuid: "11111111-1111-1111-1111-111111111111",
                   videoPath: "/this/does/not/exist.mov",
                   thumbPath: "/nor/this.png"),
        ])
        let dangling = AerialWallManifestStore.danglingEntries(in: m)
        #expect(dangling.count == 1)
    }

    @Test func nonDanglingNotFlagged() throws {
        // Use /etc/hosts as a real file guaranteed to exist on macOS.
        let m = AerialWallManifest(wallpapers: [
            sample(videoPath: "/etc/hosts", thumbPath: "/etc/hosts"),
        ])
        let dangling = AerialWallManifestStore.danglingEntries(in: m)
        #expect(dangling.isEmpty)
    }
}

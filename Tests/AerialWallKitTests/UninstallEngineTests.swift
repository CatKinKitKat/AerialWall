import Testing
import Foundation
@testable import AerialWallKit

@Suite("UninstallEngine — T15/V29")
struct UninstallEngineTests {

    /// Build a sandbox replicating the on-disk layout uninstall touches.
    /// Optionally seed: aerial wall manifest with N wallpapers, matching
    /// asset files, the AerialWall storage dir, and the LaunchAgent plist.
    private struct Sandbox {
        let context: UninstallContext
        let root: URL
        let aerialIDs: [String]

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeSandbox(
        wallpaperCount: Int = 2,
        seedEntries: Bool = true,
        seedStorage: Bool = true,
        seedLaunchAgent: Bool = true
    ) throws -> Sandbox {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "uninstall-\(UUID().uuidString)", directoryHint: .isDirectory)

        let aerialRoot = root.appending(path: "aerialwall", directoryHint: .isDirectory)
        let wallpaperRoot = root.appending(path: "wallpaper", directoryHint: .isDirectory)
        let videos     = wallpaperRoot.appending(path: "videos",     directoryHint: .isDirectory)
        let thumbs     = wallpaperRoot.appending(path: "thumbnails", directoryHint: .isDirectory)
        let backups    = aerialRoot.appending(path: "backups",       directoryHint: .isDirectory)

        for d in [root, aerialRoot, wallpaperRoot, videos, thumbs, backups] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }

        // Make N AerialWall wallpaper entries with matching video+thumb files
        var ids: [String] = []
        var entries: [AerialWallEntry] = []
        for i in 0..<wallpaperCount {
            let id = "AAAAAAAA-BBBB-CCCC-DDDD-\(String(format: "%012d", i))"
            ids.append(id)
            let entry = AerialWallEntry(
                uuid: id, name: "Test \(i)", description: "x",
                originalFilename: "src-\(i).mp4",
                importedAt: Date(),
                durationSeconds: 10,
                resolution: "4K",
                videoPath: videos.appending(path: "\(id).mov").path,
                thumbPath: thumbs.appending(path: "\(id).png").path,
                isInjected: true)
            entries.append(entry)
            try Data("video-\(i)".utf8)
                .write(to: videos.appending(path: "\(id).mov"))
            try Data("thumb-\(i)".utf8)
                .write(to: thumbs.appending(path: "\(id).png"))
        }

        // Seed AerialWall manifest
        let mfst = AerialWallManifest(wallpapers: entries)
        let mfstPath = aerialRoot.appending(path: "manifest.json")
        try AerialWallManifestStore.save(mfst, to: mfstPath)

        // Seed AerialWall sub-folders so storage deletion has something to do
        if seedStorage {
            for sub in ["library", "thumbs", "originals"] {
                let p = aerialRoot.appending(path: sub, directoryHint: .isDirectory)
                try fm.createDirectory(at: p, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: p.appending(path: "marker.txt"))
            }
        }

        // Seed entries.json containing the matching IDs
        let entriesPath = wallpaperRoot.appending(path: "entries.json")
        if seedEntries {
            try Data(EntriesJSONTests.fixture.utf8).write(to: entriesPath)
            var em = try EntriesJSONCodec.load(from: entriesPath)
            for id in ids {
                em.assets.append(Asset(
                    id: id,
                    accessibilityLabel: "AerialWall Test",
                    categories: [Constants.AerialWallCategory.categoryID],
                    subcategories: [Constants.AerialWallCategory.subcategoryID],
                    includeInShuffle: false,
                    localizedNameKey: "AerialWall Test",
                    preferredOrder: 100,
                    previewImage: "https://x/preview.png",
                    shotID: "AW_\(id.prefix(8))",
                    showInTopLevel: true,
                    urlSDR4K240: "https://x/video.mov"))
            }
            em.categories.append(Category(
                id: Constants.AerialWallCategory.categoryID,
                localizedNameKey: "AerialWall",
                localizedDescriptionKey: "AerialWall",
                preferredOrder: 99,
                previewImage: "https://x/cat.png",
                representativeAssetID: ids.first ?? "",
                subcategories: []))
            try EntriesJSONCodec.writeAtomically(em, to: entriesPath)
        }

        // Seed LaunchAgent plist
        let launchAgentPlist = root.appending(path: "com.aerialwall.agent.plist")
        if seedLaunchAgent {
            try Data("<plist/>".utf8).write(to: launchAgentPlist)
        }

        let context = UninstallContext(
            aerialWallRoot:         aerialRoot,
            aerialWallManifestPath: mfstPath,
            aerialWallBackupsDir:   backups,
            entriesJSONPath:        entriesPath,
            wallpaperVideosDir:     videos,
            wallpaperThumbnailsDir: thumbs,
            launchAgentPlist:       launchAgentPlist,
            signalAgentOnFinish:    false   // no real WallpaperAgent in tests
        )
        return Sandbox(context: context, root: root, aerialIDs: ids)
    }

    @Test func fullUninstallStripsEntriesAndDeletesEverything() async throws {
        let s = try makeSandbox(wallpaperCount: 2)
        defer { s.cleanup() }

        let report = try await UninstallEngine.uninstall(mode: .full, context: s.context)

        #expect(report.assetsConsidered == 2)
        #expect(report.assetsStripped == 2)
        #expect(report.filesDeleted == 4)        // 2 videos + 2 thumbs
        #expect(report.storageDeleted == true)
        #expect(report.launchAgentRemoved == true)

        // entries.json no longer references AerialWall IDs or category
        let em = try EntriesJSONCodec.load(from: s.context.entriesJSONPath)
        for id in s.aerialIDs {
            #expect(!em.assets.contains { $0.id == id })
        }
        #expect(!em.categories.contains {
            $0.id == Constants.AerialWallCategory.categoryID
        })
        // Apple stock entries from the fixture are untouched (V28)
        #expect(em.assets.count == 2)            // the 2 stock fixtures remain

        // Files actually gone
        let fm = FileManager.default
        for id in s.aerialIDs {
            #expect(!fm.fileExists(atPath: s.context.wallpaperVideosDir
                .appending(path: "\(id).mov").path))
            #expect(!fm.fileExists(atPath: s.context.wallpaperThumbnailsDir
                .appending(path: "\(id).png").path))
        }
        // AerialWall storage gone
        #expect(!fm.fileExists(atPath: s.context.aerialWallRoot.path))
        // LaunchAgent plist gone
        #expect(!fm.fileExists(atPath: s.context.launchAgentPlist.path))
    }

    @Test func preservingBackupKeepsBackupsDir() async throws {
        let s = try makeSandbox()
        defer { s.cleanup() }

        // Drop a fake backup file so we can verify it survives
        let backupFile = s.context.aerialWallBackupsDir
            .appending(path: "entries.json.20260519.bak")
        try Data("backup".utf8).write(to: backupFile)

        let report = try await UninstallEngine.uninstall(
            mode: .preservingBackup, context: s.context)

        #expect(report.storageDeleted == true)
        let fm = FileManager.default
        // root still exists (because backups/ wasn't nuked)
        #expect(fm.fileExists(atPath: s.context.aerialWallRoot.path))
        #expect(fm.fileExists(atPath: backupFile.path))
        // library/thumbs/originals/manifest.json are gone
        for sub in ["library", "thumbs", "originals", "manifest.json"] {
            #expect(!fm.fileExists(atPath:
                s.context.aerialWallRoot.appending(path: sub).path))
        }
    }

    @Test func noOpWhenNothingToUninstall() async throws {
        let s = try makeSandbox(
            wallpaperCount: 0, seedEntries: false,
            seedStorage: false, seedLaunchAgent: false)
        defer { s.cleanup() }

        // Even the AerialWall manifest is empty / absent
        try? FileManager.default.removeItem(at: s.context.aerialWallManifestPath)

        let report = try await UninstallEngine.uninstall(
            mode: .full, context: s.context)

        #expect(report.assetsConsidered == 0)
        #expect(report.assetsStripped == 0)
        #expect(report.filesDeleted == 0)
        // aerialWallRoot was seeded but empty — should still be deleted
        #expect(report.storageDeleted == true)
        #expect(report.launchAgentRemoved == false)
    }
}

import Foundation

public enum UninstallError: Error {
    case entriesUnwritable(String)
    case incomplete([String])    // list of paths that failed to delete
}

/// Path bundle for uninstall. Defaults to the real Constants paths; tests
/// can pass an alternate context pointing at a sandbox.
public struct UninstallContext: Sendable {
    public var aerialWallRoot:          URL
    public var aerialWallManifestPath:  URL
    public var aerialWallBackupsDir:    URL
    public var entriesJSONPath:         URL
    public var wallpaperVideosDir:      URL
    public var wallpaperThumbnailsDir:  URL
    public var launchAgentPlist:        URL
    public var signalAgentOnFinish:     Bool

    public init(
        aerialWallRoot:         URL = Constants.aerialWallRoot,
        aerialWallManifestPath: URL = Constants.aerialWallManifestPath,
        aerialWallBackupsDir:   URL = Constants.aerialWallBackupsDir,
        entriesJSONPath:        URL = Constants.entriesJSONPath,
        wallpaperVideosDir:     URL = Constants.wallpaperVideosDir,
        wallpaperThumbnailsDir: URL = Constants.wallpaperThumbnailsDir,
        launchAgentPlist:       URL = Constants.launchAgentPlist,
        signalAgentOnFinish:    Bool = true
    ) {
        self.aerialWallRoot         = aerialWallRoot
        self.aerialWallManifestPath = aerialWallManifestPath
        self.aerialWallBackupsDir   = aerialWallBackupsDir
        self.entriesJSONPath        = entriesJSONPath
        self.wallpaperVideosDir     = wallpaperVideosDir
        self.wallpaperThumbnailsDir = wallpaperThumbnailsDir
        self.launchAgentPlist       = launchAgentPlist
        self.signalAgentOnFinish    = signalAgentOnFinish
    }
}

/// V29 + T15. Full uninstall workflow:
///  1. Strip AerialWall assets from `entries.json` (by AerialWall manifest UUIDs)
///  2. Delete the `videos/<UUID>.mov` and `thumbnails/<UUID>.png` files for each
///  3. Delete `~/Library/Application Support/AerialWall/` (manifest + originals + backups)
///  4. Unload `~/Library/LaunchAgents/com.aerialwall.agent.plist`
///  5. Restart `WallpaperAgent` so it picks up the cleaned manifest
public enum UninstallEngine {

    public enum Mode: Sendable {
        case full
        case preservingBackup
    }

    @discardableResult
    public static func uninstall(
        mode: Mode = .full,
        context: UninstallContext = UninstallContext()
    ) async throws -> UninstallReport {
        var failed: [String] = []
        var report = UninstallReport()
        let fm = FileManager.default

        AerialLog.injection.info("uninstall start mode=\(String(describing: mode), privacy: .public)")

        // 1. Load AerialWall's own manifest to find which UUIDs we own
        let ownedIDs: [String]
        if fm.fileExists(atPath: context.aerialWallManifestPath.path) {
            do {
                let mfst = try AerialWallManifestStore.load(from: context.aerialWallManifestPath)
                ownedIDs = mfst.wallpapers.map(\AerialWallEntry.id)
            } catch {
                AerialLog.injection.warning("aerialwall-manifest read failed: \(error.localizedDescription, privacy: .public)")
                ownedIDs = []
            }
        } else {
            ownedIDs = []
        }
        report.assetsConsidered = ownedIDs.count

        // 2. Strip from entries.json (best-effort: skip if file missing or schema mismatch)
        if fm.fileExists(atPath: context.entriesJSONPath.path) {
            do {
                _ = try? BackupManager.snapshot(
                    source: context.entriesJSONPath,
                    toDir: context.aerialWallBackupsDir,
                    retainCount: 3)
                var manifest = try EntriesJSONCodec.load(from: context.entriesJSONPath)
                let before = manifest.assets.count
                manifest.assets.removeAll { ownedIDs.contains($0.id) }
                manifest.categories.removeAll {
                    $0.id == Constants.AerialWallCategory.categoryID
                }
                let removedCount = before - manifest.assets.count
                try EntriesJSONCodec.writeAtomically(manifest, to: context.entriesJSONPath)
                report.assetsStripped = removedCount
                AerialLog.injection.info("stripped \(removedCount) assets from entries.json")
            } catch {
                AerialLog.injection.error("entries.json strip failed: \(error.localizedDescription, privacy: .public)")
                throw UninstallError.entriesUnwritable(error.localizedDescription)
            }
        }

        // 3. Delete the per-asset video + thumbnail files
        for id in ownedIDs {
            let video = context.wallpaperVideosDir.appending(path: "\(id).mov")
            let thumb = context.wallpaperThumbnailsDir.appending(path: "\(id).png")
            for path in [video, thumb] {
                if fm.fileExists(atPath: path.path) {
                    do { try fm.removeItem(at: path); report.filesDeleted += 1 }
                    catch { failed.append(path.path) }
                }
            }
        }

        // 4. Delete AerialWall storage (preserve backups in .preservingBackup mode)
        if fm.fileExists(atPath: context.aerialWallRoot.path) {
            if mode == .preservingBackup {
                for sub in ["library", "thumbs", "originals", "manifest.json"] {
                    let p = context.aerialWallRoot.appending(path: sub)
                    if fm.fileExists(atPath: p.path) {
                        try? fm.removeItem(at: p)
                    }
                }
                AerialLog.injection.info("preserved backups/ at \(context.aerialWallBackupsDir.path, privacy: .public)")
            } else {
                do { try fm.removeItem(at: context.aerialWallRoot) }
                catch { failed.append(context.aerialWallRoot.path) }
            }
            report.storageDeleted = true
        }

        // 5. Unload + delete LaunchAgent plist
        if fm.fileExists(atPath: context.launchAgentPlist.path) {
            try? LaunchAgentManager.uninstall(at: context.launchAgentPlist)
            try? fm.removeItem(at: context.launchAgentPlist)
            report.launchAgentRemoved = true
        }

        // 6. Restart WallpaperAgent (best-effort; tests skip via signalAgentOnFinish=false)
        if context.signalAgentOnFinish {
            do { _ = try await AgentRestart.restart() }
            catch { AerialLog.agent.warning("restart after uninstall failed: \(error.localizedDescription, privacy: .public)") }
        }

        if !failed.isEmpty {
            throw UninstallError.incomplete(failed)
        }

        AerialLog.injection.info("uninstall complete: \(report.assetsStripped) assets, \(report.filesDeleted) files")
        return report
    }
}

public struct UninstallReport: Sendable {
    public var assetsConsidered: Int = 0
    public var assetsStripped: Int = 0
    public var filesDeleted: Int = 0
    public var storageDeleted: Bool = false
    public var launchAgentRemoved: Bool = false
}

extension UninstallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .entriesUnwritable(let s):
            return "Could not edit entries.json during uninstall: \(s)"
        case .incomplete(let paths):
            return "Uninstall completed but \(paths.count) item(s) could not be deleted. Check Console for details."
        }
    }
}

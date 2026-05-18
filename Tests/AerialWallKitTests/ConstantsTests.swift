import Testing
import Foundation
@testable import AerialWallKit

@Suite("Constants — path locations & invariants")
struct ConstantsTests {

    static let allWritablePaths: [URL] = [
        Constants.wallpaperAerialsRoot,
        Constants.entriesJSONPath,
        Constants.manifestTarPath,
        Constants.manifestSourcePath,
        Constants.wallpaperVideosDir,
        Constants.wallpaperThumbnailsDir,
        Constants.wallpaperIndexPlist,
        Constants.wallpaperPrefs,
        Constants.wallpaperAerialPrefs,
        Constants.aerialWallRoot,
        Constants.aerialWallLibraryDir,
        Constants.aerialWallThumbsDir,
        Constants.aerialWallOriginalsDir,
        Constants.aerialWallManifestPath,
        Constants.aerialWallBackupsDir,
        Constants.launchAgentPlist,
    ]

    /// V5 + V22: every path is user-level — under `~`, never `/System/Library/`,
    /// never system `/Library/`, never `/Users/Shared/`.
    @Test func allPathsUserLevel() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for url in Self.allWritablePaths {
            let p = url.path
            #expect(p.hasPrefix(home), "\(p) not under \(home)")
            #expect(!p.hasPrefix("/System/"), "\(p) under /System/")
            #expect(!p.hasPrefix("/Users/Shared"), "\(p) under /Users/Shared")
            // Forbid system-level /Library (e.g. "/Library/Application Support/...")
            // but allow ~/Library which is captured by the home-prefix check above.
            if !p.hasPrefix(home) {
                #expect(!p.hasPrefix("/Library/"), "\(p) under system /Library/")
            }
        }
    }

    /// V5: Apple wallpaper paths live under `com.apple.wallpaper/aerials/`.
    @Test func appleWallpaperPathsRooted() {
        let root = Constants.wallpaperAerialsRoot.path
        #expect(Constants.entriesJSONPath.path.hasPrefix(root))
        #expect(Constants.manifestTarPath.path.hasPrefix(root))
        #expect(Constants.manifestSourcePath.path.hasPrefix(root))
        #expect(Constants.wallpaperVideosDir.path.hasPrefix(root))
        #expect(Constants.wallpaperThumbnailsDir.path.hasPrefix(root))
    }

    /// V22: AerialWall storage rooted at `~/Library/Application Support/AerialWall/`.
    @Test func aerialWallStorageRooted() {
        let root = Constants.aerialWallRoot.path
        #expect(Constants.aerialWallLibraryDir.path.hasPrefix(root))
        #expect(Constants.aerialWallThumbsDir.path.hasPrefix(root))
        #expect(Constants.aerialWallOriginalsDir.path.hasPrefix(root))
        #expect(Constants.aerialWallManifestPath.path.hasPrefix(root))
        #expect(Constants.aerialWallBackupsDir.path.hasPrefix(root))
    }

    /// V7: stock UUIDs are valid UUIDs in uppercase form.
    @Test func stockCategoryUUIDsValidAndUppercase() {
        let uuids = [
            Constants.StockCategory.landscapes,
            Constants.StockCategory.tahoeSubcategory,
            Constants.StockCategory.sequoiaSubcategory,
            Constants.StockCategory.sonomaSubcategory,
        ]
        for u in uuids {
            #expect(UUID(uuidString: u) != nil, "\(u) not a valid UUID")
            #expect(u == u.uppercased(), "\(u) not uppercased")
        }
    }

    /// V21: schema expectations pinned to observed Tahoe values.
    @Test func entriesSchemaConstantsPinned() {
        #expect(Constants.expectedEntriesSchemaVersion == 1)
        #expect(Constants.expectedLocalizationVersion == "22L-1")
    }

    /// V16/V17: wallpaper agent label matches the launchd label we'll send SIGTERM to.
    @Test func wallpaperAgentLabelMatchesApple() {
        #expect(Constants.wallpaperAgentLabel == "com.apple.wallpaper.agent")
    }
}

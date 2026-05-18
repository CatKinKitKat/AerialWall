import Foundation

public enum AerialWallKit {
    public static let version = "0.0.1"
}

public enum Constants {

    // MARK: - bundle / daemon identifiers

    public static let appBundleID = "com.aerialwall.app"
    public static let agentBundleID = "com.aerialwall.agent"
    public static let agentLaunchLabel = "com.aerialwall.agent"

    /// Apple system WallpaperAgent — the only Apple daemon we interact with on Tahoe.
    public static let wallpaperAgentLabel = "com.apple.wallpaper.agent"

    // MARK: - entries.json schema expectations (V21)

    public static let expectedEntriesSchemaVersion = 1
    public static let expectedLocalizationVersion = "22L-1"

    // MARK: - Apple wallpaper paths (V5, user-level only)

    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials/`
    public static var wallpaperAerialsRoot: URL {
        home.appending(path: "Library/Application Support/com.apple.wallpaper/aerials", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json`
    public static var entriesJSONPath: URL {
        wallpaperAerialsRoot.appending(path: "manifest/entries.json")
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/manifest.tar` (Apple-signed)
    public static var manifestTarPath: URL {
        wallpaperAerialsRoot.appending(path: "manifest/manifest.tar")
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/manifest.source` (remote tar URL)
    public static var manifestSourcePath: URL {
        wallpaperAerialsRoot.appending(path: "manifest/manifest.source")
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials/videos/`
    public static var wallpaperVideosDir: URL {
        wallpaperAerialsRoot.appending(path: "videos", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials/thumbnails/`
    public static var wallpaperThumbnailsDir: URL {
        wallpaperAerialsRoot.appending(path: "thumbnails", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`
    public static var wallpaperIndexPlist: URL {
        home.appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// `~/Library/Preferences/com.apple.wallpaper.plist`
    public static var wallpaperPrefs: URL {
        home.appending(path: "Library/Preferences/com.apple.wallpaper.plist")
    }

    /// `~/Library/Preferences/com.apple.wallpaper.aerial.plist` (new in Tahoe)
    public static var wallpaperAerialPrefs: URL {
        home.appending(path: "Library/Preferences/com.apple.wallpaper.aerial.plist")
    }

    // MARK: - AerialWall storage (V22)

    /// `~/Library/Application Support/AerialWall/`
    public static var aerialWallRoot: URL {
        home.appending(path: "Library/Application Support/AerialWall", directoryHint: .isDirectory)
    }

    public static var aerialWallLibraryDir: URL {
        aerialWallRoot.appending(path: "library", directoryHint: .isDirectory)
    }

    public static var aerialWallThumbsDir: URL {
        aerialWallRoot.appending(path: "thumbs", directoryHint: .isDirectory)
    }

    public static var aerialWallOriginalsDir: URL {
        aerialWallRoot.appending(path: "originals", directoryHint: .isDirectory)
    }

    public static var aerialWallManifestPath: URL {
        aerialWallRoot.appending(path: "manifest.json")
    }

    public static var aerialWallBackupsDir: URL {
        aerialWallRoot.appending(path: "backups", directoryHint: .isDirectory)
    }

    /// `~/Library/LaunchAgents/com.aerialwall.agent.plist`
    public static var launchAgentPlist: URL {
        home.appending(path: "Library/LaunchAgents/com.aerialwall.agent.plist")
    }

    // MARK: - Apple stock category UUIDs (verbatim — do NOT modify these entries)

    public enum StockCategory {
        /// Landscapes — top-level Apple category. Default parent for AerialWall imports.
        public static let landscapes = "A33A55D9-EDEA-4596-A850-6C10B54FBBB5"
        /// Tahoe subcategory under Landscapes.
        public static let tahoeSubcategory = "0DC99DD8-3386-4D1E-8878-C43E97EB710A"
        /// Sequoia subcategory.
        public static let sequoiaSubcategory = "78D1B993-DA5B-4CA6-90F0-865DA7F9091D"
        /// Sonoma subcategory.
        public static let sonomaSubcategory = "3CC63110-FF0E-4443-9A2D-63CD0795954E"
    }
}

import Foundation

// V52: Every public Error in AerialWallKit conforms to LocalizedError so the UI
// surfaces an actionable string rather than the raw enum case description.

extension InjectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .assetInvalid(let reason):
            return "This wallpaper can't be added: \(reason)"
        case .schemaIncompatible(let observed, let expected):
            return "macOS updated the wallpaper manifest format (v\(observed)). AerialWall only knows v\(expected) — update the app."
        }
    }
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let url):
            return "Can't back up — the file at \(url.lastPathComponent) doesn't exist."
        }
    }
}

extension ThumbnailError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceNotReadable(let url):
            return "Can't read \(url.lastPathComponent) for thumbnail generation."
        case .noVideoTrack:
            return "The file has no video track."
        case .encodingFailed:
            return "Could not generate a thumbnail PNG."
        }
    }
}

extension AerialWallManifestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .decodeFailed(let s):
            return "AerialWall's own manifest is corrupted: \(s). Delete ~/Library/Application Support/com.apple.wallpaper/aerials/manifest/aerialwall-manifest.json to reset."
        }
    }
}

// TranscodeError already conforms to LocalizedError in TranscodeEngine.swift.

extension LaunchAgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .launchctlFailed(let code, let err):
            return "launchctl exited \(code): \(err)"
        }
    }
}

extension AgentRestartError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .agentNotFound(let label):
            return "WallpaperAgent (\(label)) is not running. Open System Settings → Wallpaper once, then try again."
        case .launchctlFailed(let code):
            return "launchctl refused to restart the wallpaper agent (exit \(code))."
        case .signalFailed(let errno):
            return "kill(2) failed with errno \(errno) — the agent may be running as a different user."
        case .respawnTimeout:
            return "WallpaperAgent did not come back online after restart."
        }
    }
}

extension PersistenceWatcherError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let url):
            return "Can't watch \(url.lastPathComponent) for changes."
        }
    }
}

extension EntriesJSONError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileMissing(let url):
            return "macOS hasn't created \(url.lastPathComponent) yet. Open System Settings → Wallpaper at least once to bootstrap it."
        case .invalidSchema(let s):
            return "entries.json is malformed: \(s)"
        case .unsupportedVersion(let observed, let expected):
            return "entries.json is version \(observed); AerialWall only supports v\(expected). Update the app."
        }
    }
}

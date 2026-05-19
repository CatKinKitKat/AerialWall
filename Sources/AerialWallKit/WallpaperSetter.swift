import Foundation

public enum WallpaperSetterError: Error, LocalizedError {
    case indexPlistMissing
    case indexPlistCorrupt(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .indexPlistMissing:   return "Wallpaper index not found — open System Settings → Wallpaper at least once."
        case .indexPlistCorrupt(let s): return "Wallpaper index is unreadable: \(s)"
        case .writeFailed(let s):  return "Could not write wallpaper selection: \(s)"
        }
    }
}

/// Applies an injected AerialWall asset as the current wallpaper by writing
/// to `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`
/// and signalling WallpaperAgent to reload (V25 — only valid after injection
/// into entries.json, which ImportService guarantees).
public enum WallpaperSetter {

    public static func apply(assetID: String) throws {
        AerialLog.setter.info("apply assetID=\(assetID, privacy: .public)")
        let url = Constants.wallpaperIndexPlist
        guard FileManager.default.fileExists(atPath: url.path) else {
            AerialLog.setter.error("Index.plist missing at \(url.path, privacy: .public)")
            throw WallpaperSetterError.indexPlistMissing
        }

        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                options: [], format: nil
            )
        } catch {
            throw WallpaperSetterError.indexPlistCorrupt("\(error)")
        }
        guard var outer = raw as? [String: Any] else {
            throw WallpaperSetterError.indexPlistCorrupt("unexpected root type")
        }

        // Build the binary-encoded Configuration sub-plist the agent expects.
        let configData: Data
        do {
            configData = try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID] as [String: Any],
                format: .binary,
                options: 0
            )
        } catch {
            throw WallpaperSetterError.writeFailed("could not encode assetID: \(error)")
        }

        let choice: [String: Any] = [
            "Configuration": configData,
            "Files": [] as [Any],
            "Provider": "com.apple.wallpaper.choice.aerials",
        ]
        // NSNull is not valid in binary plist (format 200); omit Shuffle instead.
        let linked: [String: Any] = [
            "Content": [
                "Choices": [choice],
            ] as [String: Any],
            "LastSet": Date(),
            "LastUse": Date(),
        ]

        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            var block = (outer[key] as? [String: Any]) ?? [:]
            block["Linked"] = linked
            block["Type"] = "linked"
            outer[key] = block
        }
        // V53: clear per-display and per-Space overrides so the new wallpaper
        // applies uniformly across every monitor and Mission Control space.
        // Leaving `Displays` populated causes external monitors to retain the
        // previous wallpaper after Apply.
        outer["Displays"] = [String: Any]()
        outer["Spaces"]   = [String: Any]()

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: outer, format: .binary, options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw WallpaperSetterError.writeFailed("\(error)")
        }

        AerialLog.setter.info("Index.plist written, signalling WallpaperAgent")
        // Signal WallpaperAgent so it picks up the new selection immediately.
        // Best-effort — if it fails, the change takes effect on the next
        // natural agent cycle.
        Task.detached {
            do {
                try await AgentRestart.restart()
            } catch {
                AerialLog.setter.warning("agent restart after apply failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

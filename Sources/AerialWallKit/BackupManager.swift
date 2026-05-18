import Foundation

public enum BackupError: Error, Equatable {
    case sourceMissing(URL)
}

public enum BackupManager {

    /// File-safe ISO8601 (replaces `:` with `-`).
    static func timestamp(_ date: Date = .now) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    static let backupPrefix = "entries.json."
    static let backupSuffix = ".bak"

    /// V30: snapshot before injection. Returns the snapshot path. Prunes oldest
    /// backups beyond `retainCount`.
    @discardableResult
    public static func snapshot(
        source: URL = Constants.entriesJSONPath,
        toDir: URL = Constants.aerialWallBackupsDir,
        retainCount: Int = 3,
        now: Date = .now
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BackupError.sourceMissing(source)
        }
        try FileManager.default.createDirectory(at: toDir, withIntermediateDirectories: true)
        let target = toDir.appending(path: "\(backupPrefix)\(timestamp(now))\(backupSuffix)")
        try FileManager.default.copyItem(at: source, to: target)
        try prune(in: toDir, retainCount: retainCount)
        return target
    }

    /// Newest-first listing of snapshots in `dir`.
    public static func list(in dir: URL = Constants.aerialWallBackupsDir) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        return urls
            .filter {
                $0.lastPathComponent.hasPrefix(backupPrefix)
                && $0.lastPathComponent.hasSuffix(backupSuffix)
            }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return aDate > bDate
            }
    }

    /// Delete snapshots older than the `retainCount` most recent.
    public static func prune(in dir: URL, retainCount: Int) throws {
        let backups = list(in: dir)
        guard backups.count > retainCount else { return }
        for url in backups.dropFirst(retainCount) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Restore a snapshot to `dest`. Atomic, mirrors entries.json write semantics.
    public static func restore(from backup: URL,
                               to dest: URL = Constants.entriesJSONPath) throws {
        let data = try Data(contentsOf: backup)
        try data.write(to: dest, options: .atomic)
    }
}

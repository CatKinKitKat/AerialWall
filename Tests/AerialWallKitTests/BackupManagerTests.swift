import Testing
import Foundation
@testable import AerialWallKit

@Suite("BackupManager — V30 snapshot + retain N")
struct BackupManagerTests {

    private func makeSandbox() throws -> (source: URL, dir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "entries.json")
        try Data(#"{"version":1}"#.utf8).write(to: source)
        let dir = root.appending(path: "backups", directoryHint: .isDirectory)
        return (source, dir)
    }

    @Test func snapshotCreatesFile() throws {
        let (source, dir) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let snap = try BackupManager.snapshot(source: source, toDir: dir, retainCount: 3)
        #expect(FileManager.default.fileExists(atPath: snap.path))
        #expect(snap.lastPathComponent.hasPrefix("entries.json."))
        #expect(snap.pathExtension == "bak")
    }

    @Test func snapshotMissingSourceThrows() {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).json")
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "out-\(UUID().uuidString)")
        #expect(throws: BackupError.self) {
            try BackupManager.snapshot(source: nowhere, toDir: dir)
        }
    }

    /// V30: only the N most recent snapshots are retained.
    @Test func pruneRetainsOnlyNMostRecent() throws {
        let (source, dir) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        // Five snapshots with distinct timestamps.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var created: [URL] = []
        for i in 0..<5 {
            let snap = try BackupManager.snapshot(
                source: source, toDir: dir, retainCount: 999,
                now: base.addingTimeInterval(TimeInterval(i))
            )
            created.append(snap)
            // Adjust mtime so list() ordering is deterministic regardless of fs timestamp resolution.
            try FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(TimeInterval(i))],
                ofItemAtPath: snap.path
            )
        }

        try BackupManager.prune(in: dir, retainCount: 3)
        let remaining = BackupManager.list(in: dir)
        #expect(remaining.count == 3)
        // Newest-first ordering means the three latest should survive.
        let remainingNames = Set(remaining.map(\.lastPathComponent))
        let survivors = Set(created.suffix(3).map(\.lastPathComponent))
        #expect(remainingNames == survivors)
    }

    @Test func restoreRoundTrips() throws {
        let (source, dir) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let snap = try BackupManager.snapshot(source: source, toDir: dir, retainCount: 3)

        try Data(#"{"version":99}"#.utf8).write(to: source)  // corrupt source
        try BackupManager.restore(from: snap, to: source)
        let restored = String(data: try Data(contentsOf: source), encoding: .utf8)
        #expect(restored == #"{"version":1}"#)
    }

    @Test func listReturnsNewestFirst() throws {
        let (source, dir) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<3 {
            let snap = try BackupManager.snapshot(
                source: source, toDir: dir, retainCount: 999,
                now: base.addingTimeInterval(TimeInterval(i))
            )
            try FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(TimeInterval(i))],
                ofItemAtPath: snap.path
            )
        }
        let listed = BackupManager.list(in: dir)
        let mtimes = listed.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        #expect(mtimes == mtimes.sorted(by: >))
    }
}

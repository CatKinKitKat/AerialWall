import Testing
import Foundation
@testable import AerialWallKit

@Suite("PersistenceWatcher — V9 FSEvents stream, V20 drift trigger")
struct PersistenceWatcherTests {

    private func tmpFile(_ contents: String = "x") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pw-\(UUID().uuidString).txt")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func cannotOpenMissingFile() {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).txt")
        #expect(throws: PersistenceWatcherError.self) {
            _ = try PersistenceWatcher.eventStream(for: nowhere)
        }
    }

    /// Helper: race stream-yielded-once vs a 2s timeout.
    private func awaitFirstEvent<T: Sendable>(stream: AsyncStream<T>) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                for await event in stream { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @Test func writeTriggersEvent() async throws {
        let url = try tmpFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let stream = try PersistenceWatcher.eventStream(for: url)
        // Mutate after a tick so the dispatch source is installed.
        let writer = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            try? "y".write(to: url, atomically: true, encoding: .utf8)
        }
        let first: ()? = await awaitFirstEvent(stream: stream)
        writer.cancel()
        #expect(first != nil, "no event fired within 2s")
    }

    @Test func mergedStreamYieldsURLs() async throws {
        let a = try tmpFile()
        let b = try tmpFile()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }

        let merged = PersistenceWatcher.mergedStream(for: [a, b])
        let writer = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            try? "1".write(to: a, atomically: true, encoding: .utf8)
            try? await Task.sleep(nanoseconds: 50_000_000)
            try? "2".write(to: b, atomically: true, encoding: .utf8)
        }
        let first = await awaitFirstEvent(stream: merged)
        writer.cancel()
        #expect(first != nil)
        #expect(first == a || first == b)
    }
}

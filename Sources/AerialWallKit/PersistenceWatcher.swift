@preconcurrency import Foundation
import Darwin

public enum PersistenceWatcherError: Error, Equatable {
    case cannotOpen(URL)
}

/// V9 + V19: FSEvents-style file watcher built on `DispatchSource.makeFileSystemObjectSource`.
/// Yields an event each time the watched file is written, renamed, or deleted.
/// `manifest.tar` re-pulls and `entries.json` rewrites both trip it — the consumer
/// then reconciles AerialWall manifest entries against `entries.json` (V20).
public enum PersistenceWatcher {

    /// AsyncStream of events for a single file. Cancelling the consuming task
    /// closes the underlying fd via `onTermination`.
    public static func eventStream(for url: URL) throws -> AsyncStream<Void> {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { throw PersistenceWatcherError.cannotOpen(url) }

        return AsyncStream { continuation in
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { continuation.yield(()) }
            source.setCancelHandler { close(fd) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }

    /// Merge events from multiple URLs into one stream.
    public static func mergedStream(for urls: [URL]) -> AsyncStream<URL> {
        AsyncStream { continuation in
            let subTasks: [Task<Void, Never>] = urls.compactMap { url in
                guard let sub = try? eventStream(for: url) else { return nil }
                return Task {
                    for await _ in sub {
                        if Task.isCancelled { return }
                        continuation.yield(url)
                    }
                }
            }
            continuation.onTermination = { _ in
                for t in subTasks { t.cancel() }
            }
        }
    }
}

import Testing
import Foundation
@testable import AerialWallKit

@Suite("V52 — every public error type has an actionable LocalizedError description")
struct LocalizedErrorTests {

    @Test func injectionErrorsHaveDescriptions() {
        let cases: [InjectionError] = [
            .assetInvalid(reason: "bad UUID"),
            .schemaIncompatible(observed: 2, expected: 1),
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }

    @Test func backupErrorHasDescription() {
        let url = URL(fileURLWithPath: "/tmp/x")
        #expect((BackupError.sourceMissing(url) as LocalizedError).errorDescription != nil)
    }

    @Test func thumbnailErrorsHaveDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let cases: [ThumbnailError] = [
            .sourceNotReadable(url),
            .noVideoTrack,
            .encodingFailed,
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }

    @Test func manifestErrorHasDescription() {
        #expect((AerialWallManifestError.decodeFailed("bad")
                 as LocalizedError).errorDescription?.contains("AerialWall") == true)
    }

    @Test func transcodeErrorsHaveDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let cases: [TranscodeError] = [
            .noVideoTrack(url),
            .inputFormatUnsupported(url),
            .writerSetupFailed("nope"),
            .readerSetupFailed("nope"),
            .encodeFailed("nope"),
            .outputNotPlayable(url),
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }

    @Test func launchAgentErrorHasDescription() {
        let e: LaunchAgentError = .launchctlFailed(exitCode: 42, stderr: "nope")
        #expect((e as LocalizedError).errorDescription?.contains("42") == true)
    }

    @Test func agentRestartErrorsHaveDescriptions() {
        let cases: [AgentRestartError] = [
            .agentNotFound(label: "com.apple.x"),
            .launchctlFailed(exitCode: 1),
            .signalFailed(errno: 13),
            .respawnTimeout,
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }

    @Test func watcherErrorHasDescription() {
        let url = URL(fileURLWithPath: "/tmp/x")
        #expect((PersistenceWatcherError.cannotOpen(url)
                 as LocalizedError).errorDescription != nil)
    }

    @Test func entriesJSONErrorsHaveDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/entries.json")
        let cases: [EntriesJSONError] = [
            .fileMissing(url),
            .invalidSchema("bad"),
            .unsupportedVersion(observed: 2, expected: 1),
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }

    @Test func wallpaperSetterErrorsHaveDescriptions() {
        let cases: [WallpaperSetterError] = [
            .indexPlistMissing,
            .indexPlistCorrupt("nope"),
            .writeFailed("nope"),
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }

    @Test func uninstallErrorsHaveDescriptions() {
        let cases: [UninstallError] = [
            .entriesUnwritable("nope"),
            .incomplete(["/tmp/x"]),
        ]
        for e in cases {
            #expect((e as LocalizedError).errorDescription?.isEmpty == false)
        }
    }
}

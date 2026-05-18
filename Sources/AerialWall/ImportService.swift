import Foundation
import AVFoundation
import AerialWallKit

/// Single-shot import pipeline: transcode → thumbnail → backup → inject → restart agent.
/// Glue between AerialWallKit engines; lives in the app target since the agent
/// doesn't import (it only re-injects existing entries on drift).
enum ImportService {

    typealias ProgressHandler = @Sendable (Double) -> Void

    static func run(
        source: URL,
        name: String,
        progress: ProgressHandler? = nil
    ) async throws -> AerialWallEntry {
        let uuid = UUID().uuidString.uppercased()

        // Ensure target dirs exist.
        try FileManager.default.createDirectory(at: Constants.aerialWallLibraryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Constants.aerialWallThumbsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Constants.wallpaperVideosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Constants.wallpaperThumbnailsDir, withIntermediateDirectories: true)

        let kitVideoPath = Constants.aerialWallLibraryDir.appending(path: "\(uuid).mov")
        let kitThumbPath = Constants.aerialWallThumbsDir.appending(path: "\(uuid).png")

        progress?(0.05)

        // T5 transcode (V1, V2, V3, V4) — also runs the .isPlayable validation.
        try await TranscodeEngine.transcodeAndValidate(input: source, output: kitVideoPath)
        progress?(0.65)

        // T6 thumbnail.
        try await ThumbnailGenerator.generate(from: kitVideoPath, to: kitThumbPath)
        progress?(0.70)

        // Read final dimensions / duration for the AerialWall manifest.
        let avAsset = AVURLAsset(url: kitVideoPath)
        let duration = (try? await avAsset.load(.duration).seconds) ?? 0
        let tracks = (try? await avAsset.loadTracks(withMediaType: .video)) ?? []
        let size = (try? await tracks.first?.load(.naturalSize)) ?? .zero
        let resolution = size.width > 0 && size.height > 0
            ? "\(Int(size.width))x\(Int(size.height))"
            : "—"

        // V30: snapshot entries.json before we touch it.
        _ = try? BackupManager.snapshot()

        // Copy mov + png into Apple's wallpaper dir under our UUID. V31: real copy,
        // not hardlink — keeps refcount semantics simple if the kit-side file is later removed.
        let appleVideoPath = Constants.wallpaperVideosDir.appending(path: "\(uuid).mov")
        let appleThumbPath = Constants.wallpaperThumbnailsDir.appending(path: "\(uuid).png")
        try? FileManager.default.removeItem(at: appleVideoPath)
        try? FileManager.default.removeItem(at: appleThumbPath)
        try FileManager.default.copyItem(at: kitVideoPath, to: appleVideoPath)
        try FileManager.default.copyItem(at: kitThumbPath, to: appleThumbPath)
        progress?(0.80)

        // T4 inject into entries.json (V7, V13, V14, V21).
        let injectionAsset = Asset(
            id: uuid,
            accessibilityLabel: name,
            categories: [Constants.StockCategory.landscapes],
            subcategories: [Constants.StockCategory.tahoeSubcategory],
            includeInShuffle: false,
            localizedNameKey: name,                     // V9: rendered literally
            preferredOrder: -100,                       // surface at top
            previewImage: appleThumbPath.absoluteString,
            shotID: "AERIALWALL_\(uuid.prefix(8))",
            showInTopLevel: true,
            urlSDR4K240: appleVideoPath.absoluteString
        )
        try InjectionEngine.inject(injectionAsset)
        progress?(0.90)

        // T8 restart wallpaper agent so it picks up the new entry. Best-effort —
        // failures here don't roll back; entries.json mutation already succeeded.
        _ = try? await AgentRestart.restart()
        progress?(1.0)

        // Persist the AerialWall manifest entry.
        let entry = AerialWallEntry(
            uuid: uuid,
            name: name,
            originalFilename: source.lastPathComponent,
            importedAt: .now,
            durationSeconds: duration,
            resolution: resolution,
            videoPath: kitVideoPath.path,
            thumbPath: kitThumbPath.path,
            isInjected: true
        )
        try AerialWallManifestStore.upsert(entry)
        return entry
    }
}

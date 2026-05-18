import Foundation
import AVFoundation
import AerialWallKit

/// Two-phase import pipeline:
/// - phase 1 (`prepareDraft`): cheap probe — duration, resolution, preview PNG.
///   Runs in seconds; output feeds the import modal.
/// - phase 2 (`run`): full transcode → thumbnail → backup → inject → restart.
///   Long-running; expects user-confirmed metadata.
enum ImportService {

    typealias ProgressHandler = @Sendable (Double) -> Void

    static func prepareDraft(source: URL) async throws -> ImportDraft {
        // Quick thumbnail to a tmp file. Cancellation deletes it.
        let tmpThumb = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-draft-\(UUID().uuidString).png")
        try await ThumbnailGenerator.generate(from: source, to: tmpThumb)

        let avAsset = AVURLAsset(url: source)
        let duration = (try? await avAsset.load(.duration).seconds) ?? 0
        let tracks = (try? await avAsset.loadTracks(withMediaType: .video)) ?? []
        let size = (try? await tracks.first?.load(.naturalSize)) ?? .zero
        let resolution = size.width > 0 && size.height > 0
            ? "\(Int(size.width))×\(Int(size.height))"
            : "—"

        return ImportDraft(
            source: source,
            previewThumbnailPath: tmpThumb,
            durationSeconds: duration,
            sourceResolution: resolution,
            suggestedName: source.deletingPathExtension().lastPathComponent
        )
    }

    static func run(
        source: URL,
        metadata: ImportMetadata,
        progress: ProgressHandler? = nil
    ) async throws -> AerialWallEntry {
        let uuid = UUID().uuidString.uppercased()

        try FileManager.default.createDirectory(at: Constants.aerialWallLibraryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Constants.aerialWallThumbsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Constants.wallpaperVideosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Constants.wallpaperThumbnailsDir, withIntermediateDirectories: true)

        let kitVideoPath = Constants.aerialWallLibraryDir.appending(path: "\(uuid).mov")
        let kitThumbPath = Constants.aerialWallThumbsDir.appending(path: "\(uuid).png")

        progress?(0.02)

        // Probe source duration so transcode can emit live progress.
        let inputDuration = (try? await AVURLAsset(url: source).load(.duration).seconds) ?? 0

        // T5 transcode (V1, V2, V3, V4). 0.02 … 0.85 ≈ long pole of the import.
        var opts = TranscodeOptions()
        opts.inputDurationSeconds = inputDuration > 0 ? inputDuration : nil
        try await TranscodeEngine.transcodeAndValidate(
            input: source, output: kitVideoPath, options: opts
        ) { ratio in
            progress?(0.02 + ratio * 0.83)
        }
        progress?(0.85)

        // T6 thumbnail.
        try await ThumbnailGenerator.generate(from: kitVideoPath, to: kitThumbPath)
        progress?(0.90)

        // Read final dimensions/duration of the transcoded file for the manifest.
        let avAsset = AVURLAsset(url: kitVideoPath)
        let duration = (try? await avAsset.load(.duration).seconds) ?? 0
        let tracks = (try? await avAsset.loadTracks(withMediaType: .video)) ?? []
        let size = (try? await tracks.first?.load(.naturalSize)) ?? .zero
        let resolution = size.width > 0 && size.height > 0
            ? "\(Int(size.width))x\(Int(size.height))"
            : "—"

        // V30: snapshot entries.json before mutation.
        _ = try? BackupManager.snapshot()

        // V31: real copy, not hardlink.
        let appleVideoPath = Constants.wallpaperVideosDir.appending(path: "\(uuid).mov")
        let appleThumbPath = Constants.wallpaperThumbnailsDir.appending(path: "\(uuid).png")
        try? FileManager.default.removeItem(at: appleVideoPath)
        try? FileManager.default.removeItem(at: appleThumbPath)
        try FileManager.default.copyItem(at: kitVideoPath, to: appleVideoPath)
        try FileManager.default.copyItem(at: kitThumbPath, to: appleThumbPath)
        progress?(0.95)

        // T4 inject into entries.json. V27: include the AerialWall category in
        // the same atomic write — idempotent if it's already present.
        //
        // V41: URLs are synthesized https:// strings matching Apple's pattern,
        // NOT file:// to the local files. The wallpaper runtime auto-discovers
        // the local mov/png at videos/<UUID>.mov + thumbnails/<UUID>.png by
        // UUID convention; the URL is only used as a download fallback. file://
        // URLs cause initial selection to work but unlock-rebind to fail with
        // a gray fallback (B12).
        let previewURL = "https://sylvan.apple.com/aerialwall/\(uuid)/thumbnail.png"
        let videoURL = "https://sylvan.apple.com/aerialwall/\(uuid)/video.mov"

        let injectionAsset = Asset(
            id: uuid,
            accessibilityLabel: metadata.name,
            categories: [Constants.AerialWallCategory.categoryID],
            subcategories: [Constants.AerialWallCategory.subcategoryID],
            includeInShuffle: true,                          // match Apple's default
            localizedNameKey: metadata.name,                 // V9: rendered literally
            preferredOrder: 1,                               // match Apple's small-positive convention
            previewImage: previewURL,
            shotID: "AERIALWALL_\(uuid.prefix(8))",
            showInTopLevel: true,
            urlSDR4K240: videoURL
        )
        let aerialWallCategory = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: uuid,
            previewImageURL: previewURL
        )
        try InjectionEngine.inject(injectionAsset, ensureCategory: aerialWallCategory)
        progress?(0.98)

        _ = try? await AgentRestart.restart()
        progress?(1.0)

        let entry = AerialWallEntry(
            uuid: uuid,
            name: metadata.name,
            description: metadata.description,
            categoryID: Constants.AerialWallCategory.categoryID,
            subcategoryID: Constants.AerialWallCategory.subcategoryID,
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

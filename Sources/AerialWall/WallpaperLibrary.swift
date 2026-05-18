import Foundation
import AppKit
import AerialWallKit
import Observation
import UniformTypeIdentifiers

@Observable @MainActor
final class WallpaperViewModel: Identifiable {
    let id: String
    var name: String
    var description: String
    var categoryID: String
    var subcategoryID: String
    var resolution: String
    var durationSeconds: Double
    var importedAt: Date
    var videoPath: String
    var thumbPath: String
    var isInjected: Bool

    var encodingProgress: Double? = nil
    var errorMessage: String? = nil

    init(entry: AerialWallEntry) {
        self.id = entry.uuid
        self.name = entry.name
        self.description = entry.description
        self.categoryID = entry.categoryID
        self.subcategoryID = entry.subcategoryID
        self.resolution = entry.resolution
        self.durationSeconds = entry.durationSeconds
        self.importedAt = entry.importedAt
        self.videoPath = entry.videoPath
        self.thumbPath = entry.thumbPath
        self.isInjected = entry.isInjected
    }

    static func pending(metadata: ImportMetadata) -> WallpaperViewModel {
        let entry = AerialWallEntry(
            uuid: UUID().uuidString.uppercased(),
            name: metadata.name,
            description: metadata.description,
            categoryID: Constants.AerialWallCategory.categoryID,
            subcategoryID: Constants.AerialWallCategory.subcategoryID,
            originalFilename: "",
            importedAt: .now,
            durationSeconds: 0,
            resolution: "—",
            videoPath: "",
            thumbPath: "",
            isInjected: false
        )
        let vm = WallpaperViewModel(entry: entry)
        vm.encodingProgress = 0
        return vm
    }

    var durationString: String {
        let total = Int(durationSeconds)
        guard total > 0 else { return "—" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@Observable @MainActor
final class WallpaperLibrary {
    private(set) var wallpapers: [WallpaperViewModel] = []
    var importError: String? = nil
    var showOnboarding: Bool = false

    /// Set when a file has been picked + previewed; drives the import sheet.
    /// `nil` ⇒ no sheet.
    var activeDraft: ImportDraft? = nil

    /// Set when user invokes Rename; drives the rename sheet.
    var renameTarget: WallpaperViewModel? = nil

    /// Set when user invokes Remove; drives the confirmation alert.
    var removeTarget: WallpaperViewModel? = nil

    func load() async {
        do {
            let manifest = try AerialWallManifestStore.load()
            self.wallpapers = manifest.wallpapers.map(WallpaperViewModel.init)
        } catch {
            self.importError = "Failed to load manifest: \(error)"
        }
        self.showOnboarding = !FileManager.default.fileExists(atPath: Constants.entriesJSONPath.path)
    }

    func openImportPanel() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            await prepareDraft(from: url)
        }
    }

    func prepareDraft(from source: URL) async {
        do {
            let draft = try await ImportService.prepareDraft(source: source)
            self.activeDraft = draft
        } catch {
            self.importError = "Couldn't preview \"\(source.lastPathComponent)\": \(error)"
        }
    }

    func cancelDraft() {
        if let draft = activeDraft {
            try? FileManager.default.removeItem(at: draft.previewThumbnailPath)
        }
        activeDraft = nil
    }

    /// User confirmed the modal. Kick the full pipeline; sheet dismisses immediately.
    func confirmImport(_ draft: ImportDraft, metadata: ImportMetadata) async {
        // Dismiss sheet first so the table+progress is visible during transcode.
        activeDraft = nil

        let placeholder = WallpaperViewModel.pending(metadata: metadata)
        wallpapers.append(placeholder)

        do {
            let entry = try await ImportService.run(source: draft.source, metadata: metadata) { progress in
                Task { @MainActor in
                    placeholder.encodingProgress = progress
                }
            }
            if let idx = wallpapers.firstIndex(where: { $0.id == placeholder.id }) {
                wallpapers[idx] = WallpaperViewModel(entry: entry)
            }
        } catch {
            placeholder.encodingProgress = nil
            placeholder.errorMessage = "\(error)"
        }

        try? FileManager.default.removeItem(at: draft.previewThumbnailPath)
    }

    // MARK: - rename

    func rename(_ vm: WallpaperViewModel, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != vm.name else { return }
        do {
            // Re-inject entries.json entry with updated labels (V9, V10).
            let entriesManifest = try EntriesJSONCodec.load(from: Constants.entriesJSONPath)
            if var assetCopy = entriesManifest.assets.first(where: { $0.id == vm.id }) {
                assetCopy.accessibilityLabel = trimmed
                assetCopy.localizedNameKey = trimmed
                try InjectionEngine.inject(assetCopy)
            }
            try AerialWallManifestStore.update(uuid: vm.id) { $0.name = trimmed }
            _ = try? await AgentRestart.restart()
            vm.name = trimmed
        } catch {
            importError = "Rename failed: \(error)"
        }
    }

    // MARK: - remove (mini-T15)

    func remove(_ vm: WallpaperViewModel) async {
        let id = vm.id
        do {
            try InjectionEngine.remove(id: id)
            // Apple-side files
            try? FileManager.default.removeItem(
                at: Constants.wallpaperVideosDir.appending(path: "\(id).mov"))
            try? FileManager.default.removeItem(
                at: Constants.wallpaperThumbnailsDir.appending(path: "\(id).png"))
            // AerialWall-side files
            if !vm.videoPath.isEmpty {
                try? FileManager.default.removeItem(atPath: vm.videoPath)
            }
            if !vm.thumbPath.isEmpty {
                try? FileManager.default.removeItem(atPath: vm.thumbPath)
            }
            try AerialWallManifestStore.remove(uuid: id)
            _ = try? await AgentRestart.restart()
            wallpapers.removeAll { $0.id == id }
        } catch {
            importError = "Remove failed: \(error)"
        }
    }
}

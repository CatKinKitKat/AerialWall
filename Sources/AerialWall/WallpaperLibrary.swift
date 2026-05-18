import Foundation
import AppKit
import AerialWallKit
import Observation
import UniformTypeIdentifiers

@Observable @MainActor
final class WallpaperViewModel: Identifiable {
    let id: String
    var name: String
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
        self.resolution = entry.resolution
        self.durationSeconds = entry.durationSeconds
        self.importedAt = entry.importedAt
        self.videoPath = entry.videoPath
        self.thumbPath = entry.thumbPath
        self.isInjected = entry.isInjected
    }

    static func pending(filename: String) -> WallpaperViewModel {
        let entry = AerialWallEntry(
            uuid: UUID().uuidString.uppercased(),
            name: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
            originalFilename: filename,
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
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video, UTType("public.video") ?? .movie]
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            await beginImport(from: url)
        }
    }

    func beginImport(from source: URL) async {
        let placeholder = WallpaperViewModel.pending(filename: source.lastPathComponent)
        wallpapers.append(placeholder)
        let displayName = placeholder.name

        do {
            let entry = try await ImportService.run(source: source, name: displayName) { progress in
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
    }
}

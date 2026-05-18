import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var library: WallpaperLibrary
    let filter: SidebarItem
    @State private var selectedID: WallpaperViewModel.ID?

    private var displayed: [WallpaperViewModel] {
        let sorted = library.wallpapers.sorted { $0.importedAt > $1.importedAt }
        if filter == .recentlyAdded { return Array(sorted.prefix(20)) }
        return sorted
    }

    var body: some View {
        Group {
            if displayed.isEmpty {
                ContentUnavailableView {
                    Label("No Wallpapers Yet", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Import a video to use it as a native aerial wallpaper.")
                } actions: {
                    Button("Import Video…") {
                        Task { await library.openImportPanel() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Table(displayed, selection: $selectedID) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Duration") { Text($0.durationString).monospacedDigit() }
                    TableColumn("Resolution") { Text($0.resolution) }
                    TableColumn("Status") { StatusCell(wallpaper: $0) }
                    TableColumn("Added") { Text($0.importedAt, style: .relative) }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: WallpaperViewModel.ID.self) { ids in
                    if let wp = wallpaper(for: ids) {
                        Button("Rename…") { library.renameTarget = wp }
                        Button("Show in Finder") { reveal(wp) }
                        Button("Copy UUID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(wp.id, forType: .string)
                        }
                        Divider()
                        Button("Remove", role: .destructive) { library.removeTarget = wp }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await library.openImportPanel() }
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .navigationTitle("AerialWall")
        .onDrop(of: [.movie, .mpeg4Movie, .quickTimeMovie, .video], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        await library.prepareDraft(from: url)
                    }
                }
            }
            return true
        }
    }

    private func wallpaper(for ids: Set<WallpaperViewModel.ID>) -> WallpaperViewModel? {
        guard let id = ids.first else { return nil }
        return displayed.first { $0.id == id }
    }

    private func reveal(_ wp: WallpaperViewModel) {
        guard !wp.videoPath.isEmpty else { return }
        NSWorkspace.shared.selectFile(wp.videoPath, inFileViewerRootedAtPath: "")
    }
}

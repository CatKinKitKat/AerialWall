import SwiftUI
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
                        await library.beginImport(from: url)
                    }
                }
            }
            return true
        }
    }
}

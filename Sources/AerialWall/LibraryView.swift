import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

struct LibraryView: View {
    @Bindable var library: WallpaperLibrary
    let filter: SidebarItem
    @State private var selectedID: WallpaperViewModel.ID?
    @AppStorage("aerialwall.libraryViewMode") private var viewModeRaw = LibraryViewMode.grid.rawValue

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .list
    }

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
                switch viewMode {
                case .list: listView
                case .grid: gridView
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $viewModeRaw) {
                    ForEach(LibraryViewMode.allCases) { mode in
                        Image(systemName: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Toggle list / grid view")
            }
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

    // MARK: - list

    private var listView: some View {
        Table(displayed, selection: $selectedID) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("Duration") { Text($0.durationString).monospacedDigit() }
            TableColumn("Resolution") { Text($0.resolution) }
            TableColumn("Status") { StatusCell(wallpaper: $0) }
            TableColumn("Added") { Text($0.importedAt, style: .relative) }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: WallpaperViewModel.ID.self) { ids in
            contextMenu(for: wallpaper(for: ids))
        } primaryAction: { ids in
            if let wp = wallpaper(for: ids) { Task { await library.apply(wp) } }
        }
    }

    // MARK: - grid

    private let gridColumns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(displayed) { wp in
                    WallpaperCard(wallpaper: wp, isSelected: selectedID == wp.id)
                        .onTapGesture { selectedID = wp.id }
                        .onTapGesture(count: 2) { Task { await library.apply(wp) } }
                        .contextMenu { contextMenu(for: wp) }
                }
            }
            .padding(16)
        }
    }

    // MARK: - shared

    @ViewBuilder
    private func contextMenu(for wp: WallpaperViewModel?) -> some View {
        if let wp {
            Button("Apply as Wallpaper") { Task { await library.apply(wp) } }
            Divider()
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

    private func wallpaper(for ids: Set<WallpaperViewModel.ID>) -> WallpaperViewModel? {
        guard let id = ids.first else { return nil }
        return displayed.first { $0.id == id }
    }

    private func reveal(_ wp: WallpaperViewModel) {
        guard !wp.videoPath.isEmpty else { return }
        NSWorkspace.shared.selectFile(wp.videoPath, inFileViewerRootedAtPath: "")
    }
}

private struct WallpaperCard: View {
    let wallpaper: WallpaperViewModel
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let nsImage = thumbnailImage() {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .aspectRatio(16/9, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                if wallpaper.isApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.white, .green)
                        .padding(6)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(8)
                }
                if let p = wallpaper.encodingProgress {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(wallpaper.resolution)
                    Text("·")
                    Text(wallpaper.durationString).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func thumbnailImage() -> NSImage? {
        guard !wallpaper.thumbPath.isEmpty,
              FileManager.default.fileExists(atPath: wallpaper.thumbPath)
        else { return nil }
        return NSImage(contentsOfFile: wallpaper.thumbPath)
    }
}

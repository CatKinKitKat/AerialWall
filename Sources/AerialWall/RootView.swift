import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable {
    case allWallpapers
    case recentlyAdded
    case logs
}

struct RootView: View {
    @Bindable var library: WallpaperLibrary
    @State private var selection: SidebarItem? = .allWallpapers

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, count: library.wallpapers.count)
        } detail: {
            ContentArea(library: library, selection: selection ?? .allWallpapers)
                .id(selection)   // force clean recreation when sidebar switches
        }
        .sheet(isPresented: $library.showOnboarding) {
            OnboardingView(isPresented: $library.showOnboarding)
        }
        .sheet(item: $library.activeDraft) { draft in
            ImportSheet(
                draft: draft,
                onCancel: { library.cancelDraft() },
                onContinue: { metadata in
                    Task { await library.confirmImport(draft, metadata: metadata) }
                }
            )
        }
        .sheet(item: $library.renameTarget) { target in
            RenameSheet(
                target: target,
                onCancel: { library.renameTarget = nil },
                onConfirm: { newName in
                    let vm = target
                    library.renameTarget = nil
                    Task { await library.rename(vm, to: newName) }
                }
            )
        }
        .alert(
            "Remove \"\(library.removeTarget?.name ?? "")\"?",
            isPresented: Binding(
                get: { library.removeTarget != nil },
                set: { if !$0 { library.removeTarget = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let vm = library.removeTarget {
                    library.removeTarget = nil
                    Task { await library.remove(vm) }
                }
            }
            Button("Cancel", role: .cancel) { library.removeTarget = nil }
        } message: {
            Text("The wallpaper will be removed from System Settings and the transcoded files in ~/Library/Application Support/AerialWall/ will be deleted.")
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { library.importError != nil },
                set: { if !$0 { library.importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importError ?? "")
        }
    }
}

private struct ContentArea: View {
    @Bindable var library: WallpaperLibrary
    let selection: SidebarItem

    var body: some View {
        switch selection {
        case .allWallpapers, .recentlyAdded:
            LibraryView(library: library, filter: selection)
        case .logs:
            LogView()
        }
    }
}

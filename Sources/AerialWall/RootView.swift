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
        }
        .sheet(isPresented: $library.showOnboarding) {
            OnboardingView(isPresented: $library.showOnboarding)
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

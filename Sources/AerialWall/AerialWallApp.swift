import SwiftUI
import AerialWallKit

@main
struct AerialWallApp: App {
    @State private var library = WallpaperLibrary()

    var body: some Scene {
        WindowGroup("AerialWall") {
            RootView(library: library)
                .frame(minWidth: 760, minHeight: 520)
                .task { await library.load() }
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import…") {
                    Task { await library.openImportPanel() }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsScene()
        }
    }
}

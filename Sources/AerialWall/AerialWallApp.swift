import SwiftUI
import AppKit
import AerialWallKit

/// V39: SPM-launched executables default to a UIElement-style activation policy.
/// Without an explicit `.regular` policy + activate, sheet windows never become
/// key, so `TextField` inside a sheet drops clicks/keypresses (see B11).
final class AerialWallAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct AerialWallApp: App {
    @NSApplicationDelegateAdaptor(AerialWallAppDelegate.self) var appDelegate
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

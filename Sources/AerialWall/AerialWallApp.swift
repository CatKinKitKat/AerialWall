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
        refreshAppIcon()
        // Re-render when the user switches Light/Dark so the dock icon stays
        // in sync (V54).
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshAppIcon),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @MainActor @objc private func refreshAppIcon() {
        // In a proper .app bundle, CFBundleIconName + Assets.car drives the
        // dock icon and macOS handles light/dark/tinted automatically. Force-
        // setting applicationIconImage = NSImage(contentsOf: icns) would lock
        // it to the single-appearance .icns and break appearance switching.
        // Detect: if Info.plist has CFBundleIconName, we're in a bundle — skip.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil {
            return
        }
        // swift run / no .app bundle — fall back to the static .icns so at
        // least *something* shows up in the dock instead of the generic exec.
        if let url = Bundle.module.url(forResource: "AerialWall", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }
}

/// Toggle for the "Developer" menu — shows/hides the Logs sidebar section.
/// Kept in its own view so the @AppStorage binding is independent of the App
/// scope and the menu item gets the SwiftUI checkmark state automatically.
struct DeveloperModeToggle: View {
    @AppStorage("aerialwall.developerMode") private var developerMode = false
    var body: some View {
        Toggle("Show Logs in Sidebar", isOn: $developerMode)
    }
}

@main
struct AerialWallApp: App {
    @NSApplicationDelegateAdaptor(AerialWallAppDelegate.self) var appDelegate
    @State private var library = WallpaperLibrary()
    @State private var showAbout = false
    @State private var showHelp = false

    var body: some Scene {
        WindowGroup("AerialWall") {
            RootView(library: library)
                .frame(minWidth: 760, minHeight: 520)
                .task { await library.load() }
                .sheet(isPresented: $showAbout) { AboutView() }
                .sheet(isPresented: $showHelp) { HelpView() }
                .onReceive(NotificationCenter.default.publisher(
                    for: Notification.Name("AerialWall.showAbout"))) { _ in
                    showAbout = true
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: Notification.Name("AerialWall.showHelp"))) { _ in
                    showHelp = true
                }
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import…") {
                    Task { await library.openImportPanel() }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About AerialWall") {
                    NotificationCenter.default.post(
                        name: Notification.Name("AerialWall.showAbout"), object: nil)
                }
            }
            CommandGroup(replacing: .help) {
                Button("AerialWall Help") {
                    NotificationCenter.default.post(
                        name: Notification.Name("AerialWall.showHelp"), object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            CommandMenu("Developer") {
                DeveloperModeToggle()
            }
        }

        Settings {
            SettingsScene()
        }
    }
}

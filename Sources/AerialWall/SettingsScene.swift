import SwiftUI
import AerialWallKit

struct SettingsScene: View {
    @AppStorage("aerialwall.applyToAllDisplays") private var applyToAllDisplays = true
    @AppStorage("aerialwall.watcherAtLogin") private var watcherAtLogin = true
    @AppStorage("aerialwall.transcodeQuality") private var quality = "balanced"
    @AppStorage("aerialwall.targetResolution") private var resolution = "uhd"
    @AppStorage("aerialwall.keepOriginals") private var keepOriginals = false

    @State private var showUninstallConfirm = false
    @State private var uninstallPreserveBackup = true
    @State private var uninstallInFlight = false
    @State private var uninstallResult: String? = nil

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start watcher at login", isOn: $watcherAtLogin)
                Toggle("Apply wallpaper to all displays", isOn: $applyToAllDisplays)
            }
            Section("Import") {
                Picker("Video quality", selection: $quality) {
                    Text("Fast").tag("fast")
                    Text("Balanced").tag("balanced")
                    Text("Maximum").tag("maximum")
                }
                Picker("Target resolution", selection: $resolution) {
                    Text("4K (3840×2160)").tag("uhd")
                    Text("1080p (1920×1080)").tag("fhd")
                    Text("Match source").tag("source")
                }
                Toggle("Keep original files", isOn: $keepOriginals)
            }
            Section {
                Toggle("Preserve backups when uninstalling", isOn: $uninstallPreserveBackup)
                Button("Uninstall AerialWall…", role: .destructive) {
                    showUninstallConfirm = true
                }
                .disabled(uninstallInFlight)
                if let r = uninstallResult {
                    Text(r).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Removes all AerialWall entries from System Settings → Wallpaper and deletes the app's local storage. Apple's stock wallpapers are untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .confirmationDialog(
            "Uninstall AerialWall?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) { runUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(uninstallPreserveBackup
                ? "All injected wallpapers will be removed. The backups/ folder will be kept so you can restore manually."
                : "All injected wallpapers, the AerialWall storage folder, the launch agent, and the backups will be deleted.")
        }
    }

    private func runUninstall() {
        uninstallInFlight = true
        uninstallResult = nil
        Task {
            do {
                let report = try await UninstallEngine.uninstall(
                    mode: uninstallPreserveBackup ? .preservingBackup : .full
                )
                uninstallResult = "Removed \(report.assetsStripped) wallpaper(s), \(report.filesDeleted) file(s)."
            } catch {
                uninstallResult = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            uninstallInFlight = false
        }
    }
}

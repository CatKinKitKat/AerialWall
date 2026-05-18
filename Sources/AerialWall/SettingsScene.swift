import SwiftUI

struct SettingsScene: View {
    @AppStorage("aerialwall.applyToAllDisplays") private var applyToAllDisplays = true
    @AppStorage("aerialwall.watcherAtLogin") private var watcherAtLogin = true
    @AppStorage("aerialwall.transcodeQuality") private var quality = "balanced"
    @AppStorage("aerialwall.targetResolution") private var resolution = "uhd"
    @AppStorage("aerialwall.keepOriginals") private var keepOriginals = false

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
                Button("Remove All Injected Wallpapers…", role: .destructive) {}
                    .disabled(true)
                Button("Uninstall AerialWall…", role: .destructive) {}
                    .disabled(true)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Lands in T15 (uninstall flow).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 480)
    }
}

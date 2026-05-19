import SwiftUI
import AppKit

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                HelpCard(title: "Getting started", systemImage: "play.circle") {
                    step(1, "Click **Import…** in the toolbar (or press ⌘O) and choose a video file. You can also drag and drop a video into the library window.")
                    step(2, "Give it a name and an optional description in the import sheet, then click **Import**.")
                    step(3, "Wait for the transcode to finish — the progress bar shows how far along it is.")
                    step(4, "The new wallpaper appears in the library and in **System Settings → Wallpaper** under the AerialWall category.")
                }

                HelpCard(title: "Applying a wallpaper", systemImage: "rectangle.inset.filled.on.rectangle") {
                    bullet("**Double-click** a wallpaper card to apply it.")
                    bullet("Or right-click → **Apply as Wallpaper**.")
                    bullet("The status badge turns into a green checkmark when applied.")
                    bullet("Applies to all displays and Mission Control spaces uniformly.")
                }

                HelpCard(title: "Supported video formats", systemImage: "film") {
                    Text("**Direct import:**").font(.callout.weight(.semibold))
                    bullet(".mp4, .mov, .m4v — any codec AVFoundation reads (H.264, HEVC, ProRes…)")
                    Text("**Convert first:**").font(.callout.weight(.semibold)).padding(.top, 4)
                    bullet(".webm, .mkv, .avi — AVFoundation cannot read these containers on macOS 26. Use HandBrake to convert to .mp4.")
                }

                HelpCard(title: "Library views", systemImage: "square.grid.2x2") {
                    bullet("Toggle between **grid** and **list** view in the toolbar.")
                    bullet("Right-click any wallpaper for actions: Rename, Show in Finder, Copy UUID, Remove.")
                    bullet("**Remove** strips the wallpaper from the manifest and deletes its files. Apple's stock aerials are never touched.")
                }

                HelpCard(title: "Troubleshooting", systemImage: "wrench.and.screwdriver") {
                    issue(
                        "Wallpaper plays during lock but goes gray after unlock",
                        "Re-import the source. AerialWall encodes with HEVC temporal sub-layers required by macOS 26 — older imports made by buggy versions may need to be re-imported.")
                    issue(
                        "Import gets stuck",
                        "Check **Console.app** for the `com.aerialwall.kit` subsystem. WebM and MKV files fail at the reader step — convert to .mp4 first.")
                    issue(
                        "AerialWall category doesn't appear in System Settings",
                        "Open System Settings → Wallpaper at least once before launching AerialWall — macOS bootstraps `entries.json` lazily. Then quit and re-open AerialWall.")
                    issue(
                        "Other aerial categories disappeared from System Settings",
                        "A previous version left a dangling category reference. Open Settings → Danger Zone → Uninstall (preserving backups), then re-import.")
                }

                HelpCard(title: "Uninstalling", systemImage: "trash") {
                    Text("Open **Settings → Danger Zone → Uninstall AerialWall…**")
                    bullet("**Preserve backups**: keeps the `backups/` folder so you can hand-restore.")
                    bullet("**Full**: removes everything, including the LaunchAgent and backups.")
                    Text("Apple's stock wallpapers are never touched by uninstall.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                HelpCard(title: "Need more help?", systemImage: "questionmark.circle") {
                    linkRow("Open an issue on GitHub", url: "https://github.com/CatKinKitKat/AerialWall/issues")
                    linkRow("Read the SPEC.md (developer-facing)", url: "https://github.com/CatKinKitKat/AerialWall/blob/develop/SPEC.md")
                    linkRow("Read the RESEARCH.md (Tahoe internals)", url: "https://github.com/CatKinKitKat/AerialWall/blob/develop/RESEARCH.md")
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
        .frame(width: 560, height: 640)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Help").font(.largeTitle.weight(.semibold))
            Text("How to use AerialWall.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - row builders

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.callout.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(.tint)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .padding(.top, 8)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func issue(_ symptom: String, _ fix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(symptom).font(.callout.weight(.semibold))
            Text(fix).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func linkRow(_ title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HelpCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

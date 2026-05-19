import SwiftUI
import AppKit
import AerialWallKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev (swift run)"
    }
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                aboutSection
                supportSection
                creditsSection
            }
            .padding(24)
            .frame(maxWidth: 540)
        }
        .frame(width: 480, height: 600)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - sections

    private var header: some View {
        VStack(spacing: 8) {
            if let icon = appIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .accessibilityLabel("AerialWall icon")
            }
            Text("AerialWall").font(.largeTitle.weight(.semibold))
            Text("Native Video Wallpapers for macOS Tahoe")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Version \(appVersion) (\(appBuild))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var aboutSection: some View {
        AboutCard(title: "About") {
            Text("AerialWall transcodes your videos to the HEVC format required by macOS 26's `WallpaperAerialsExtension` and injects them into the wallpaper manifest. No overlays, no fake windows, no background helper — your wallpaper plays through the same renderer Apple uses.")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            link("GitHub", url: "https://github.com/CatKinKitKat/AerialWall", system: "chevron.left.forwardslash.chevron.right")
            link("Report a bug", url: "https://github.com/CatKinKitKat/AerialWall/issues/new?template=bug_report.yml", system: "ant")
            link("Request a feature", url: "https://github.com/CatKinKitKat/AerialWall/issues/new?template=feature_request.yml", system: "lightbulb")
        }
    }

    private var supportSection: some View {
        AboutCard(title: "Support development") {
            Text("AerialWall is free and open-source under AGPL-3.0. If it saves you time, a small tip keeps the lights on.")
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    open("https://ko-fi.com/catkinkitkat")
                } label: {
                    Label("Ko-fi", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.867, blue: 0.0))   // #FFDD00
                .foregroundStyle(.black)

                Button {
                    open("https://www.buymeacoffee.com/catkinkitkat")
                } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.heat.waves.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.867, blue: 0.0))
                .foregroundStyle(.black)
            }
        }
    }

    private var creditsSection: some View {
        AboutCard(title: "Created by") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gonçalo Candeias Amaro").font(.body.weight(.medium))
                Text("@CatKinKitKat").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Built with SwiftUI, AVFoundation, and VideoToolbox. Icon designed in Icon Composer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - helpers

    private func link(_ title: String, url: String, system: String) -> some View {
        Button {
            open(url)
        } label: {
            HStack {
                Label(title, systemImage: system)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func appIcon() -> NSImage? {
        // In a proper bundle, NSApp.applicationIconImage is the appearance-aware version
        if let img = NSApp.applicationIconImage { return img }
        if let url = Bundle.module.url(forResource: "AerialWall", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

private struct AboutCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

import SwiftUI
import AppKit
import AerialWallKit

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var entriesPresent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before you start")
                .font(.title2).bold()

            // V35: no helper-install step on Tahoe.
            OnboardingStep(
                number: 1,
                title: "Download an Apple wallpaper video",
                detail: "Open System Settings → Wallpaper and download any Apple aerial video.",
                isDone: entriesPresent,
                action: openWallpaperSettings,
                actionLabel: "Open Wallpaper Settings"
            )

            OnboardingStep(
                number: 2,
                title: "Set that Apple video as your wallpaper",
                detail: "Once selected, AerialWall can append new entries to the wallpaper system.",
                isDone: false
            )

            Spacer()

            HStack {
                Spacer()
                Button("Continue") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .onAppear {
            entriesPresent = FileManager.default.fileExists(atPath: Constants.entriesJSONPath.path)
        }
    }

    private func openWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct OnboardingStep: View {
    let number: Int
    let title: String
    let detail: String
    let isDone: Bool
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 24, height: 24)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                if let action, let actionLabel {
                    Button(actionLabel, action: action)
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
            }
            Spacer()
        }
    }
}

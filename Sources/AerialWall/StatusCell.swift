import SwiftUI

struct StatusCell: View {
    @Bindable var wallpaper: WallpaperViewModel

    var body: some View {
        if let progress = wallpaper.encodingProgress {
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 80)
                    .controlSize(.small)
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let err = wallpaper.errorMessage {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(err)
        } else if wallpaper.isApplied {
            Label("Applied", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if wallpaper.isInjected {
            Text("● Ready").foregroundStyle(.secondary)
        } else {
            Text("Pending").foregroundStyle(.secondary)
        }
    }
}

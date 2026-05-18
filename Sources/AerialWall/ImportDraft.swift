import Foundation
import AerialWallKit

/// Immutable starting point for the import modal. Created by
/// `WallpaperLibrary.prepareDraft(source:)` after a cheap thumbnail + duration
/// probe; the actual heavy transcode doesn't run until the user clicks
/// "Continue" in the sheet.
struct ImportDraft: Identifiable {
    let id = UUID()
    let source: URL
    let previewThumbnailPath: URL    // /tmp/<uuid>.png — discarded on cancel
    let durationSeconds: Double
    let sourceResolution: String
    let suggestedName: String

    var durationString: String {
        let total = Int(durationSeconds)
        guard total > 0 else { return "—" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Caller-supplied metadata for the full import pipeline. Category fields
/// are no longer user-selectable — every AerialWall import goes under the
/// hardcoded `Constants.AerialWallCategory` (V27, V28).
struct ImportMetadata: Sendable {
    let name: String
    let description: String
}

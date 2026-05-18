import Foundation

public enum InjectionError: Error, Equatable {
    case assetInvalid(reason: String)
    case schemaIncompatible(observed: Int, expected: Int)
}

public extension Asset {
    /// V7 + V13: all required fields populated, ID is a valid uppercase UUID.
    func validate() throws {
        if id.isEmpty || UUID(uuidString: id) == nil {
            throw InjectionError.assetInvalid(reason: "id is not a valid UUID: \(id)")
        }
        if id != id.uppercased() {
            throw InjectionError.assetInvalid(reason: "id must be uppercase: \(id)")
        }
        if accessibilityLabel.isEmpty {
            throw InjectionError.assetInvalid(reason: "accessibilityLabel empty")
        }
        if localizedNameKey.isEmpty {
            throw InjectionError.assetInvalid(reason: "localizedNameKey empty")
        }
        if shotID.isEmpty {
            throw InjectionError.assetInvalid(reason: "shotID empty")
        }
        if previewImage.isEmpty {
            throw InjectionError.assetInvalid(reason: "previewImage empty")
        }
        if urlSDR4K240.isEmpty {
            throw InjectionError.assetInvalid(reason: "url-4K-SDR-240FPS empty")
        }
        if categories.isEmpty {
            throw InjectionError.assetInvalid(reason: "categories empty")
        }
        if subcategories.isEmpty {
            throw InjectionError.assetInvalid(reason: "subcategories empty")
        }
    }
}

/// Append / remove / probe AerialWall assets within Apple's `entries.json`.
///
/// Scope (T4):
/// - validate asset (V7, V13)
/// - schema-gate the target file (V21)
/// - load → mutate → atomic write (V14)
/// - replace-by-id on duplicate (no duplicates ever appear)
///
/// Out of scope here: category upserts (T4 reuses existing categories),
/// agent restart (T8), post-restart presence verification (T8 wires it),
/// backups (T11).
public enum InjectionEngine {

    /// Wraps codec-level schema errors into `InjectionError` so callers see one type.
    private static func gateSchema(at url: URL) throws {
        do {
            try EntriesJSONCodec.assertSchemaCompatible(at: url)
        } catch EntriesJSONError.unsupportedVersion(let observed, let expected) {
            throw InjectionError.schemaIncompatible(observed: observed, expected: expected)
        }
    }

    /// Insert `asset`, or replace the existing entry with the same id.
    @discardableResult
    public static func inject(
        _ asset: Asset,
        into entriesURL: URL = Constants.entriesJSONPath
    ) throws -> EntriesManifest {
        try asset.validate()
        try gateSchema(at: entriesURL)

        var manifest = try EntriesJSONCodec.load(from: entriesURL)
        if let existing = manifest.assets.firstIndex(where: { $0.id == asset.id }) {
            manifest.assets[existing] = asset
        } else {
            manifest.assets.append(asset)
        }
        try EntriesJSONCodec.writeAtomically(manifest, to: entriesURL)
        return manifest
    }

    /// Remove the asset with `id`. No-op if absent.
    @discardableResult
    public static func remove(
        id: String,
        from entriesURL: URL = Constants.entriesJSONPath
    ) throws -> EntriesManifest {
        try gateSchema(at: entriesURL)
        var manifest = try EntriesJSONCodec.load(from: entriesURL)
        manifest.assets.removeAll { $0.id == id }
        try EntriesJSONCodec.writeAtomically(manifest, to: entriesURL)
        return manifest
    }

    /// V20: cheap presence check used by PersistenceWatcher to detect drift.
    public static func isPresent(
        id: String,
        in entriesURL: URL = Constants.entriesJSONPath
    ) throws -> Bool {
        let manifest = try EntriesJSONCodec.load(from: entriesURL)
        return manifest.assets.contains { $0.id == id }
    }

    public static func count(in entriesURL: URL = Constants.entriesJSONPath) throws -> Int {
        let manifest = try EntriesJSONCodec.load(from: entriesURL)
        return manifest.assets.count
    }

    /// V20: identifies which `expectedIDs` are missing from `entriesURL`. Empty
    /// result ⇒ no drift detected.
    public static func missingIDs(
        from entriesURL: URL = Constants.entriesJSONPath,
        expected expectedIDs: [String]
    ) throws -> [String] {
        let manifest = try EntriesJSONCodec.load(from: entriesURL)
        let present = Set(manifest.assets.map { $0.id })
        return expectedIDs.filter { !present.contains($0) }
    }
}

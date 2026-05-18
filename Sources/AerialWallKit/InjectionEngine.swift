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
    /// If `upsertCategory` is provided: append it when absent, OR refresh
    /// `representativeAssetID` + `previewImage` on the existing category
    /// (V43 — rep MUST always point to a live asset, otherwise
    /// WallpaperAerialsExtension drops every aerial category from the UI).
    @discardableResult
    public static func inject(
        _ asset: Asset,
        into entriesURL: URL = Constants.entriesJSONPath,
        upsertCategory: Category? = nil
    ) throws -> EntriesManifest {
        try asset.validate()
        try gateSchema(at: entriesURL)

        var manifest = try EntriesJSONCodec.load(from: entriesURL)

        if let cat = upsertCategory {
            if let i = manifest.categories.firstIndex(where: { $0.id == cat.id }) {
                manifest.categories[i].representativeAssetID = cat.representativeAssetID
                manifest.categories[i].previewImage = cat.previewImage
                for newSub in cat.subcategories {
                    if let sj = manifest.categories[i].subcategories.firstIndex(where: { $0.id == newSub.id }) {
                        manifest.categories[i].subcategories[sj].representativeAssetID = newSub.representativeAssetID
                        manifest.categories[i].subcategories[sj].previewImage = newSub.previewImage
                    }
                }
            } else {
                manifest.categories.append(cat)
            }
        }

        if let existing = manifest.assets.firstIndex(where: { $0.id == asset.id }) {
            manifest.assets[existing] = asset
        } else {
            manifest.assets.append(asset)
        }
        try EntriesJSONCodec.writeAtomically(manifest, to: entriesURL)
        return manifest
    }

    /// Build the canonical "AerialWall" category record we append to entries.json.
    /// `representativeAssetID` is referenced for the category preview thumbnail
    /// in System Settings — pass the UUID of the first asset you're injecting.
    public static func makeAerialWallCategory(
        representativeAssetID: String,
        previewImageURL: String
    ) -> Category {
        Category(
            id: Constants.AerialWallCategory.categoryID,
            localizedNameKey: Constants.AerialWallCategory.displayName,
            localizedDescriptionKey: Constants.AerialWallCategory.descriptionText,
            preferredOrder: -1,
            previewImage: previewImageURL,
            representativeAssetID: representativeAssetID,
            subcategories: [
                Subcategory(
                    id: Constants.AerialWallCategory.subcategoryID,
                    localizedNameKey: Constants.AerialWallCategory.subcategoryDisplayName,
                    localizedDescriptionKey: Constants.AerialWallCategory.descriptionText,
                    preferredOrder: -1,
                    previewImage: previewImageURL,
                    representativeAssetID: representativeAssetID
                )
            ]
        )
    }

    /// Remove the asset with `id`. No-op if absent.
    /// `maintaining` lists custom category UUIDs whose integrity we own
    /// (V28: never touch stock Apple categories). For each: if the removed
    /// asset was the category's rep, reassign rep to another remaining asset;
    /// if no assets remain in the category, drop the category entirely.
    @discardableResult
    public static func remove(
        id: String,
        from entriesURL: URL = Constants.entriesJSONPath,
        maintaining customCategoryIDs: Set<String> = [Constants.AerialWallCategory.categoryID]
    ) throws -> EntriesManifest {
        try gateSchema(at: entriesURL)
        var manifest = try EntriesJSONCodec.load(from: entriesURL)
        manifest.assets.removeAll { $0.id == id }

        var keptCategories: [Category] = []
        for var cat in manifest.categories {
            guard customCategoryIDs.contains(cat.id) else {
                keptCategories.append(cat)
                continue
            }
            let remaining = manifest.assets.filter { $0.categories.contains(cat.id) }
            guard !remaining.isEmpty else { continue }    // drop empty custom category

            if cat.representativeAssetID == id, let pick = remaining.first {
                cat.representativeAssetID = pick.id
                cat.previewImage = pick.previewImage
            }
            var keptSubs: [Subcategory] = []
            for var sub in cat.subcategories {
                let subRemaining = remaining.filter { $0.subcategories.contains(sub.id) }
                guard !subRemaining.isEmpty else { continue }
                if sub.representativeAssetID == id, let pick = subRemaining.first {
                    sub.representativeAssetID = pick.id
                    sub.previewImage = pick.previewImage
                }
                keptSubs.append(sub)
            }
            cat.subcategories = keptSubs
            keptCategories.append(cat)
        }
        manifest.categories = keptCategories

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

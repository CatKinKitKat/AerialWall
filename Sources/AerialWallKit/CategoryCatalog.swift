import Foundation

/// One picker option in the import modal's category dropdown.
public struct CategoryOption: Identifiable, Equatable, Hashable, Sendable {
    public let id: String              // subcategory UUID
    public let parentID: String        // parent category UUID
    public let displayName: String     // user-visible, e.g. "Tahoe"
    public let parentDisplayName: String  // e.g. "Landscapes"

    public init(id: String, parentID: String, displayName: String, parentDisplayName: String) {
        self.id = id
        self.parentID = parentID
        self.displayName = displayName
        self.parentDisplayName = parentDisplayName
    }
}

public enum CategoryCatalog {

    /// Strip Apple's localization-key prefix so we get a readable label
    /// without round-tripping through `TVIdleScreenStrings.bundle` (V8: ⊥ modify it).
    static func displayName(from localizedNameKey: String) -> String {
        var s = localizedNameKey
        for prefix in ["AerialSubcategory", "AerialCategory"] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        // Insert spaces before capitals in CamelCase tail (e.g. "EarthFromAbove" → "Earth From Above").
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, ch.isUppercase, let prev = out.last, prev.isLowercase {
                out.append(" ")
            }
            out.append(ch)
        }
        return out.isEmpty ? localizedNameKey : out
    }

    /// Enumerate every (category, subcategory) pair in `entries.json` as a flat
    /// pickable list. Falls back to a single hardcoded option (Landscapes → Tahoe)
    /// if the file is absent — onboarding will tell the user to download a stock
    /// asset first (V20-equivalent).
    public static func availableOptions(
        at url: URL = Constants.entriesJSONPath
    ) -> [CategoryOption] {
        guard let manifest = try? EntriesJSONCodec.load(from: url) else {
            return [CategoryOption(
                id: Constants.StockCategory.tahoeSubcategory,
                parentID: Constants.StockCategory.landscapes,
                displayName: "Tahoe",
                parentDisplayName: "Landscapes"
            )]
        }
        var opts: [CategoryOption] = []
        for cat in manifest.categories {
            let parentName = displayName(from: cat.localizedNameKey)
            for sub in cat.subcategories {
                opts.append(CategoryOption(
                    id: sub.id, parentID: cat.id,
                    displayName: displayName(from: sub.localizedNameKey),
                    parentDisplayName: parentName
                ))
            }
        }
        return opts
    }

    public static func defaultOption(in options: [CategoryOption]) -> CategoryOption? {
        options.first { $0.id == Constants.StockCategory.tahoeSubcategory }
        ?? options.first
    }
}

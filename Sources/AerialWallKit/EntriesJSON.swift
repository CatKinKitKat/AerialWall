import Foundation

public enum EntriesJSONError: Error, Equatable {
    case fileMissing(URL)
    case invalidSchema(String)
    case unsupportedVersion(observed: Int, expected: Int)
}

/// Top-level shape of `~/Library/.../com.apple.wallpaper/aerials/manifest/entries.json`.
public struct EntriesManifest: Codable, Equatable {
    public var version: Int
    public var initialAssetCount: Int
    public var localizationVersion: String
    public var assets: [Asset]
    public var categories: [Category]

    public init(version: Int, initialAssetCount: Int, localizationVersion: String,
                assets: [Asset], categories: [Category]) {
        self.version = version
        self.initialAssetCount = initialAssetCount
        self.localizationVersion = localizationVersion
        self.assets = assets
        self.categories = categories
    }
}

/// One wallpaper video — what AerialWall appends to `assets`.
///
/// All 12 fields here are required for every stock Apple entry (verified 156/156).
/// Optional `group` is present in 44/156 stock entries.
public struct Asset: Codable, Equatable {
    public var id: String
    public var accessibilityLabel: String
    public var categories: [String]
    public var subcategories: [String]
    public var includeInShuffle: Bool
    public var localizedNameKey: String
    public var pointsOfInterest: [String: AnyJSON]
    public var preferredOrder: Int
    public var previewImage: String
    public var shotID: String
    public var showInTopLevel: Bool
    public var urlSDR4K240: String
    public var group: String?

    private enum CodingKeys: String, CodingKey {
        case id, accessibilityLabel, categories, subcategories, includeInShuffle
        case localizedNameKey, pointsOfInterest, preferredOrder, previewImage
        case shotID, showInTopLevel, group
        case urlSDR4K240 = "url-4K-SDR-240FPS"
    }

    public init(id: String, accessibilityLabel: String,
                categories: [String], subcategories: [String],
                includeInShuffle: Bool, localizedNameKey: String,
                pointsOfInterest: [String: AnyJSON] = [:],
                preferredOrder: Int, previewImage: String,
                shotID: String, showInTopLevel: Bool,
                urlSDR4K240: String, group: String? = nil) {
        self.id = id
        self.accessibilityLabel = accessibilityLabel
        self.categories = categories
        self.subcategories = subcategories
        self.includeInShuffle = includeInShuffle
        self.localizedNameKey = localizedNameKey
        self.pointsOfInterest = pointsOfInterest
        self.preferredOrder = preferredOrder
        self.previewImage = previewImage
        self.shotID = shotID
        self.showInTopLevel = showInTopLevel
        self.urlSDR4K240 = urlSDR4K240
        self.group = group
    }
}

public struct Category: Codable, Equatable {
    public var id: String
    public var localizedNameKey: String
    public var localizedDescriptionKey: String
    public var preferredOrder: Int
    public var previewImage: String
    public var representativeAssetID: String
    public var subcategories: [Subcategory]
}

public struct Subcategory: Codable, Equatable {
    public var id: String
    public var localizedNameKey: String
    public var localizedDescriptionKey: String
    public var preferredOrder: Int
    public var previewImage: String
    public var representativeAssetID: String
}

/// Passthrough for unknown JSON shapes (e.g. `pointsOfInterest` values whose type
/// we haven't pinned down — Apple stock entries always carry `{}` but the field is
/// modelled generically to survive future population).
public enum AnyJSON: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
        if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "AnyJSON: unknown shape")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

public enum EntriesJSONCodec {

    /// V15: sorted keys (matches Apple's alphabetical top-level ordering)
    /// + pretty-printed 2-space indent (matches Apple's formatting).
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    public static let decoder = JSONDecoder()

    public static func load(from url: URL) throws -> EntriesManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EntriesJSONError.fileMissing(url)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(EntriesManifest.self, from: data)
    }

    /// V14: atomic write — `Data.write(options: .atomic)` writes to a sibling
    /// temp file and `rename(2)`s into place. Partial writes never visible.
    public static func writeAtomically(_ manifest: EntriesManifest, to url: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    /// V21 schema gate. Probes `version` + `localizationVersion` without
    /// fully decoding — cheaper, and survives unknown asset/category fields
    /// that might appear in a future schema we haven't modelled yet.
    public static func probeSchemaVersion(at url: URL) throws -> (version: Int, localizationVersion: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EntriesJSONError.fileMissing(url)
        }
        let data = try Data(contentsOf: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = obj["version"] as? Int,
              let locVersion = obj["localizationVersion"] as? String
        else {
            throw EntriesJSONError.invalidSchema("missing version or localizationVersion key")
        }
        return (version, locVersion)
    }

    /// V21: probe + compare against pinned expectations. Throws on mismatch
    /// so callers (InjectionEngine) can refuse to inject against an unknown schema.
    public static func assertSchemaCompatible(at url: URL) throws {
        let (version, _) = try probeSchemaVersion(at: url)
        guard version == Constants.expectedEntriesSchemaVersion else {
            throw EntriesJSONError.unsupportedVersion(
                observed: version,
                expected: Constants.expectedEntriesSchemaVersion
            )
        }
    }
}

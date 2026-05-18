import Foundation

public struct AerialWallEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { uuid }
    public var uuid: String
    public var name: String
    public var originalFilename: String
    public var importedAt: Date
    public var durationSeconds: Double
    public var resolution: String
    public var videoPath: String
    public var thumbPath: String
    public var isInjected: Bool

    public init(uuid: String, name: String, originalFilename: String,
                importedAt: Date, durationSeconds: Double, resolution: String,
                videoPath: String, thumbPath: String, isInjected: Bool = false) {
        self.uuid = uuid
        self.name = name
        self.originalFilename = originalFilename
        self.importedAt = importedAt
        self.durationSeconds = durationSeconds
        self.resolution = resolution
        self.videoPath = videoPath
        self.thumbPath = thumbPath
        self.isInjected = isInjected
    }
}

public struct AerialWallManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var entriesSchemaSeen: Int
    public var wallpapers: [AerialWallEntry]

    public init(schemaVersion: Int = 1,
                entriesSchemaSeen: Int = Constants.expectedEntriesSchemaVersion,
                wallpapers: [AerialWallEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entriesSchemaSeen = entriesSchemaSeen
        self.wallpapers = wallpapers
    }
}

public enum AerialWallManifestError: Error, Equatable {
    case decodeFailed(String)
}

public enum AerialWallManifestStore {

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Load from disk. Missing file ⇒ fresh empty manifest (first-run case).
    public static func load(from url: URL = Constants.aerialWallManifestPath) throws -> AerialWallManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AerialWallManifest()
        }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(AerialWallManifest.self, from: data)
        } catch {
            throw AerialWallManifestError.decodeFailed("\(error)")
        }
    }

    public static func save(_ manifest: AerialWallManifest,
                            to url: URL = Constants.aerialWallManifestPath) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    /// V19: entries whose `videoPath` or `thumbPath` is missing on disk.
    /// UI surfaces these for user-confirmed cleanup; never auto-removed.
    public static func danglingEntries(in manifest: AerialWallManifest) -> [AerialWallEntry] {
        let fm = FileManager.default
        return manifest.wallpapers.filter {
            !fm.fileExists(atPath: $0.videoPath) || !fm.fileExists(atPath: $0.thumbPath)
        }
    }

    /// Convenience mutator: add or replace an entry by uuid, then save.
    public static func upsert(_ entry: AerialWallEntry,
                              at url: URL = Constants.aerialWallManifestPath) throws {
        var m = try load(from: url)
        if let i = m.wallpapers.firstIndex(where: { $0.uuid == entry.uuid }) {
            m.wallpapers[i] = entry
        } else {
            m.wallpapers.append(entry)
        }
        try save(m, to: url)
    }

    public static func remove(uuid: String,
                              at url: URL = Constants.aerialWallManifestPath) throws {
        var m = try load(from: url)
        m.wallpapers.removeAll { $0.uuid == uuid }
        try save(m, to: url)
    }
}

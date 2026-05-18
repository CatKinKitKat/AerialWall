import Testing
import Foundation
@testable import AerialWallKit

@Suite("EntriesJSON codec — V14 atomic write, V15 key ordering, V21 schema gate")
struct EntriesJSONTests {

    static let fixture = """
    {
      "assets" : [
        {
          "accessibilityLabel" : "Tahoe Day",
          "categories" : [
            "A33A55D9-EDEA-4596-A850-6C10B54FBBB5"
          ],
          "id" : "4C108785-A7BA-422E-9C79-B0129F1D5550",
          "includeInShuffle" : true,
          "localizedNameKey" : "TA_L_002_NAME",
          "pointsOfInterest" : {},
          "preferredOrder" : 1,
          "previewImage" : "https://example.com/thumb.png",
          "shotID" : "TA_L_002",
          "showInTopLevel" : true,
          "subcategories" : [
            "0DC99DD8-3386-4D1E-8878-C43E97EB710A"
          ],
          "url-4K-SDR-240FPS" : "https://example.com/video.mov"
        },
        {
          "accessibilityLabel" : "Sequoia Day",
          "categories" : ["A33A55D9-EDEA-4596-A850-6C10B54FBBB5"],
          "group" : "SequoiaPair",
          "id" : "F88CDF4A-9681-4D1F-88FE-34F1A3C6A62B",
          "includeInShuffle" : true,
          "localizedNameKey" : "SEQ_L_001_NAME",
          "pointsOfInterest" : {},
          "preferredOrder" : 2,
          "previewImage" : "https://example.com/seq.png",
          "shotID" : "SEQ_L_001",
          "showInTopLevel" : true,
          "subcategories" : ["78D1B993-DA5B-4CA6-90F0-865DA7F9091D"],
          "url-4K-SDR-240FPS" : "https://example.com/seq.mov"
        }
      ],
      "categories" : [
        {
          "id" : "A33A55D9-EDEA-4596-A850-6C10B54FBBB5",
          "localizedDescriptionKey" : "AerialCategoryLandscapesDescription",
          "localizedNameKey" : "AerialCategoryLandscapes",
          "preferredOrder" : 0,
          "previewImage" : "https://example.com/landscapes.jpg",
          "representativeAssetID" : "4C108785-A7BA-422E-9C79-B0129F1D5550",
          "subcategories" : [
            {
              "id" : "0DC99DD8-3386-4D1E-8878-C43E97EB710A",
              "localizedDescriptionKey" : "AerialSubcategoryDescriptionTahoe",
              "localizedNameKey" : "AerialSubcategoryTahoe",
              "preferredOrder" : -1,
              "previewImage" : "https://example.com/tahoe.png",
              "representativeAssetID" : "4C108785-A7BA-422E-9C79-B0129F1D5550"
            }
          ]
        }
      ],
      "initialAssetCount" : 4,
      "localizationVersion" : "22L-1",
      "version" : 1
    }
    """

    private func decode(_ s: String) throws -> EntriesManifest {
        try EntriesJSONCodec.decoder.decode(EntriesManifest.self, from: Data(s.utf8))
    }

    @Test func fixtureDecodesAllFields() throws {
        let m = try decode(Self.fixture)
        #expect(m.version == 1)
        #expect(m.initialAssetCount == 4)
        #expect(m.localizationVersion == "22L-1")
        #expect(m.assets.count == 2)
        #expect(m.categories.count == 1)

        let a = m.assets[0]
        #expect(a.id == "4C108785-A7BA-422E-9C79-B0129F1D5550")
        #expect(a.accessibilityLabel == "Tahoe Day")
        #expect(a.localizedNameKey == "TA_L_002_NAME")
        #expect(a.shotID == "TA_L_002")
        #expect(a.preferredOrder == 1)
        #expect(a.includeInShuffle == true)
        #expect(a.showInTopLevel == true)
        #expect(a.categories == ["A33A55D9-EDEA-4596-A850-6C10B54FBBB5"])
        #expect(a.subcategories == ["0DC99DD8-3386-4D1E-8878-C43E97EB710A"])
        #expect(a.urlSDR4K240 == "https://example.com/video.mov")
        #expect(a.previewImage == "https://example.com/thumb.png")
        #expect(a.pointsOfInterest.isEmpty)
        #expect(a.group == nil)

        #expect(m.assets[1].group == "SequoiaPair")
    }

    @Test func roundTripPreservesData() throws {
        let m = try decode(Self.fixture)
        let encoded = try EntriesJSONCodec.encoder.encode(m)
        let redecoded = try EntriesJSONCodec.decoder.decode(EntriesManifest.self, from: encoded)
        #expect(redecoded == m)
    }

    /// V15: encoded top-level keys are alphabetical (matches Apple's serialization).
    @Test func encoderSortsTopLevelKeys() throws {
        let m = try decode(Self.fixture)
        let encoded = try EntriesJSONCodec.encoder.encode(m)
        let s = String(data: encoded, encoding: .utf8)!
        // Find first occurrence of each top-level key in encoded string.
        let keys = ["assets", "categories", "initialAssetCount", "localizationVersion", "version"]
        let positions = keys.compactMap { s.range(of: "\"\($0)\"")?.lowerBound }
        #expect(positions.count == keys.count)
        #expect(positions == positions.sorted())
    }

    /// V14: writeAtomically produces a valid file that re-decodes to the original.
    @Test func atomicWriteRoundTrip() throws {
        let m = try decode(Self.fixture)
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try EntriesJSONCodec.writeAtomically(m, to: tmp)
        #expect(FileManager.default.fileExists(atPath: tmp.path))
        let loaded = try EntriesJSONCodec.load(from: tmp)
        #expect(loaded == m)
    }

    /// V14: atomic write overwriting an existing file leaves no partial state.
    /// (We can't easily simulate a crash mid-write, but we can verify replacement
    /// preserves a valid file on disk.)
    @Test func atomicWriteOverwritesCleanly() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        var m = try decode(Self.fixture)
        try EntriesJSONCodec.writeAtomically(m, to: tmp)

        m.assets[0].accessibilityLabel = "Modified"
        try EntriesJSONCodec.writeAtomically(m, to: tmp)

        let loaded = try EntriesJSONCodec.load(from: tmp)
        #expect(loaded.assets[0].accessibilityLabel == "Modified")
    }

    /// V21: probeSchemaVersion returns observed values without full decode.
    @Test func schemaProbeReadsVersionAndLocalization() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-probe-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(Self.fixture.utf8).write(to: tmp)

        let result = try EntriesJSONCodec.probeSchemaVersion(at: tmp)
        #expect(result.version == 1)
        #expect(result.localizationVersion == "22L-1")
    }

    /// V21: assertSchemaCompatible passes on v1, throws on mismatch.
    @Test func schemaAssertRejectsUnknownVersion() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-badver-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bad = Self.fixture.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        try Data(bad.utf8).write(to: tmp)

        #expect(throws: EntriesJSONError.self) {
            try EntriesJSONCodec.assertSchemaCompatible(at: tmp)
        }
    }

    @Test func schemaProbeMissingFileThrows() {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "definitely-not-here-\(UUID().uuidString).json")
        #expect(throws: EntriesJSONError.self) {
            try EntriesJSONCodec.probeSchemaVersion(at: nowhere)
        }
    }

    /// Hardest test: round-trip the real Apple entries.json on disk. Skipped if
    /// not present (CI / fresh install). Locally this validates we cope with
    /// all 156 stock entries — every required field, the optional `group`, the
    /// full categories tree, and idempotent re-encoding.
    @Test func realAppleEntriesJsonRoundTrips() throws {
        let path = Constants.entriesJSONPath
        guard FileManager.default.fileExists(atPath: path.path) else {
            return  // skip — file not present
        }
        let loaded = try EntriesJSONCodec.load(from: path)
        #expect(loaded.version == 1)
        #expect(loaded.assets.count >= 100)  // 156 on Tahoe stock
        #expect(loaded.categories.count >= 1)
        #expect(loaded.assets.allSatisfy { UUID(uuidString: $0.id) != nil })
        #expect(loaded.assets.allSatisfy { $0.id == $0.id.uppercased() })

        // Round-trip: encode → decode → equal struct.
        let encoded = try EntriesJSONCodec.encoder.encode(loaded)
        let redecoded = try EntriesJSONCodec.decoder.decode(EntriesManifest.self, from: encoded)
        #expect(redecoded == loaded)
    }
}

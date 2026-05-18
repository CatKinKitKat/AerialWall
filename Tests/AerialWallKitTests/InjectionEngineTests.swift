import Testing
import Foundation
@testable import AerialWallKit

@Suite("InjectionEngine — V7, V13 validation, V14 atomic mutate, V20 drift, V21 schema gate")
struct InjectionEngineTests {

    private func makeFixture() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-inject-\(UUID().uuidString).json")
        try Data(EntriesJSONTests.fixture.utf8).write(to: tmp)
        return tmp
    }

    private func validAsset(id: String = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") -> Asset {
        Asset(
            id: id,
            accessibilityLabel: "AerialWall Test",
            categories: [Constants.StockCategory.landscapes],
            subcategories: [Constants.StockCategory.tahoeSubcategory],
            includeInShuffle: false,
            localizedNameKey: "AerialWall Test",
            preferredOrder: -100,
            previewImage: "file:///tmp/preview.png",
            shotID: "AERIALWALL_TEST",
            showInTopLevel: true,
            urlSDR4K240: "file:///tmp/test.mov"
        )
    }

    @Test func injectAppendsNewAsset() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try InjectionEngine.count(in: url)
        let asset = validAsset()
        let manifest = try InjectionEngine.inject(asset, into: url)

        #expect(manifest.assets.count == before + 1)
        #expect(try InjectionEngine.isPresent(id: asset.id, in: url))
    }

    /// Idempotent: re-injecting same id replaces, never duplicates.
    @Test func injectReplacesByID() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        var a = validAsset()
        try InjectionEngine.inject(a, into: url)
        let countAfterFirst = try InjectionEngine.count(in: url)

        a.accessibilityLabel = "Renamed"
        let manifest = try InjectionEngine.inject(a, into: url)

        #expect(manifest.assets.count == countAfterFirst)
        let injected = manifest.assets.first { $0.id == a.id }
        #expect(injected?.accessibilityLabel == "Renamed")
    }

    /// V7: lowercase UUIDs rejected.
    @Test func rejectsLowercaseUUID() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = validAsset(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(throws: InjectionError.self) {
            try InjectionEngine.inject(a, into: url)
        }
    }

    /// V7: malformed UUIDs rejected.
    @Test func rejectsInvalidUUID() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = validAsset(id: "NOT-A-UUID")
        #expect(throws: InjectionError.self) {
            try InjectionEngine.inject(a, into: url)
        }
    }

    /// V13: each required field is verified non-empty.
    @Test func rejectsMissingRequiredFields() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        var a = validAsset(); a.accessibilityLabel = ""
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }

        a = validAsset(); a.localizedNameKey = ""
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }

        a = validAsset(); a.shotID = ""
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }

        a = validAsset(); a.previewImage = ""
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }

        a = validAsset(); a.urlSDR4K240 = ""
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }

        a = validAsset(); a.categories = []
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }

        a = validAsset(); a.subcategories = []
        #expect(throws: InjectionError.self) { try InjectionEngine.inject(a, into: url) }
    }

    @Test func removeDropsAsset() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = validAsset()
        try InjectionEngine.inject(a, into: url)
        #expect(try InjectionEngine.isPresent(id: a.id, in: url))
        try InjectionEngine.remove(id: a.id, from: url)
        #expect(try !InjectionEngine.isPresent(id: a.id, in: url))
    }

    @Test func removeOfAbsentIDIsNoOp() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try InjectionEngine.count(in: url)
        try InjectionEngine.remove(id: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF", from: url)
        let after = try InjectionEngine.count(in: url)
        #expect(before == after)
    }

    /// V21: schema gate rejects unknown versions.
    @Test func schemaGateRejectsBadVersion() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aerialwall-badver-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let bad = EntriesJSONTests.fixture
            .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        try Data(bad.utf8).write(to: url)

        #expect(throws: InjectionError.self) {
            try InjectionEngine.inject(validAsset(), into: url)
        }
    }

    /// V20: missingIDs returns the gap between expected and present.
    @Test func missingIDsReportsDrift() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = validAsset(id: "11111111-2222-3333-4444-555555555555")
        let b = validAsset(id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        try InjectionEngine.inject(a, into: url)
        try InjectionEngine.inject(b, into: url)
        try InjectionEngine.remove(id: a.id, from: url)  // simulate Apple wiping our entry

        let missing = try InjectionEngine.missingIDs(from: url, expected: [a.id, b.id])
        #expect(missing == [a.id])
    }

    /// V27: ensureCategory adds the AerialWall category once. Second inject is idempotent.
    @Test func ensureCategoryIdempotent() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let beforeCount = try EntriesJSONCodec.load(from: url).categories.count

        let a = validAsset()
        let cat = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: a.id,
            previewImageURL: "file:///tmp/x.png"
        )
        try InjectionEngine.inject(a, into: url, ensureCategory: cat)
        let afterFirst = try EntriesJSONCodec.load(from: url)
        #expect(afterFirst.categories.count == beforeCount + 1)
        #expect(afterFirst.categories.contains { $0.id == Constants.AerialWallCategory.categoryID })

        // Inject same asset again with same category — count stays put.
        try InjectionEngine.inject(a, into: url, ensureCategory: cat)
        let afterSecond = try EntriesJSONCodec.load(from: url)
        #expect(afterSecond.categories.count == beforeCount + 1)
    }

    @Test func aerialWallCategoryUUIDsAreValidUppercase() {
        let cat = Constants.AerialWallCategory.categoryID
        let sub = Constants.AerialWallCategory.subcategoryID
        #expect(UUID(uuidString: cat) != nil)
        #expect(UUID(uuidString: sub) != nil)
        #expect(cat == cat.uppercased())
        #expect(sub == sub.uppercased())
        #expect(cat != sub)
    }

    /// Stock entries are untouched by inject/remove of an AerialWall id.
    @Test func stockAssetsPreservedAcrossMutations() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let stockIDsBefore = try EntriesJSONCodec.load(from: url).assets.map(\.id)

        let a = validAsset()
        try InjectionEngine.inject(a, into: url)
        try InjectionEngine.remove(id: a.id, from: url)

        let stockIDsAfter = try EntriesJSONCodec.load(from: url).assets.map(\.id)
        #expect(stockIDsBefore == stockIDsAfter)
    }
}

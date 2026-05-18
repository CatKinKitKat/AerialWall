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

    /// Variant whose categories/subcategories reference the AerialWall custom
    /// category — for tests that exercise upsertCategory/maintaining logic.
    private func aerialWallAsset(id: String) -> Asset {
        Asset(
            id: id,
            accessibilityLabel: "AerialWall Test",
            categories: [Constants.AerialWallCategory.categoryID],
            subcategories: [Constants.AerialWallCategory.subcategoryID],
            includeInShuffle: true,
            localizedNameKey: "AerialWall Test",
            preferredOrder: 1,
            previewImage: "https://x/p.png",
            shotID: "AERIALWALL_TEST",
            showInTopLevel: true,
            urlSDR4K240: "https://x/v.mov"
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

    /// V27: upsertCategory adds the AerialWall category once. Second inject is idempotent.
    @Test func upsertCategoryIdempotent() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let beforeCount = try EntriesJSONCodec.load(from: url).categories.count

        let a = validAsset()
        let cat = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: a.id,
            previewImageURL: "https://x/x.png"
        )
        try InjectionEngine.inject(a, into: url, upsertCategory: cat)
        let afterFirst = try EntriesJSONCodec.load(from: url)
        #expect(afterFirst.categories.count == beforeCount + 1)
        #expect(afterFirst.categories.contains { $0.id == Constants.AerialWallCategory.categoryID })

        try InjectionEngine.inject(a, into: url, upsertCategory: cat)
        let afterSecond = try EntriesJSONCodec.load(from: url)
        #expect(afterSecond.categories.count == beforeCount + 1)
    }

    /// V43: upsertCategory on a pre-existing category refreshes rep + previewImage
    /// so they keep pointing at a currently-existing asset.
    @Test func upsertCategoryRefreshesRep() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let firstAsset = validAsset(id: "11111111-1111-1111-1111-111111111111")
        let firstCat = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: firstAsset.id,
            previewImageURL: "https://first.example/p.png"
        )
        try InjectionEngine.inject(firstAsset, into: url, upsertCategory: firstCat)

        let secondAsset = validAsset(id: "22222222-2222-2222-2222-222222222222")
        let secondCat = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: secondAsset.id,
            previewImageURL: "https://second.example/p.png"
        )
        try InjectionEngine.inject(secondAsset, into: url, upsertCategory: secondCat)

        let loaded = try EntriesJSONCodec.load(from: url)
        let our = loaded.categories.first { $0.id == Constants.AerialWallCategory.categoryID }!
        #expect(our.representativeAssetID == secondAsset.id)
        #expect(our.previewImage == "https://second.example/p.png")
        for sub in our.subcategories {
            #expect(sub.representativeAssetID == secondAsset.id)
            #expect(sub.previewImage == "https://second.example/p.png")
        }
    }

    /// V43: remove() reassigns rep when the removed asset was the category's representative.
    @Test func removeReassignsCategoryRepWhenAssetsRemain() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = aerialWallAsset(id: "11111111-1111-1111-1111-111111111111")
        let b = aerialWallAsset(id: "22222222-2222-2222-2222-222222222222")
        let catA = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: a.id, previewImageURL: "https://a/p.png")
        let catB = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: b.id, previewImageURL: "https://b/p.png")
        try InjectionEngine.inject(a, into: url, upsertCategory: catA)
        try InjectionEngine.inject(b, into: url, upsertCategory: catB)
        // Category rep is now b. Remove b → rep must fall back to a.
        try InjectionEngine.remove(id: b.id, from: url)
        let loaded = try EntriesJSONCodec.load(from: url)
        let our = loaded.categories.first { $0.id == Constants.AerialWallCategory.categoryID }!
        #expect(our.representativeAssetID == a.id)
    }

    /// V43: remove() strips the custom category entirely when no AerialWall assets remain.
    @Test func removeStripsCategoryWhenEmpty() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = aerialWallAsset(id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let cat = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: a.id, previewImageURL: "https://a/p.png")
        try InjectionEngine.inject(a, into: url, upsertCategory: cat)
        try InjectionEngine.remove(id: a.id, from: url)
        let loaded = try EntriesJSONCodec.load(from: url)
        #expect(!loaded.categories.contains { $0.id == Constants.AerialWallCategory.categoryID })
        // Stock categories survive (V28).
        #expect(loaded.categories.contains { $0.id == Constants.StockCategory.landscapes })
    }

    /// V28: remove() never touches stock Apple categories even if they end up empty.
    @Test func removeNeverDropsStockCategories() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let stockCountBefore = try EntriesJSONCodec.load(from: url).categories.count
        let a = aerialWallAsset(id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let cat = InjectionEngine.makeAerialWallCategory(
            representativeAssetID: a.id, previewImageURL: "https://a/p.png")
        try InjectionEngine.inject(a, into: url, upsertCategory: cat)
        try InjectionEngine.remove(id: a.id, from: url)
        let stockCountAfter = try EntriesJSONCodec.load(from: url).categories.count
        #expect(stockCountAfter == stockCountBefore)
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

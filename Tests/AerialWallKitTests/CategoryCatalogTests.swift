import Testing
import Foundation
@testable import AerialWallKit

@Suite("CategoryCatalog & AerialWallEntry backward-compat decode")
struct CategoryCatalogTests {

    @Test func displayNameStripsApplePrefixes() {
        #expect(CategoryCatalog.displayName(from: "AerialSubcategoryTahoe") == "Tahoe")
        #expect(CategoryCatalog.displayName(from: "AerialCategoryLandscapes") == "Landscapes")
        #expect(CategoryCatalog.displayName(from: "AerialSubcategoryEarthFromAbove") == "Earth From Above")
    }

    @Test func availableOptionsFallsBackWhenEntriesAbsent() {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).json")
        let opts = CategoryCatalog.availableOptions(at: nowhere)
        #expect(opts.count == 1)
        #expect(opts.first?.id == Constants.StockCategory.tahoeSubcategory)
        #expect(opts.first?.parentID == Constants.StockCategory.landscapes)
    }

    /// Decoding a manifest produced before description/categoryID existed must
    /// succeed and supply the defaults (Constants.StockCategory.*).
    @Test func decodesLegacyManifestWithoutNewFields() throws {
        let legacy = """
        {
          "schemaVersion": 1,
          "entriesSchemaSeen": 1,
          "wallpapers": [
            {
              "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "name": "Old Wallpaper",
              "originalFilename": "old.mp4",
              "importedAt": "2026-05-18T15:00:00Z",
              "durationSeconds": 30,
              "resolution": "3840x2160",
              "videoPath": "/some/old/path.mov",
              "thumbPath": "/some/old/thumb.png",
              "isInjected": true
            }
          ]
        }
        """
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(legacy.utf8).write(to: tmp)

        let manifest = try AerialWallManifestStore.load(from: tmp)
        #expect(manifest.wallpapers.count == 1)
        let entry = manifest.wallpapers[0]
        #expect(entry.name == "Old Wallpaper")
        #expect(entry.description == "")
        #expect(entry.categoryID == Constants.StockCategory.landscapes)
        #expect(entry.subcategoryID == Constants.StockCategory.tahoeSubcategory)
    }
}

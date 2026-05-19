import Testing
import Foundation
@testable import AerialWallKit

@Suite("WallpaperSetter — V25 apply, V53 multi-display clear")
struct WallpaperSetterTests {

    /// Make a minimal Index.plist resembling the real Tahoe layout.
    private func makeSandbox(prefill: [String: Any] = [:]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "wpsetter-\(UUID().uuidString).plist")
        var seed: [String: Any] = [
            "AllSpacesAndDisplays": ["Type": "linked"] as [String: Any],
            "SystemDefault":        ["Type": "linked"] as [String: Any],
            "Displays":             ["display-uuid-1": ["something": "preserve-not"]] as [String: Any],
            "Spaces":               ["space-uuid-1":   ["something": "preserve-not"]] as [String: Any],
        ]
        for (k, v) in prefill { seed[k] = v }
        let data = try PropertyListSerialization.data(
            fromPropertyList: seed, format: .binary, options: 0)
        try data.write(to: tmp)
        return tmp
    }

    private func readPlist(_ url: URL) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), options: [], format: nil) as! [String: Any]
    }

    @Test func applyWritesAssetIDIntoBothBlocks() throws {
        let url = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: url) }

        let id = "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB"
        try WallpaperSetter.apply(assetID: id, indexPlistURL: url, signalAgent: false)

        let outer = try readPlist(url)
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            let block   = outer[key] as! [String: Any]
            #expect(block["Type"] as? String == "linked")
            let linked  = block["Linked"] as! [String: Any]
            let content = linked["Content"] as! [String: Any]
            let choices = content["Choices"] as! [[String: Any]]
            #expect(choices.count == 1)
            #expect(choices[0]["Provider"] as? String == "com.apple.wallpaper.choice.aerials")
            // Configuration is a nested binary plist with {"assetID": "<UUID>"}
            let configData = choices[0]["Configuration"] as! Data
            let cfg = try PropertyListSerialization.propertyList(
                from: configData, options: [], format: nil) as! [String: Any]
            #expect(cfg["assetID"] as? String == id)
        }
    }

    @Test func applyClearsPerDisplayAndPerSpaceOverrides() throws {
        let url = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: url) }

        try WallpaperSetter.apply(
            assetID: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB",
            indexPlistURL: url,
            signalAgent: false)

        let outer = try readPlist(url)
        let displays = outer["Displays"] as! [String: Any]
        let spaces   = outer["Spaces"]   as! [String: Any]
        #expect(displays.isEmpty)
        #expect(spaces.isEmpty)
    }

    @Test func applyMissingIndexPlistThrows() {
        let nowhere = FileManager.default.temporaryDirectory
            .appending(path: "no-such-\(UUID().uuidString).plist")
        #expect(throws: WallpaperSetterError.self) {
            try WallpaperSetter.apply(
                assetID: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB",
                indexPlistURL: nowhere,
                signalAgent: false)
        }
    }

    @Test func applyCorruptPlistThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "corrupt-\(UUID().uuidString).plist")
        try Data("this is not a plist".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: WallpaperSetterError.self) {
            try WallpaperSetter.apply(
                assetID: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB",
                indexPlistURL: url,
                signalAgent: false)
        }
    }
}

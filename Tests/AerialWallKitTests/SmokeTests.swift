import Testing
@testable import AerialWallKit

@Test func kitVersionIsSemverShape() {
    let parts = AerialWallKit.version.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}

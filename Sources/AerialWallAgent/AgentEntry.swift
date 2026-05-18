import Foundation
import AerialWallKit

@main
struct AgentEntry {
    static func main() {
        FileHandle.standardError.write(
            Data("AerialWallAgent v\(AerialWallKit.version) — placeholder, watcher lands in T9\n".utf8)
        )
    }
}

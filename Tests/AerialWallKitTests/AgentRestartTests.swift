import Testing
import Foundation
@testable import AerialWallKit

@Suite("AgentRestart — V16 SIGTERM, V17 PID parse, V18 respawn wait")
struct AgentRestartTests {

    /// V17: parser pulls the PID for the matching label from real launchctl-style output.
    @Test func parsePIDMatchesLabel() {
        let out = """
        -\t0\tcom.apple.AssetCache.agent
        645\t0\tcom.apple.wallpaper.agent
        -\t0\tcom.apple.bookassetd
        7511\t0\tcom.apple.jetpackassetd
        """
        let pid = AgentRestart.parsePID(label: "com.apple.wallpaper.agent", in: out)
        #expect(pid == 645)
    }

    @Test func parsePIDReturnsNilWhenLabelMissing() {
        let out = "-\t0\tcom.apple.AssetCache.agent\n7511\t0\tcom.apple.jetpackassetd"
        #expect(AgentRestart.parsePID(label: "com.apple.wallpaper.agent", in: out) == nil)
    }

    @Test func parsePIDReturnsNilWhenColumnIsDash() {
        let out = "-\t0\tcom.apple.wallpaper.agent"
        #expect(AgentRestart.parsePID(label: "com.apple.wallpaper.agent", in: out) == nil)
    }

    /// Live test: WallpaperAgent is running on macOS — findAgentPID should succeed.
    /// Doesn't restart it (disruptive).
    @Test func livePIDLookupSucceedsOnTahoe() throws {
        let pid = try AgentRestart.findAgentPID()
        #expect(pid != nil, "expected com.apple.wallpaper.agent to be running")
        if let pid { #expect(pid > 0) }
    }

    /// V18 negative path: looking up a label that doesn't exist returns nil cleanly.
    @Test func findAgentPIDReturnsNilForUnknownLabel() throws {
        let pid = try AgentRestart.findAgentPID(label: "com.aerialwall.definitely-not-loaded")
        #expect(pid == nil)
    }
}

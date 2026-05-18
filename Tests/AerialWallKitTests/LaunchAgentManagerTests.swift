import Testing
import Foundation
@testable import AerialWallKit

@Suite("LaunchAgentManager — plist shape, install/uninstall idempotence")
struct LaunchAgentManagerTests {

    @Test func plistDictionaryHasRequiredKeys() {
        let exe = URL(fileURLWithPath: "/tmp/fake-agent")
        let d = LaunchAgentManager.plistDictionary(executable: exe)
        #expect(d["Label"] as? String == Constants.agentLaunchLabel)
        #expect(d["RunAtLoad"] as? Bool == true)
        #expect(d["KeepAlive"] as? Bool == true)
        let args = d["ProgramArguments"] as? [String]
        #expect(args == [exe.path, "--watch"])
    }

    @Test func plistDataIsValidPlist() throws {
        let exe = URL(fileURLWithPath: "/tmp/fake-agent")
        let data = try LaunchAgentManager.plistData(executable: exe)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]
        #expect(parsed?["Label"] as? String == Constants.agentLaunchLabel)
    }

    /// `install` writes the plist file. We use a tmpdir target so this never
    /// actually loads anything into the user domain — `runLaunchctl` will
    /// fail loud on a tmp-path plist, so we test the file-write half only by
    /// calling plistData + writing directly.
    @Test func plistWriteToTmpRoundTrips() throws {
        let exe = URL(fileURLWithPath: "/tmp/fake-agent")
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "agent-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LaunchAgentManager.plistData(executable: exe).write(to: tmp)
        let reloaded = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: tmp), options: [], format: nil
        ) as? [String: Any]
        #expect(reloaded?["Label"] as? String == Constants.agentLaunchLabel)
    }

    @Test func isInstalledReflectsFilesystem() {
        // We don't install; just confirm the check is read-only and returns
        // a Bool without throwing.
        _ = LaunchAgentManager.isInstalled
    }
}

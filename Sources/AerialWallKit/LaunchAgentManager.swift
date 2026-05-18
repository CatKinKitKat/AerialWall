import Foundation

public enum LaunchAgentError: Error, Equatable {
    case launchctlFailed(exitCode: Int32, stderr: String)
}

public enum LaunchAgentManager {

    /// Build the plist dictionary AerialWallAgent will be registered with.
    /// Exposed pure-ish so tests can assert structure without writing to disk.
    public static func plistDictionary(executable: URL) -> [String: Any] {
        [
            "Label": Constants.agentLaunchLabel,
            "ProgramArguments": [executable.path, "--watch"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardErrorPath": "/tmp/aerialwall.agent.err",
            "StandardOutPath": "/tmp/aerialwall.agent.out",
        ] as [String: Any]
    }

    public static func plistData(executable: URL) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: plistDictionary(executable: executable),
            format: .xml, options: 0
        )
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Constants.launchAgentPlist.path)
    }

    /// Write the plist, then `launchctl load -w` it into the user domain.
    /// `executable` is the absolute path of AerialWallAgent's binary.
    public static func install(executable: URL,
                               at plistURL: URL = Constants.launchAgentPlist) throws {
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try plistData(executable: executable)
        try data.write(to: plistURL, options: .atomic)
        try runLaunchctl(["load", "-w", plistURL.path])
    }

    /// `launchctl unload -w` then delete the plist file.
    public static func uninstall(at plistURL: URL = Constants.launchAgentPlist) throws {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            // unload tolerates "already unloaded"; swallow non-zero here so
            // uninstall is always idempotent.
            _ = try? runLaunchctl(["unload", "-w", plistURL.path])
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            throw LaunchAgentError.launchctlFailed(
                exitCode: proc.terminationStatus, stderr: stderr
            )
        }
        return ""
    }
}

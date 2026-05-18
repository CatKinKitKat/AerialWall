import Foundation
import Darwin

public enum AgentRestartError: Error, Equatable {
    case agentNotFound(label: String)
    case launchctlFailed(exitCode: Int32)
    case signalFailed(errno: Int32)
    case respawnTimeout
}

public enum AgentRestart {

    /// V17: parse `launchctl list`. Output is TSV: PID \t status \t label.
    /// Column 1 may be `-` when the agent is registered but not running.
    public static func findAgentPID(label: String = Constants.wallpaperAgentLabel) throws -> pid_t? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw AgentRestartError.launchctlFailed(exitCode: proc.terminationStatus)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return parsePID(label: label, in: text)
    }

    /// Pure parser — exposed for unit tests.
    static func parsePID(label: String, in launchctlOutput: String) -> pid_t? {
        for line in launchctlOutput.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3, String(cols[2]) == label else { continue }
            return pid_t(cols[0])  // nil if column is "-"
        }
        return nil
    }

    /// V16 + V18: send SIGTERM, wait for launchd to respawn with a new PID.
    /// Returns the new PID. `timeout` is the upper bound on respawn delay.
    @discardableResult
    public static func restart(
        label: String = Constants.wallpaperAgentLabel,
        timeout: TimeInterval = 5
    ) async throws -> pid_t {
        guard let oldPID = try findAgentPID(label: label) else {
            throw AgentRestartError.agentNotFound(label: label)
        }
        if kill(oldPID, SIGTERM) != 0 {
            throw AgentRestartError.signalFailed(errno: errno)
        }
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if let newPID = try? findAgentPID(label: label), newPID != oldPID {
                return newPID
            }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }
        throw AgentRestartError.respawnTimeout
    }
}

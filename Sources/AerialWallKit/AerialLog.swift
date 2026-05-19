import os

/// V51: structured logging via `os.Logger`. One subsystem, per-engine category.
/// View live in Console.app with subsystem == "com.aerialwall.kit".
public enum AerialLog {
    private static let subsystem = "com.aerialwall.kit"

    public static let injection  = Logger(subsystem: subsystem, category: "injection")
    public static let transcode  = Logger(subsystem: subsystem, category: "transcode")
    public static let agent      = Logger(subsystem: subsystem, category: "agent")
    public static let watcher    = Logger(subsystem: subsystem, category: "watcher")
    public static let setter     = Logger(subsystem: subsystem, category: "setter")
    public static let backup     = Logger(subsystem: subsystem, category: "backup")
    public static let manifest   = Logger(subsystem: subsystem, category: "manifest")
}

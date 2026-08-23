import Foundation

public enum DebugLog {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ENTERCALC_DEBUG_LOGS"] == "1"
    }

    public static func emit(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[\(category)] \(message())")
        // Output is block-buffered when stdout is a pipe or file, so logs from a
        // still-running app would otherwise sit unflushed and appear empty to
        // anything reading them.
        fflush(stdout)
    }
}
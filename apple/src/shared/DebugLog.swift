import Foundation

public enum DebugLog {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ENTERCALC_DEBUG_LOGS"] == "1"
    }

    public static func emit(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[\(category)] \(message())")
    }
}
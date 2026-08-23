import Foundation
import os

/// Signposts around the tap-to-display path, so #90's "median tap-to-display
/// latency reduced by at least 20%" can be *measured* rather than argued.
///
/// The optimisations in #104 removed work that provably sat between the touch
/// and the display update, but the acceptance criterion is a number, and a
/// number needs an instrument. These emit to the Points of Interest category,
/// which Instruments shows without a custom instrument package: record a trace
/// on a device, tap the keypad, and read the interval durations straight off
/// the track.
///
/// Signposts cost a load and a branch when no tool is listening, which is why
/// they are compiled in rather than gated behind a debug flag — a measurement
/// you have to rebuild for is one nobody takes.
public enum InputLatencySignpost {
    public static let subsystem = "com.tipliai.entercalc"

    /// Emitted for the whole press, from the tap being committed to the last
    /// side effect returning.
    public static let pressInterval: StaticString = "keypad press"
    /// Emitted for the calculation and display update alone. The difference
    /// between this and `pressInterval` is what confirmation — haptics, sound,
    /// animation — costs on the critical path, which is the thing #90 suspects.
    public static let resultInterval: StaticString = "keypad result"

    private static let signposter = OSSignposter(
        subsystem: subsystem,
        category: OSLog.Category.pointsOfInterest
    )

    /// Opens the whole-press interval. Paired with `endPress`, so a press that
    /// returns early still closes its interval via `defer`.
    public static func beginPress() -> OSSignpostIntervalState {
        signposter.beginInterval(pressInterval)
    }

    public static func endPress(_ state: OSSignpostIntervalState) {
        signposter.endInterval(pressInterval, state)
    }

    /// Times `body` and returns whatever it returns, so it can wrap an existing
    /// call without restructuring it.
    @discardableResult
    public static func measuring<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return body()
    }
}

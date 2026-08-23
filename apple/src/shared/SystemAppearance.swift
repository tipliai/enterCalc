import SwiftUI

/// Resolution of the operating system's light/dark setting.
///
/// This is deliberately kept separate from `@Environment(\.colorScheme)`. When a
/// platform shell applies its own appearance override to a window (as the macOS
/// app does for the Light/Dark/Blue themes), the ambient color scheme reflects
/// that override rather than the system setting, and it is not guaranteed to be
/// re-resolved at the moment the override is removed. Reading the system setting
/// directly gives the "System" theme a value that never depends on what the app
/// itself last applied.
public enum SystemAppearance {
    /// Maps a raw `AppleInterfaceStyle` value to a color scheme.
    ///
    /// macOS only writes this global-domain key while Dark Mode is enabled; in
    /// Light Mode the key is absent, which is why `nil` maps to `.light`.
    public static func colorScheme(forInterfaceStyle rawValue: String?) -> ColorScheme {
        guard let rawValue else { return .light }
        return rawValue.lowercased().hasPrefix("dark") ? .dark : .light
    }
}

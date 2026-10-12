import SwiftUI

/// The app's Text Size setting (#148): follow the OS text size, or override it
/// for this app with one of five sizes.
///
/// The five sizes follow the common slider-with-stops pattern (iOS's own Text
/// Size, Apple Books, most readers). On iOS each maps to a Dynamic Type size, so
/// everything that already honours Dynamic Type, Settings included, scales the
/// same way it does for the system's larger text. macOS has no Dynamic Type, so
/// it uses `relativeScale` directly.
public enum TextSizePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case extraSmall
    case small
    case standard
    case large
    case extraLarge

    public static let storageKey = "settings.textSize"

    /// The sizes the slider steps through, smallest first.
    public static let sizes: [TextSizePreference] = [.extraSmall, .small, .standard, .large, .extraLarge]

    public var id: String { rawValue }

    public init(storedValue: String) {
        self = TextSizePreference(rawValue: storedValue) ?? .system
    }

    public var followsSystem: Bool { self == .system }

    /// Position on the slider, or nil when following the system.
    public var sizeIndex: Int? { Self.sizes.firstIndex(of: self) }

    public static func size(atIndex index: Int) -> TextSizePreference {
        sizes[min(max(index, 0), sizes.count - 1)]
    }

    /// The Dynamic Type size this override stands for, or nil to follow the OS.
    public var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: return nil
        case .extraSmall: return .xSmall
        case .small: return .small
        case .standard: return .large
        case .large: return .xxLarge
        case .extraLarge: return .accessibility1
        }
    }

    /// Text scale relative to the default size, matching the body-text ratios of
    /// the Dynamic Type sizes above (14, 15, 17, 21 and 28pt against 17pt).
    /// Nil when following the OS.
    public var relativeScale: CGFloat? {
        switch self {
        case .system: return nil
        case .extraSmall: return 14.0 / 17.0
        case .small: return 15.0 / 17.0
        case .standard: return 1
        case .large: return 21.0 / 17.0
        case .extraLarge: return 28.0 / 17.0
        }
    }

    public var localizationKey: String {
        switch self {
        case .system: return "settings.textSize.useSystem"
        case .extraSmall: return "settings.textSize.extraSmall"
        case .small: return "settings.textSize.small"
        case .standard: return "settings.textSize.standard"
        case .large: return "settings.textSize.large"
        case .extraLarge: return "settings.textSize.extraLarge"
        }
    }
}

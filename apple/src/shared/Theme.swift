import SwiftUI

/// Central palette for light/dark themes to avoid scattered color literals.
public struct Palette {
    public let surface: Color
    public let panel: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let accent: Color
    public let accentText: Color
    public let accentGradientStart: Color
    public let accentGradientMid: Color
    public let accentGradientEnd: Color
    public let buttonNumber: Color
    public let buttonOperation: Color
    public let buttonFunction: Color
    public let buttonHighlight: Color
    public let buttonBorder: Color
    public let buttonHoverOverlay: Color
    public let operatorColumnTop: Color
    public let operatorColumnBottom: Color
    public let memoryControlActive: Color
    public let memoryControlDisabled: Color
    public let headerHover: Color
    public let historyBackground: Color
    public let historyTileBackground: Color

    /// Titles of the right-column operator/equals buttons, ordered top→bottom.
    public static let operatorColumnTitles: [String] = ["÷", "×", "−", "+", "="]

    /// Returns a solid color for a right-column button at `index` out of `total`,
    /// interpolated between `operatorColumnTop` and `operatorColumnBottom`.
    public func operatorColumnColor(at index: Int) -> Color {
        let total = Palette.operatorColumnTitles.count
        let t = total > 1 ? CGFloat(index) / CGFloat(total - 1) : 0
        let sr: CGFloat = 0.6118, sg: CGFloat = 0.7725, sb: CGFloat = 0.9882 // #9cc5fc
        let er: CGFloat = 0,      eg: CGFloat = 0.3529, eb: CGFloat = 1.0    // #005aff
        return Color(red: sr + t * (er - sr), green: sg + t * (eg - sg), blue: sb + t * (eb - sb))
    }

    /// Returns the operator column color for a given button title, or nil if not in the column.
    public func operatorColumnColor(for title: String) -> Color? {
        guard let index = Palette.operatorColumnTitles.firstIndex(of: title) else { return nil }
        return operatorColumnColor(at: index)
    }

    public static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }

    private static let darkTextPrimary = Color(red: 0.9176, green: 0.9176, blue: 0.9176) // #eaeaea
    private static let lightTextPrimary = Color(red: 0.0980, green: 0.0980, blue: 0.0980) // #191919

    public static let dark = Palette(
        surface: Color(red: 0.1137, green: 0.1137, blue: 0.1137), // #1d1d1d
        panel: Color(red: 0.1686, green: 0.1686, blue: 0.1686), // #2b2b2b
        textPrimary: darkTextPrimary,
        textSecondary: darkTextPrimary.opacity(0.65),
        accent: Color(red: 0.0, green: 0.3608, blue: 0.7216), // #005cb8 — matches light theme
        accentText: darkTextPrimary,
        accentGradientStart: Color(red: 0.2392, green: 0.3176, blue: 0.7647), // #3d51c3
        accentGradientMid: Color(red: 0.2313, green: 0.1764, blue: 0.8510),   // #3b2dd9
        accentGradientEnd: Color(red: 0.1411, green: 0.1020, blue: 0.6823),   // #241aad
        buttonNumber: Color(red: 0.2039, green: 0.2039, blue: 0.2039), // #343434
        buttonOperation: Color(red: 0.1686, green: 0.1686, blue: 0.1686), // #2b2b2b
        buttonFunction: Color(red: 0.1686, green: 0.1686, blue: 0.1686), // #2b2b2b
        buttonHighlight: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        buttonBorder: Color.white.opacity(0.05),
        buttonHoverOverlay: Color.black.opacity(0.12),
        operatorColumnTop: Color(red: 0.6118, green: 0.7725, blue: 0.9882),    // #9cc5fc
        operatorColumnBottom: Color(red: 0, green: 0.3529, blue: 1.0),         // #005aff
        memoryControlActive: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        memoryControlDisabled: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        headerHover: Color.white.opacity(0.08),
        historyBackground: Color(red: 0.1137, green: 0.1137, blue: 0.1137), // match surface
        historyTileBackground: Color.white.opacity(0.05)
    )

    public static let light = Palette(
        surface: Color(red: 0.9451, green: 0.9451, blue: 0.9451), // #f1f1f1
        panel: Color(red: 0.9725, green: 0.9725, blue: 0.9725), // #f8f8f8
        textPrimary: lightTextPrimary,
        textSecondary: lightTextPrimary.opacity(0.65),
        accent: Color(red: 0.0, green: 0.3608, blue: 0.7216), // #005cb8
        accentText: Color.white,
        accentGradientStart: Color(red: 0.2392, green: 0.3176, blue: 0.7647), // #3d51c3
        accentGradientMid: Color(red: 0.2313, green: 0.1764, blue: 0.8510),   // #3b2dd9
        accentGradientEnd: Color(red: 0.1411, green: 0.1020, blue: 0.6823),   // #241aad
        buttonNumber: Color.white, // #ffffff
        buttonOperation: Color(red: 0.9725, green: 0.9725, blue: 0.9725), // #f8f8f8
        buttonFunction: Color(red: 0.9725, green: 0.9725, blue: 0.9725), // #f8f8f8
        buttonHighlight: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        buttonBorder: Color.black.opacity(0.05),
        buttonHoverOverlay: Color.black.opacity(0.06),
        operatorColumnTop: Color(red: 0.6118, green: 0.7725, blue: 0.9882),    // #9cc5fc
        operatorColumnBottom: Color(red: 0, green: 0.3529, blue: 1.0),         // #005aff
        memoryControlActive: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        memoryControlDisabled: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        headerHover: Color.black.opacity(0.08),
        historyBackground: Color(red: 0.9451, green: 0.9451, blue: 0.9451), // match surface
        historyTileBackground: Color.black.opacity(0.05)
    )

    public static let blue = Palette(
        surface: Color(red: 0.388, green: 0.451, blue: 0.980),
        panel: Color(red: 0.356, green: 0.420, blue: 0.949),
        textPrimary: Color.white.opacity(0.97),
        textSecondary: Color.white.opacity(0.72),
        accent: Color(red: 0.965, green: 0.969, blue: 0.982),
        accentText: Color(red: 0.113, green: 0.113, blue: 0.113),
        accentGradientStart: Color(red: 1.0, green: 1.0, blue: 1.0),
        accentGradientMid: Color(red: 0.958, green: 0.964, blue: 0.982),
        accentGradientEnd: Color(red: 0.860, green: 0.890, blue: 0.945),
        buttonNumber: Color(red: 0.258, green: 0.337, blue: 0.920),
        buttonOperation: Color(red: 0.258, green: 0.337, blue: 0.920),
        buttonFunction: Color(red: 0.258, green: 0.337, blue: 0.920),
        buttonHighlight: Color(red: 0.803, green: 0.878, blue: 1.0),
        buttonBorder: Color.white.opacity(0.06),
        buttonHoverOverlay: Color.black.opacity(0.08),
        operatorColumnTop: Color(red: 0.678, green: 0.804, blue: 1.0),
        operatorColumnBottom: Color(red: 0.290, green: 0.455, blue: 1.0),
        memoryControlActive: Color(red: 0.803, green: 0.878, blue: 1.0),
        memoryControlDisabled: Color(red: 0.803, green: 0.878, blue: 1.0),
        headerHover: Color.white.opacity(0.12),
        historyBackground: Color(red: 0.246, green: 0.318, blue: 0.870),
        historyTileBackground: Color.white.opacity(0.08)
    )
}

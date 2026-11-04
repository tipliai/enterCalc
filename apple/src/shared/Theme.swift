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
    public let accentGradientEnd: Color
    public let buttonNumber: Color
    public let buttonOperation: Color
    public let buttonFunction: Color
    public let buttonHighlight: Color
    public let buttonBorder: Color
    public let buttonHoverOverlay: Color
    public let memoryControlActive: Color
    public let memoryControlDisabled: Color
    public let headerHover: Color
    public let historyBackground: Color
    public let historyTileBackground: Color
    /// The folded-down corner on keys whose function can be changed (#131).
    public var functionKeyEar: Color = .clear
    /// An extra middle stop for the gradient at 0.42; only the Blue theme
    /// keeps one, so its white fills look as they always have.
    public var accentGradientMid: Color? = nil
    /// The link colour, where it differs from `accent`; nil uses `accent`.
    public var foregroundAccentOverride: Color? = nil

    /// Links and thin accent lines (#137): the OS blue a shade darker on light
    /// themes (#0066cc) and a shade lighter on dark ones (#47a3ff), so link
    /// text keeps at least 4.5:1 against the background. No one colour can do
    /// that on both. Fills keep the gradient.
    public var foregroundAccent: Color { foregroundAccentOverride ?? accent }

    /// The slider and page-dot colour, where it differs from `foregroundAccent`.
    public var sliderTintOverride: Color? = nil

    /// Sliders and the active page dot: the OS blue (#0a84ff) on light and
    /// dark themes alike. As graphics they need 3:1, which it meets on both.
    public var sliderTint: Color { sliderTintOverride ?? foregroundAccent }

    /// The app's one accent treatment: the Enter key's gradient (#137), from
    /// #3d51c3 at the top left to the OS blue at the bottom right (#007aff on
    /// light themes, #0a84ff on dark). Every accent fill uses it, from the
    /// Enter key to highlighted keys and selected chips. Two stops on light
    /// and dark themes, so the blend has no band of a third colour through
    /// the middle.
    public var accentGradient: LinearGradient {
        var stops: [Gradient.Stop] = [.init(color: accentGradientStart, location: 0.0)]
        if let accentGradientMid {
            stops.append(.init(color: accentGradientMid, location: 0.42))
        }
        stops.append(.init(color: accentGradientEnd, location: 1.0))
        return LinearGradient(
            stops: stops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Titles of the right-column operator/equals buttons, ordered top→bottom.
    public static let operatorColumnTitles: [String] = ["÷", "×", "−", "+", "="]

    /// Returns a solid color for a right-column button at `index` out of `total`
    /// for the launch animation, following the Enter key's gradient: the OS
    /// blue at the top (÷) down to #3d51c3 at the bottom, shared by all themes.
    public func operatorColumnColor(at index: Int) -> Color {
        let total = Palette.operatorColumnTitles.count
        let t = total > 1 ? CGFloat(index) / CGFloat(total - 1) : 0
        let sr: CGFloat = 0.0392, sg: CGFloat = 0.5176, sb: CGFloat = 1.0    // #0a84ff (OS blue)
        let er: CGFloat = 0.2392, eg: CGFloat = 0.3176, eb: CGFloat = 0.7647 // #3d51c3
        return Color(red: sr + t * (er - sr), green: sg + t * (eg - sg), blue: sb + t * (eb - sb))
    }

    /// Returns the operator column color for a given button title, or nil if not in the column.
    public func operatorColumnColor(for title: String) -> Color? {
        guard let index = Palette.operatorColumnTitles.firstIndex(of: title) else { return nil }
        return operatorColumnColor(at: index)
    }

    public static func forScheme(_ scheme: ColorScheme, increasedContrast: Bool = false) -> Palette {
        let base = scheme == .dark ? Palette.dark : Palette.light
        return increasedContrast
            ? base.adjustedForIncreasedContrast(isDarkLike: scheme == .dark, isBlueLike: false)
            : base
    }

    public func adjustedForIncreasedContrast(isDarkLike: Bool, isBlueLike: Bool = false) -> Palette {
        let highContrastPrimary = isDarkLike ? Color.white : Color.black
        let highContrastSecondary = highContrastPrimary.opacity(isDarkLike ? 0.92 : 0.84)
        let highContrastSurface = isBlueLike
            ? Color(red: 0.282, green: 0.353, blue: 0.874)
            : (isDarkLike ? Color(red: 0.090, green: 0.090, blue: 0.090) : Color(red: 0.968, green: 0.968, blue: 0.968))
        let highContrastPanel = isBlueLike
            ? Color(red: 0.226, green: 0.298, blue: 0.828)
            : (isDarkLike ? Color(red: 0.136, green: 0.136, blue: 0.136) : Color(red: 0.992, green: 0.992, blue: 0.992))
        let highContrastButtonNumber = isBlueLike
            ? Color(red: 0.184, green: 0.255, blue: 0.790)
            : (isDarkLike ? Color(red: 0.180, green: 0.180, blue: 0.180) : Color.white)
        let highContrastButtonSurface = isBlueLike
            ? Color(red: 0.184, green: 0.255, blue: 0.790)
            : (isDarkLike ? Color(red: 0.130, green: 0.130, blue: 0.130) : Color(red: 0.925, green: 0.925, blue: 0.925))

        return Palette(
            surface: highContrastSurface,
            panel: highContrastPanel,
            textPrimary: highContrastPrimary,
            textSecondary: highContrastSecondary,
            accent: isBlueLike ? Color.white : accent,
            accentText: accentText,
            accentGradientStart: accentGradientStart,
            accentGradientEnd: accentGradientEnd,
            buttonNumber: highContrastButtonNumber,
            buttonOperation: highContrastButtonSurface,
            buttonFunction: highContrastButtonSurface,
            buttonHighlight: isBlueLike ? Color(red: 0.812, green: 0.894, blue: 1.0) : (isDarkLike ? buttonHighlight : Color(red: 0.52, green: 0.70, blue: 0.95)),
            buttonBorder: isDarkLike ? Color.white.opacity(isBlueLike ? 0.26 : 0.24) : Color.black.opacity(0.24),
            buttonHoverOverlay: isDarkLike ? Color.white.opacity(isBlueLike ? 0.18 : 0.16) : Color.black.opacity(0.14),
            memoryControlActive: memoryControlActive,
            memoryControlDisabled: memoryControlActive.opacity(isDarkLike ? 0.86 : 0.72),
            headerHover: isDarkLike ? Color.white.opacity(isBlueLike ? 0.22 : 0.2) : Color.black.opacity(0.16),
            historyBackground: highContrastSurface,
            historyTileBackground: isDarkLike ? Color.white.opacity(isBlueLike ? 0.15 : 0.13) : Color.black.opacity(0.11),
            functionKeyEar: isBlueLike ? Color.white.opacity(0.45) : (isDarkLike ? Color.white.opacity(0.30) : Color.black.opacity(0.22)),
            accentGradientMid: accentGradientMid,
            foregroundAccentOverride: isBlueLike ? nil : foregroundAccentOverride,
            sliderTintOverride: isBlueLike ? nil : sliderTintOverride
        )
    }

    private static let darkTextPrimary = Color(red: 0.9176, green: 0.9176, blue: 0.9176) // #eaeaea
    private static let lightTextPrimary = Color(red: 0.0980, green: 0.0980, blue: 0.0980) // #191919

    public static let dark = Palette(
        surface: Color(red: 0.1137, green: 0.1137, blue: 0.1137), // #1d1d1d
        panel: Color(red: 0.1686, green: 0.1686, blue: 0.1686), // #2b2b2b
        textPrimary: darkTextPrimary,
        textSecondary: darkTextPrimary.opacity(0.65),
        accent: Color(red: 0.1412, green: 0.4157, blue: 0.8824), // #246ae1, the gradient's midpoint
        // Pure white: the light grey of the dark theme's text only reaches
        // 4.1:1 in the middle of the gradient, white 5.0:1.
        accentText: Color.white,
        accentGradientStart: Color(red: 0.2392, green: 0.3176, blue: 0.7647), // #3d51c3
        accentGradientEnd: Color(red: 0.0392, green: 0.5176, blue: 1.0),      // #0a84ff, the OS blue in dark mode
        buttonNumber: Color(red: 0.2039, green: 0.2039, blue: 0.2039), // #343434
        buttonOperation: Color(red: 0.1686, green: 0.1686, blue: 0.1686), // #2b2b2b
        buttonFunction: Color(red: 0.1686, green: 0.1686, blue: 0.1686), // #2b2b2b
        buttonHighlight: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        buttonBorder: Color.white.opacity(0.05),
        buttonHoverOverlay: Color.black.opacity(0.12),
        memoryControlActive: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        memoryControlDisabled: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        headerHover: Color.white.opacity(0.08),
        historyBackground: Color(red: 0.1137, green: 0.1137, blue: 0.1137), // match surface
        historyTileBackground: Color.white.opacity(0.05),
        functionKeyEar: Color.white.opacity(0.20),
        foregroundAccentOverride: Color(red: 0.2784, green: 0.6392, blue: 1.0), // #47a3ff
        sliderTintOverride: Color(red: 0.0392, green: 0.5176, blue: 1.0)        // #0a84ff
    )

    public static let light = Palette(
        surface: Color(red: 0.9451, green: 0.9451, blue: 0.9451), // #f1f1f1
        panel: Color(red: 0.9725, green: 0.9725, blue: 0.9725), // #f8f8f8
        textPrimary: lightTextPrimary,
        textSecondary: lightTextPrimary.opacity(0.65),
        accent: Color(red: 0.1176, green: 0.4000, blue: 0.8824), // #1e66e1, the gradient's midpoint
        accentText: Color.white,
        accentGradientStart: Color(red: 0.2392, green: 0.3176, blue: 0.7647), // #3d51c3
        accentGradientEnd: Color(red: 0.0, green: 0.4784, blue: 1.0),         // #007aff, the OS blue in light mode
        buttonNumber: Color.white, // #ffffff
        buttonOperation: Color(red: 0.9725, green: 0.9725, blue: 0.9725), // #f8f8f8
        buttonFunction: Color(red: 0.9725, green: 0.9725, blue: 0.9725), // #f8f8f8
        buttonHighlight: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        buttonBorder: Color.black.opacity(0.05),
        buttonHoverOverlay: Color.black.opacity(0.06),
        memoryControlActive: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        memoryControlDisabled: Color(red: 0.6118, green: 0.7725, blue: 0.9882), // #9cc5fc
        headerHover: Color.black.opacity(0.08),
        historyBackground: Color(red: 0.9451, green: 0.9451, blue: 0.9451), // match surface
        historyTileBackground: Color.black.opacity(0.05),
        functionKeyEar: Color.black.opacity(0.13),
        foregroundAccentOverride: Color(red: 0.0, green: 0.4, blue: 0.8),       // #0066cc
        sliderTintOverride: Color(red: 0.0392, green: 0.5176, blue: 1.0)        // #0a84ff
    )

    public static let blue = Palette(
        surface: Color(red: 0.388, green: 0.451, blue: 0.980),
        panel: Color(red: 0.356, green: 0.420, blue: 0.949),
        textPrimary: Color.white.opacity(0.97),
        textSecondary: Color.white.opacity(0.72),
        accent: Color(red: 0.965, green: 0.969, blue: 0.982),
        accentText: Color(red: 0.113, green: 0.113, blue: 0.113),
        accentGradientStart: Color(red: 1.0, green: 1.0, blue: 1.0),
        accentGradientEnd: Color(red: 0.860, green: 0.890, blue: 0.945),
        buttonNumber: Color(red: 0.258, green: 0.337, blue: 0.920),
        buttonOperation: Color(red: 0.258, green: 0.337, blue: 0.920),
        buttonFunction: Color(red: 0.258, green: 0.337, blue: 0.920),
        buttonHighlight: Color(red: 0.803, green: 0.878, blue: 1.0),
        buttonBorder: Color.white.opacity(0.06),
        buttonHoverOverlay: Color.black.opacity(0.08),
        memoryControlActive: Color(red: 0.803, green: 0.878, blue: 1.0),
        memoryControlDisabled: Color(red: 0.803, green: 0.878, blue: 1.0),
        headerHover: Color.white.opacity(0.12),
        historyBackground: Color(red: 0.246, green: 0.318, blue: 0.870),
        historyTileBackground: Color.white.opacity(0.08),
        functionKeyEar: Color.white.opacity(0.34),
        accentGradientMid: Color(red: 0.958, green: 0.964, blue: 0.982)
    )
}

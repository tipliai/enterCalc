import XCTest
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import EnterCalcCore

/// Text on the accent gradient (the Enter key, highlighted keys and selected
/// chips) must stay readable at every stop, in every theme (#137).
final class AccentGradientContrastTests: XCTestCase {
    #if canImport(AppKit)
    private func relativeLuminance(_ color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(ns.redComponent) + 0.7152 * channel(ns.greenComponent) + 0.0722 * channel(ns.blueComponent)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private var palettes: [(String, Palette)] {
        [
            ("light", .light),
            ("dark", .dark),
            ("blue", .blue),
            ("light, increased contrast", Palette.light.adjustedForIncreasedContrast(isDarkLike: false)),
            ("dark, increased contrast", Palette.dark.adjustedForIncreasedContrast(isDarkLike: true)),
            ("blue, increased contrast", Palette.blue.adjustedForIncreasedContrast(isDarkLike: true, isBlueLike: true)),
        ]
    }

    func testAccentTextMeetsAAOnEveryGradientStop() {
        for (name, palette) in palettes {
            for (stop, color) in [("start", palette.accentGradientStart), ("mid", palette.accentGradientMid), ("end", palette.accentGradientEnd)] {
                XCTAssertGreaterThanOrEqual(contrast(palette.accentText, color), 4.5, "\(name): accent text on the gradient \(stop)")
            }
        }
    }

    func testSolidAccentMatchesTheGradientInLightAndDark() {
        for palette in [Palette.light, Palette.dark] {
            XCTAssertEqual(relativeLuminance(palette.accent), relativeLuminance(palette.accentGradientMid), accuracy: 0.0001)
        }
    }
    #endif
}

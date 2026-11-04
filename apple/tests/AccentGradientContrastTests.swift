import XCTest
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import EnterCalcCore

/// Accent colours stay readable in every theme (#137): text on the gradient
/// (the Enter key, highlighted keys and selected chips), links, sliders and
/// the page dot.
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

    private func srgb(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
    }

    /// The colour `t` of the way along a two-stop gradient.
    private func gradientColor(of palette: Palette, at t: CGFloat) -> Color {
        let a = srgb(palette.accentGradientStart), b = srgb(palette.accentGradientEnd)
        return Color(.sRGB, red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }

    /// The colour halfway along the gradient.
    private func midpoint(of palette: Palette) -> Color {
        gradientColor(of: palette, at: 0.5)
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

    /// Normal-size labels (selected chips, highlighted keys) can stretch
    /// across most of a key, so text needs 4.5:1 over the first three quarters
    /// of the gradient. Only the far corner, which no label reaches, may drop
    /// to 3:1, the large-text level (WCAG 1.4.3). Two-stop palettes only; the
    /// Blue theme's white gradient is checked at its stops.
    func testAccentTextReadsOnTheGradient() {
        for (name, palette) in palettes {
            if palette.accentGradientMid == nil {
                for t in stride(from: CGFloat(0), through: 0.75, by: 0.05) {
                    XCTAssertGreaterThanOrEqual(contrast(palette.accentText, gradientColor(of: palette, at: t)), 4.5, "\(name): accent text at \(t) of the gradient")
                }
            } else if let mid = palette.accentGradientMid {
                XCTAssertGreaterThanOrEqual(contrast(palette.accentText, mid), 4.5, "\(name): accent text at the gradient's middle stop")
            }
            for (stop, color) in [("start", palette.accentGradientStart), ("end", palette.accentGradientEnd)] {
                XCTAssertGreaterThanOrEqual(contrast(palette.accentText, color), 3, "\(name): accent text at the gradient \(stop)")
            }
        }
    }

    /// Links and system controls use the foreground accent, which must read
    /// as text (4.5:1) on every background they sit on, in light and dark,
    /// with and without Increase Contrast.
    func testForegroundAccentMeetsAAOnEveryBackground() {
        let themes: [(String, Palette)] = [
            ("light", .light),
            ("dark", .dark),
            ("light, increased contrast", Palette.light.adjustedForIncreasedContrast(isDarkLike: false)),
            ("dark, increased contrast", Palette.dark.adjustedForIncreasedContrast(isDarkLike: true)),
        ]
        for (name, palette) in themes {
            for (background, color) in [("surface", palette.surface), ("panel", palette.panel), ("function key", palette.buttonFunction), ("history", palette.historyBackground)] {
                XCTAssertGreaterThanOrEqual(contrast(palette.foregroundAccent, color), 4.5, "\(name): foreground accent on \(background)")
            }
        }
    }

    /// A slider's fill and the page dot are graphics, so they need 3:1
    /// (WCAG 1.4.11) against the backgrounds they sit on, in every theme.
    func testSliderTintMeetsNonTextContrastOnEveryBackground() {
        for (name, palette) in palettes {
            for (background, color) in [("surface", palette.surface), ("panel", palette.panel), ("function key", palette.buttonFunction), ("history", palette.historyBackground)] {
                XCTAssertGreaterThanOrEqual(contrast(palette.sliderTint, color), 3, "\(name): slider fill on \(background)")
            }
        }
    }

    /// Sliders and the page dot use one OS blue in light and dark alike.
    func testSliderTintIsTheSameInLightAndDark() {
        XCTAssertEqual(relativeLuminance(Palette.light.sliderTint), relativeLuminance(Palette.dark.sliderTint), accuracy: 0.0001)
    }

    /// The solid accent is the gradient's midpoint, so it matches the fills.
    func testSolidAccentIsTheGradientsMidpoint() {
        for palette in [Palette.light, Palette.dark] {
            XCTAssertEqual(relativeLuminance(palette.accent), relativeLuminance(midpoint(of: palette)), accuracy: 0.003)
        }
    }
    #endif
}

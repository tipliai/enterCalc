import SwiftUI
import XCTest
@testable import EnterCalcCore

final class SystemAppearanceTests: XCTestCase {
    // macOS only writes AppleInterfaceStyle while Dark Mode is on; the key is
    // absent in Light Mode, so a missing value must not be treated as unknown.
    func testMissingInterfaceStyleResolvesToLight() {
        XCTAssertEqual(SystemAppearance.colorScheme(forInterfaceStyle: nil), .light)
    }

    func testDarkInterfaceStyleResolvesToDark() {
        XCTAssertEqual(SystemAppearance.colorScheme(forInterfaceStyle: "Dark"), .dark)
    }

    // The accent-tinted variants report values such as "DarkAqua", so matching
    // has to be prefix-based rather than an equality check against "Dark".
    func testDarkVariantInterfaceStylesResolveToDark() {
        XCTAssertEqual(SystemAppearance.colorScheme(forInterfaceStyle: "DarkAqua"), .dark)
        XCTAssertEqual(SystemAppearance.colorScheme(forInterfaceStyle: "dark"), .dark)
    }

    func testUnrecognizedInterfaceStyleResolvesToLight() {
        XCTAssertEqual(SystemAppearance.colorScheme(forInterfaceStyle: "Aqua"), .light)
        XCTAssertEqual(SystemAppearance.colorScheme(forInterfaceStyle: ""), .light)
    }

    // NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) names.
    func testAppearanceNamesResolve() {
        XCTAssertEqual(SystemAppearance.colorScheme(forAppearanceName: "NSAppearanceNameDarkAqua"), .dark)
        XCTAssertEqual(SystemAppearance.colorScheme(forAppearanceName: "NSAppearanceNameAqua"), .light)
        XCTAssertEqual(SystemAppearance.colorScheme(forAppearanceName: "NSAppearanceNameAccessibilityHighContrastDarkAqua"), .dark)
        XCTAssertEqual(SystemAppearance.colorScheme(forAppearanceName: nil), .light)
    }
}
